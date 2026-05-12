# MEDC — Architecture, Roadmap, and Operator Notes

## 1. Vision

MEDC — the **Minimal Extendable Data Centre** — is a lightweight
datacenter-simulation platform. It sits in the same conceptual space as
Proxmox or VMware, but runs an order of magnitude lighter: a single beefy
workstation or home-lab server is enough to stand up a full multi-cluster
Kubernetes environment that mirrors what real customers deploy.

The primary driver is **k0rdent** and **k0smotron** development, testing,
and demoing. MEDC provides the *host-platform* layer — the networked
set of nodes onto which k0rdent is installed and against which k0smotron
bootstraps child clusters. k0rdent installation itself is a post-MEDC
step and lives outside this repo.

Design tenets:

- **One host, whole datacenter.** Everything runs on a single Linux box.
- **Real nodes, not nested abstractions.** System containers (via LXC,
  migrating to Incus) with systemd, SSH, and full networking — not
  Kind/Minikube-style nested images.
- **Extendable.** Hardcoded today, parameterized tomorrow: topology,
  network, credentials, routes all become config-driven.
- **Cheap to rebuild.** Teardown + rebuild on a disposable host must be
  a single command once the refactor lands.

## 2. Current architecture (v0, LXC)

```
┌──────────────────────────────────────────────────────────────┐
│  Host (Debian Trixie, ARM64 or x86_64)                       │
├──────────────────────────────────────────────────────────────┤
│  lxcbr0 — 10.0.3.1/24, dnsmasq DHCP + DNS (lxc.local)        │
│  iptables MASQUERADE out of eth0 for 10.0.3.0/24             │
├──────────┬──────────┬──────────┬────────────────────────────┤
│          │          │          │                            │
│ k0rdent- │ k0s-     │ k0s-     │ k0s-                       │
│ mgmt     │ child-   │ child-   │ child-                     │
│ 10.0.3.10│ master   │ worker1  │ worker2                    │
│          │ 10.0.3.20│ 10.0.3.21│ 10.0.3.22                  │
│ 4G / 2CPU│ 4G / 2CPU│ 4G / 2CPU│ 4G / 2CPU                  │
└──────────┴──────────┴──────────┴────────────────────────────┘
```

### Key facts (baked into scripts today)

- **Bridge:** `lxcbr0`
- **Network:** `10.0.3.0/24`, gateway `10.0.3.1`
- **DNS domain:** `lxc.local`
- **Addressing:** DHCP with **static reservations** keyed on container MAC
  (not hardcoded per-container IPs on the container side — the host
  dnsmasq config pins the mapping). This lets us rebuild a container and
  have it land on the same IP without editing it from inside.
- **NAT:** out of the host's primary interface (`eth0` by default)
- **Rootfs:** Debian Trixie via `lxc-create -t download`
- **Resource limits:** `lxc.cgroup2.memory.max = 4G`,
  `lxc.cgroup2.cpu.max = 200000 1000000` per container
- **Auth:** `robot` user with demo password, sudoers NOPASSWD, SSH
  password + pubkey. **Demo-only.**
- **Kernel tuning applied to containers:** `bridge-nf-call-iptables`,
  `ip_forward`, high `inotify` limits, swap off.

### Script layout

**Core setup**
- `full-medc-setup.sh` — menu-driven installer (prereqs → containers →
  users/SSH → test). Writes `/usr/local/bin/create-k8s-lxc.sh` and
  `/usr/local/bin/test-lxc-network.sh` inline as part of the prereqs
  step.
- `create-containers.sh` — standalone container-creation path; assumes
  `/usr/local/bin/create-k8s-lxc.sh` already exists.
- `init-containers.sh` — in-container package init.

**Hardening**
- `medc-production-ready.sh` — chrony, kernel sysctls, cgroup limits,
  logrotate. Writes `/usr/local/bin/backup-lxc-containers.sh` and
  `/usr/local/bin/maintain-lxc-containers.sh` inline.

**Ops**
- `check-medc-health.sh` — bridge / IP-forward / NAT / container-status
  / connectivity probe.
- `medc-k8s-powerup.sh` — manual or boot-time reconciliation: sysctl,
  kernel modules (`br_netfilter`, `overlay`), iptables, container start.
- `crontab-entry.txt` — suggested cron: `@reboot` health check, daily
  backup, weekly maintenance.

## 3. Target architecture (v1, Incus + gateway)

The refactor replaces the hand-rolled bridge + dnsmasq + iptables plumbing
with **Incus** primitives and introduces a **gateway instance** that
mirrors what a real datacenter does: one router/services VM holding the
DHCP, DNS, NAT, ingress, VPN termination, registry, and binary hosting.
Every hardcoded value moves into a single YAML config (`medc.yaml`).

```
┌─────────────────────────────────────────────────────────────────────┐
│  Host  (Debian Trixie)                                              │
│  • incusd        — instance lifecycle, profiles, storage            │
│  • tailscaled    — superuser/operator tailnet (host troubleshooting)│
│                                                                     │
│  Host uplink NIC ──── (passed into gateway as eth1, macvlan) ───┐   │
│                                                                 │   │
│  Incus bridge medcbr0 (10.0.3.0/24, NAT off, DHCP off, DNS off) │   │
│   │      │      │      │      │                                 │   │
│   │   mgmt   master  worker1 worker2                            │   │
│   │  .10/8G  .20/4G  .21/4G  .22/4G                             │   │
│   │                                                             │   │
│   └─ medc-gateway (.5)                                          │   │
│        • dnsmasq    (DHCP + DNS for the lab)                    │   │
│        • tailscaled (subnet router for 10.0.3.0/24)             │   │
│        • wireguard  (alternative VPN)                           │   │
│        • registry:2 (registry.medc.local CNAME)                 │   │
│        • binary host (binaries.medc.local CNAME)                │   │
│        • iptables   (NAT to eth1, ingress DNAT)                 │   │
│                                                                 │   │
│        eth1 ───────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────────────────┘

  Default topology (configurable in medc.yaml):
    1 gateway + 1 mgmt + 1 k8s-control + 2 k8s-workers (= 5 instances)
  Mgmt has 8 GiB by default (k0rdent MCM memory pressure observed).
```

**What Incus buys us**
- One API for both system containers and VMs. Future MEDC topologies can
  mix container and VM nodes without running two tools.
- Profiles: no more `cat >> /var/lib/lxc/$NAME/config` edits.
- First-class snapshotting for the backup/rebuild path.
- Actively maintained (LXD is no longer Canonical-led; Incus is the
  community fork and the forward-looking target).

**What the gateway buys us**
- Hand-rolled dnsmasq + iptables move off the host into one container —
  the host is just a hypervisor.
- One tailscale subnet router for the whole lab (no per-container
  tailscaled), with a separate host tailscaled gated to superusers.
- Clean ingress/egress termination; matches a real datacenter's
  router/edge-services VM pattern.
- Registry + binary host on `registry.medc.local` and
  `binaries.medc.local` (CNAMEs to the gateway) — air-gapped lab use
  becomes trivial.

**What stays**
- The *default* role layout (now 1 gateway + 1 mgmt + 1 master + 2
  workers, matching k0rdent's child-cluster pattern plus the new
  edge-services node).
- Debian Trixie as the default rootfs.
- The hardening pass (chrony, kernel params, swap off).

**Storage / filesystem choice (v1)**

v1 defaults to **btrfs** for the Incus storage pool — instant
copy-on-write snapshots are what makes MEDC's "rebuild in seconds"
property real. ZFS is a fully equivalent alternative when already in
use on the host. `dir` is a slow fallback that's explicitly opt-in
for hosts where neither CoW filesystem is available.

**bcachefs** is the natural successor candidate (mainline since 6.7)
and would be a strong fit for MEDC, **but Incus does not yet provide
a `bcachefs` storage driver**. The supported set is
`dir`/`btrfs`/`zfs`/`lvm`/`lvm-thin`/`ceph*`/`linstor`. Tracked as a
watch item; we add it to MEDC's supported drivers as soon as
upstream lands one. See `docs/v1-design.md` §9.1 for detail.

## 4. Refactor roadmap

Each phase is a separate unit of work; do not bundle.

### Phase A — Parameterization design *(pending)*
Choose a config format and catalogue every hardcoded value across the
current scripts. Working default: a flat shell-sourced `conf/medc.env`
(zero dependencies, matches the shell codebase). Alternative: YAML +
a tiny parser, if we want richer structure. **Open question; do not
unilaterally pick one.**

Values to externalize: container names and roles, per-node IP and MAC
(or "auto"), bridge name, network CIDR, DHCP range, DNS domain, NAT
egress interface, ingress rules (host-to-container port forwards),
per-node CPU/memory, image (distro + release + arch), and credential
material.

### Phase B — Parameterize the LXC scripts
Rewrite `full-medc-setup.sh`, `create-containers.sh`,
`init-containers.sh`, `medc-production-ready.sh`, `medc-k8s-powerup.sh`,
and `check-medc-health.sh` to source the config and loop over declared
nodes rather than hard-coding names. Prove the config surface is
sufficient while still on LXC.

### Phase C — Migrate LXC → Incus
Replace `lxc-*` commands with `incus` equivalents. Replace the raw
bridge + dnsmasq + iptables stack with an Incus managed network. Move
per-container `config` edits into Incus profiles. Decide whether the
MVP config fits in a single profile set or whether the topology-to-
Incus translation deserves its own helper.

### Phase D — Verification suite
Scripted host-side health checks plus a teardown-and-rebuild smoke
test that runs on a disposable Debian Trixie host.

### Phase E — Hand-off to k0rdent install
Document (not script) the post-MEDC steps: installing k0rdent on
`k0rdent-mgmt`, then using k0smotron's `remoteserver` provider to
bootstrap the child cluster across the worker nodes. The install
itself stays out of this repo.

## 5. Known gaps / manual post-install steps

Features currently *documented but not implemented* by any script in
the repo. These must be performed by hand on the host if the
advertised behaviour is required. The refactor (phases B–C) should
fold them into the scripts.

### 5.1 Container autostart
`README.md` claims containers auto-start on boot, but no script appends
the necessary config lines. Do this manually per container:

```bash
for c in k0rdent-mgmt k0s-child-master k0s-child-worker1 k0s-child-worker2; do
    echo "lxc.start.auto = 1"   | sudo tee -a /var/lib/lxc/$c/config
    echo "lxc.start.delay = 5"  | sudo tee -a /var/lib/lxc/$c/config
done
```

### 5.2 iptables persistence
`full-medc-setup.sh` installs `iptables` but not the persistent variant.
On reboot, `medc-k8s-powerup.sh` re-adds the NAT + FORWARD rules, so
things still work — but the prescribed persistence path is:

```bash
sudo apt install -y iptables-persistent
sudo netfilter-persistent save
sudo systemctl enable netfilter-persistent
```

### 5.3 Boot-time systemd unit
The repo ships `medc-k8s-powerup.sh` (the script body) but no systemd
unit to invoke it at boot. Prescribed unit:

```ini
# /etc/systemd/system/medc-k8s-setup.service
[Unit]
Description=MEDC LXC Kubernetes Setup
After=network.target lxc-net.service
Wants=lxc-net.service

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/medc-k8s-powerup.sh

[Install]
WantedBy=multi-user.target
```

Install:

```bash
sudo install -m 0755 medc-k8s-powerup.sh /usr/local/bin/medc-k8s-powerup.sh
sudo systemctl daemon-reload
sudo systemctl enable medc-k8s-setup.service
```

## 6. Operating guide

### Access
```bash
sudo lxc-attach -n k0rdent-mgmt          # direct
ssh robot@10.0.3.10                      # over the bridge
```

### Start / stop
```bash
sudo ./medc-k8s-powerup.sh               # boot-time / manual reconcile
sudo lxc-start -n <name>
sudo lxc-stop  -n <name>
```

### Health
```bash
sudo ./check-medc-health.sh
```

### Backup (script generated by `medc-production-ready.sh`)
```bash
sudo /usr/local/bin/backup-lxc-containers.sh
# → snapshots, tars into /var/backups/lxc, keeps 7 days
```

### Maintenance (script generated by `medc-production-ready.sh`)
```bash
sudo /usr/local/bin/maintain-lxc-containers.sh
# → apt update/upgrade/autoremove, log rotation, disk-usage report
```

### Cron
See `crontab-entry.txt`. The suggested schedule is `@reboot` health
check + nightly backup + weekly maintenance.

## 7. Troubleshooting

### Containers don't start
```bash
sudo systemctl status lxc-net
sudo systemctl restart lxc-net
sudo ./medc-k8s-powerup.sh
```

### No internet from inside a container
```bash
sudo iptables -t nat -L POSTROUTING -n | grep 10.0.3.0/24
cat /proc/sys/net/ipv4/ip_forward            # must be 1
```

### DNS not resolving from inside a container
```bash
sudo lxc-attach -n k0rdent-mgmt -- resolvectl status
sudo lxc-attach -n k0rdent-mgmt -- cat /etc/resolv.conf
```

### Time skew (breaks k8s certs)
```bash
sudo lxc-attach -n k0rdent-mgmt -- chronyc tracking
```

### Log files worth knowing
- `/var/log/medc-health-boot.log` — boot health check
- `/var/log/lxc-backup.log` — backup
- `/var/log/lxc-maintenance.log` — maintenance
- `/var/log/lxc-k8s-status.log` — container state dump on powerup

## 8. Requirements

- **Host OS:** Debian-based (tested on Trixie)
- **Arch:** ARM64 or x86_64
- **RAM:** ≥ 16 GB (4 GB × 4 containers + headroom)
- **Disk:** ≥ 50 GB
- **CPU:** 4+ cores
- **Privilege:** root on the host

## 9. See also

- `README.md` — concise landing page
- `CLAUDE.md` — agent-oriented repo guidance and refactor state
- `stacklit.json` / `DEPENDENCIES.md` — auto-generated source map
  (regenerate with `stacklit generate`)
