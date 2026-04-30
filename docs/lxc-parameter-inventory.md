# LXC parameter inventory (v0)

**Status:** working reference for the v0 → v1 (Incus) migration. **This
file is retired the moment the Incus path lands.** Treat it as the
authoritative list of every parameter the current LXC scripts produce
or assume, so the v1 YAML config / Incus profiles cover the same
surface.

For each row:
- **Value today** — the concrete value baked into the LXC scripts.
- **Source** — the script + line where it's set or assumed.
- **Tunable?** — *Y* if a sensible operator might want to change it,
  *N* if it's effectively a system-level constant.
- **Incus mapping** — where this value lives in v1 (instance config
  key, network option, profile, device, host-side, or "removed —
  handled by Incus").

Where the v1 mapping is uncertain or contested (e.g. DHCP
reservations), the row is marked **⚠** and explained at the end of the
section.

---

## 1. Host prerequisites

Packages, sysctls, and kernel modules the host must have before any
container is created.

| Parameter | Value today | Source | Tunable? | Incus mapping |
|---|---|---|---|---|
| Host OS | Debian Trixie | `README.md`, `MEDC-overview.md` | N | unchanged — Incus runs on the same host OS |
| Host arch | ARM64 or x86_64 | `README.md` | N | unchanged |
| apt packages | `lxc lxc-templates bridge-utils dnsmasq-base iptables sshpass` | `full-medc-setup.sh:65` | partial | replaced by `incus` (single package); `sshpass` only needed for the test step |
| Kernel modules (loaded) | `br_netfilter`, `overlay` | `medc-production-ready.sh:213-214`, `medc-k8s-powerup.sh:7-8` | N | host-side, unchanged (k8s requirement, not an LXC concern) |
| Kernel modules (persistent) | `br_netfilter`, `overlay` in `/etc/modules` | `medc-production-ready.sh:217-218` | N | host-side, unchanged |
| Host sysctl `net.ipv4.ip_forward` | `1` (in `/etc/sysctl.conf` and live) | `full-medc-setup.sh:120-121`, `medc-k8s-powerup.sh:5` | N | host-side; Incus does NOT manage host sysctls. Keep this. |

**Note:** the inline-generated `/usr/local/bin/create-k8s-lxc.sh` and
`/usr/local/bin/test-lxc-network.sh` go away in v1 (Incus replaces both).

---

## 2. Bridge and network

| Parameter | Value today | Source | Tunable? | Incus mapping |
|---|---|---|---|---|
| Bridge name | `lxcbr0` | `full-medc-setup.sh:70` | Y | Incus network name (e.g. `medcbr0`) — `incus network create <name>` |
| Bridge IPv4 address | `10.0.3.1` | `full-medc-setup.sh:71` | Y | `ipv4.address=10.0.3.1/24` on the network |
| Bridge netmask | `255.255.255.0` | `full-medc-setup.sh:72` | Y | folded into `ipv4.address` CIDR |
| Network CIDR | `10.0.3.0/24` | `full-medc-setup.sh:73`, NAT rule `:124`, powerup `:11` | Y | derived from `ipv4.address` |
| DHCP range | `10.0.3.200–10.0.3.254` | `full-medc-setup.sh:74` | Y | `ipv4.dhcp.ranges=10.0.3.200-10.0.3.254` (only matters if we leave space for non-reserved instances) |
| DHCP max | `55` | `full-medc-setup.sh:75` | Y | implicit in `ipv4.dhcp.ranges` size; not separately needed |
| DNS domain | `lxc.local` | `full-medc-setup.sh:76`, dnsmasq `expand-hosts` `:166-167` | Y | `dns.domain=medc.local` (rename suggested — `lxc.local` is misleading post-Incus) |
| DHCP confile path | `/etc/lxc/dnsmasq.d/hosts.conf` | `full-medc-setup.sh:77` | N | removed — Incus owns its dnsmasq |
| `expand-hosts` | enabled | `full-medc-setup.sh:166` | N | implicit in Incus DNS |
| IPv6 | not configured (autoconfig only — see `vcd-describe.txt` historical IPv6 ULAs) | implicit | Y | `ipv6.address=auto` or `none` on the network, our call |

### Static IP / MAC reservations ⚠

| Parameter | Value today | Source | Tunable? | Incus mapping |
|---|---|---|---|---|
| `k0rdent-mgmt` IP | `10.0.3.10` | `full-medc-setup.sh:10`, `/etc/hosts` `:132` | Y | per-instance; see DHCP design call |
| `k0s-child-master` IP | `10.0.3.20` | `full-medc-setup.sh:11`, `/etc/hosts` `:133` | Y | " |
| `k0s-child-worker1` IP | `10.0.3.21` | `full-medc-setup.sh:12`, `/etc/hosts` `:134` | Y | " |
| `k0s-child-worker2` IP | `10.0.3.22` | `full-medc-setup.sh:13`, `/etc/hosts` `:135` | Y | " |
| Reservation mechanism | `dhcp-host=<MAC>,<IP>,<name>` in `/etc/lxc/dnsmasq.d/hosts.conf` | `full-medc-setup.sh:176` | N | **⚠ design call** — see note below |
| MAC discovery | started container, read `/sys/class/net/eth0/address`, then pinned | `full-medc-setup.sh:174` | N | flips: in v1 we *set* the MAC ahead of launch, not discover it |
| DNS host records | `host-record=<name>.lxc.local,<name>,<ip>` | `full-medc-setup.sh:186` | N | implicit in Incus DNS once instance has a name + IP |
| Host `/etc/hosts` entries | manually injected for all four nodes | `full-medc-setup.sh:131-135` | N | optional in v1; Incus DNS can be queried from host via the bridge |

**v1 decision: run our own dnsmasq alongside Incus.** Set the
Incus-managed network's `ipv4.dhcp=false` and `ipv4.dns.mode=none`,
attach our own dnsmasq instance bound to the bridge with a hand-curated
`/etc/medc/dnsmasq.conf` carrying the v0-style `dhcp-host=<MAC>,<IP>,<name>`
reservations and `host-record=<name>.<domain>,<ip>` DNS entries.

Rationale: this is the only option that preserves the v0 invariants
exactly — pin a MAC to an IP, let DHCP serve it, get matching DNS as a
side effect, rebuild a container without re-config. The two
alternatives explored:

- *Per-instance `volatile.eth0.hwaddr` + Incus DHCP*: works, but the
  reservation lives split across the instance config and Incus's
  internal state — no single file to grep.
- *Incus IPAM via per-NIC `ipv4.address`*: cleanest in YAML but
  bypasses DHCP entirely; the container has the IP whether or not it
  asked for one, which subtly changes failure modes.

**Implications for v1:**
- Add `dnsmasq` (the standalone package, not just `dnsmasq-base`) to
  host prereqs.
- v1 generates `/etc/medc/dnsmasq.conf` from the topology YAML at
  apply time.
- A systemd unit (or `dnsmasq.service` override) supervises the MEDC
  dnsmasq so it survives reboots without our help.
- Incus network is created with `ipv4.dhcp=false ipv4.dns.mode=none`
  but **keeps `ipv4.nat=true`** — we want Incus's NAT, just not its
  DHCP/DNS.

---

## 3. Per-instance identity

| Parameter | Values today | Source | Tunable? | Incus mapping |
|---|---|---|---|---|
| Instance name (= hostname) | `k0rdent-mgmt`, `k0s-child-master`, `k0s-child-worker1`, `k0s-child-worker2` | `full-medc-setup.sh:8`, `init-containers.sh:7`, etc. | Y | instance name; `hostnamectl` no longer needed (Incus sets it) |
| Role (implicit) | mgmt / master / worker | implicit by name | Y | explicit in v1 YAML — drives profile selection |
| Default count | 1 mgmt + 1 master + 2 workers | `full-medc-setup.sh:8` | Y | declared in v1 topology config |

---

## 4. Per-instance image

| Parameter | Value today | Source | Tunable? | Incus mapping |
|---|---|---|---|---|
| Distribution | `debian` | `full-medc-setup.sh:87` | Y | `incus launch images:debian/<release>` |
| Release | `trixie` | `full-medc-setup.sh:87` | Y | image alias |
| Architecture | `arm64` (hardcoded — should be host arch) | `full-medc-setup.sh:87` | **bug — fix in v1** | **default `x86_64` in v1**; rely on Incus's host-arch resolution by omitting `--arch` from `incus launch`. ARM64 stays supported but is no longer the implicit default. |
| Template | `download` (LXC template system) | `full-medc-setup.sh:87` | N | removed — Incus uses image servers |

---

## 5. Per-instance LXC config (the `/var/lib/lxc/<name>/config` appends)

These are LXC-config-file lines appended by various scripts. In v1
they become Incus profile entries (mostly), with caveats noted below.

| Parameter | Value today | Source | Tunable? | Incus mapping |
|---|---|---|---|---|
| `lxc.apparmor.profile` | `unconfined` | `full-medc-setup.sh:90` | Y | **see rationale below** — v1 keeps the unconfined posture by default for the same reason v0 needs it |
| `lxc.cap.drop` | empty (= drop nothing) | `full-medc-setup.sh:91` | Y | `security.privileged=true` is the closest equivalent; for k8s usually needed |
| `lxc.mount.auto` | `proc:rw sys:rw cgroup:rw` | `full-medc-setup.sh:92` | N | Incus mounts these RW by default for system containers; verify but probably remove |

**AppArmor / capabilities rationale (v0 history):** the unconfined
apparmor profile + empty `cap.drop` was set so **systemd functions
correctly inside the container** — without it, systemd unit start,
cgroup management, and `/sys/fs/cgroup` writability all break. v1
must preserve this property. The Incus equivalents:

- `security.privileged=true` — closest single switch; full
  capabilities, runs as host root inside container. **Default in v1.**
- `raw.lxc: lxc.apparmor.profile=unconfined` — keeps the LXC-level
  override available if we want unprivileged + unconfined.

**Tailscale posture (v1 decision):** MEDC runs a **two-tier tailnet**:

- **In-container privileged tailscaled** (per MEDC instance) — the
  *default*. Each container is a first-class tailnet node with its
  own identity, MagicDNS name, and ACL tags. The container's tailnet
  membership is what an *application admin* uses to reach the
  workload. Containers appear as the only addressable thing — the
  host underneath is invisible to this audience. This deliberately
  hides the fact that the MEDC host is an OVH VPS, a corp lab box, or
  anywhere else; the consumer's view is "I'm connecting to the
  k0rdent management node," not "I'm connecting to OVH-machine X
  hosting Incus instance Y."
- **Host-side tailscaled** — a *separate* tailscaled on the MEDC
  host itself, used **only by superusers / MEDC operators** for
  troubleshooting Incus, the dnsmasq we're running, the host's
  systemd, etc. This tailnet (or tailnet-tag) is gated to admin
  identities and is **not** shared with the application-admin tailnet.
  Compromising an in-container tailscaled does not give access to the
  host's tailnet membership.

Security trade-off accepted: in-container tailscaled requires
`security.privileged=true` (already our v1 default for systemd
correctness), so a tailscale-CVE-in-container = container-as-host-root
compromise. The blast radius is bounded to that one container's
tailnet identity, not the host or other containers. The two-tier
design is what makes that bound real.

**Future-proofing for remote clusters:** the schema must also leave
room for **remote k0rdent clusters** (e.g. another on-prem site)
joined into MEDC's management tailnet. Those aren't MEDC-instances —
they're external clusters that this MEDC needs to reach for
k0smotron-style management. Treat them as `tailscale.remote_clusters`
entries at schema time; no implementation needed for v1 ship, but the
config shape should accommodate them so we don't redo the schema
later.
| `lxc.start.auto` | `1` (per readme-startup.txt, **not** set by any current script — see `MEDC-overview.md` §5.1) | spec-only | Y | `boot.autostart=true` per instance — see maintenance-mode note below |
| `lxc.start.delay` | `5` (spec-only, same caveat) | spec-only | Y | `boot.autostart.delay=5` per instance |

**v1 decision:** set `boot.autostart=true` by default so the gap from
v0 closes. The schema must also support **opting out per-instance for
maintenance** without losing the default — two patterns are viable:

- **Per-instance flag**: `autostart: false` overrides the default in
  the topology config; agent re-applies the profile when toggled.
- **Maintenance window**: a single host-level flag
  (`medc maintenance on`) clears `boot.autostart` on every instance,
  with `medc maintenance off` restoring; instance-level flags remain
  unchanged underneath. Cleaner UX; preferred default.

Decision can be deferred to schema-design time; both are config-only.

---

## 6. Per-instance kernel sysctls

LXC sysctls (apply inside the container's kernel namespace where
allowed). These matter for k8s.

| Parameter | Value today | Source | Tunable? | Incus mapping |
|---|---|---|---|---|
| `net.bridge.bridge-nf-call-iptables` | `1` | `medc-production-ready.sh:69` | N | `linux.kernel_modules=br_netfilter` + post-launch `sysctl` (Incus has no direct equivalent for `lxc.sysctl.*`) |
| `net.bridge.bridge-nf-call-ip6tables` | `1` | `medc-production-ready.sh:71` | N | post-launch `sysctl` in cloud-init or init script |
| `net.ipv4.ip_forward` | `1` | `medc-production-ready.sh:70` | N | post-launch `sysctl` |
| `fs.inotify.max_user_instances` | `524288` | `medc-production-ready.sh:72` | N | post-launch `sysctl` |
| `fs.inotify.max_user_watches` | `524288` | `medc-production-ready.sh:73` | N | post-launch `sysctl` |
| Swap inside container | disabled (`swapoff -a` + fstab comment) | `medc-production-ready.sh:225-227` | N | cloud-init `runcmd` or initial `incus exec` |

**Mapping caveat:** LXC's `lxc.sysctl.*` directly writes the value
via the LXC tooling at start time. Incus profiles don't expose this
directly. **v1 decision:** apply via cloud-init `runcmd` baked into
the role profile's `user.user-data` (the cloud-init payload Incus
hands to the instance at first boot).

**Documentation requirement:** the v1 design doc and `MEDC-overview.md`
must spell out, in detail:

- That v0's `lxc.sysctl.*` values are *not* one-to-one ported into v1
  Incus config — they migrate to cloud-init.
- The exact cloud-init `runcmd` block that applies the five sysctls
  + `swapoff -a` + the `/etc/fstab` swap-comment edit, with the
  values inline so no operator hunts for them.
- Where the cloud-init payload lives in the v1 repo (likely a
  templated YAML fragment per role: `profiles/k8s-control.yaml`,
  `profiles/k8s-worker.yaml`).
- The verification step: `incus exec <name> -- sysctl <key>` after
  first boot, and how `check-medc-health.sh` confirms it.

This isn't a one-liner — it's a behavioural shift from "applied at
container start by the supervisor" to "applied once at first-boot by
the guest." Worth making it loud in the docs.

---

## 7. Per-instance resource limits

| Parameter | Value today | Source | Tunable? | Incus mapping |
|---|---|---|---|---|
| `lxc.cgroup2.memory.max` | `4G` | `medc-production-ready.sh:95` | Y | `limits.memory=4GiB` |
| `lxc.cgroup2.cpu.max` | `200000 1000000` (≈ 2 CPUs) | `medc-production-ready.sh:96` | Y | `limits.cpu=2` (CPU count) or `limits.cpu.allowance=20%` (quota) |
| Disk quota | none | n/a | Y | `limits.disk=…` (only on btrfs/zfs/lvm pools) |
| CPU pinning | none | n/a | Y | `limits.cpu=N-M` if we want pinning |

---

## 8. In-instance bootstrap (apt + system services)

What `init-containers.sh` and `full-medc-setup.sh`'s `configure_users_ssh`
+ the chrony / swap-off bits in `medc-production-ready.sh` install or
configure inside each container.

| Parameter | Value today | Source | Tunable? | Incus mapping |
|---|---|---|---|---|
| apt packages | `curl wget gnupg2 apt-transport-https ca-certificates lsb-release iptables iproute2 systemd-resolved openssh-server sudo chrony` | `init-containers.sh:18-19`, `full-medc-setup.sh:221`, `medc-production-ready.sh:49` | Y | cloud-init `packages:` list per role |
| `hostnamectl set-hostname` | matches container name | `init-containers.sh:23`, `full-medc-setup.sh:247` | N | removed — Incus sets it from instance name |
| `systemd-resolved` | enabled + started | `init-containers.sh:25-26` | N | cloud-init `runcmd:` |
| `chrony` | enabled + started + `chronyc makestep` | `medc-production-ready.sh:50-53` | N | cloud-init `runcmd:` (after `packages:` installs it) |

**Connectivity test** (`ping google.com`, `init-containers.sh:29`):
not a configured parameter, just a smoke test. Drop in v1; replace
with `incus exec ... ping -c1 1.1.1.1`.

---

## 9. Auth / SSH

| Parameter | Value today | Source | Tunable? | Incus mapping |
|---|---|---|---|---|
| `root` password | `123robot` (demo) | `full-medc-setup.sh:15, 224` | Y (must) | cloud-init `chpasswd:` — keep optional, default to disabled |
| `robot` user | uid auto, login shell `/bin/bash`, home created | `full-medc-setup.sh:227` | Y | cloud-init `users:` |
| `robot` password | `123robot` (demo) | `full-medc-setup.sh:16, 228` | Y (must) | as above; **default to SSH-key-only in v1** |
| `robot` sudo | `NOPASSWD: ALL` via `/etc/sudoers.d/robot` mode 440 | `full-medc-setup.sh:232-233` | Y | cloud-init `users.sudo:` |
| sshd `PermitRootLogin` | `yes` | `full-medc-setup.sh:237` | Y | cloud-init writes `/etc/ssh/sshd_config.d/...`; default `no` in v1 |
| sshd `PasswordAuthentication` | `yes` | `full-medc-setup.sh:238` | Y | default `no` in v1 |
| sshd `PubkeyAuthentication` | `yes` | `full-medc-setup.sh:239` | N | default `yes`, unchanged |
| SSH host keys | regenerated by Debian image first-boot | implicit | N | unchanged — cloud-init will handle |

**v1 stance:** password auth and `PermitRootLogin yes` are demo-only
holdovers. v1 should default to SSH-key auth for `robot`, no root
login, and the lab-mode password-auth path becomes opt-in via the
config.

---

## 10. Host iptables rules

| Parameter | Value today | Source | Tunable? | Incus mapping |
|---|---|---|---|---|
| NAT MASQUERADE | `iptables -t nat -A POSTROUTING -s 10.0.3.0/24 -o eth0 -j MASQUERADE` | `full-medc-setup.sh:124`, re-applied `medc-k8s-powerup.sh:11-12` | Y | `ipv4.nat=true` on the Incus network — managed automatically |
| FORWARD in | `iptables -I FORWARD -i lxcbr0 -j ACCEPT` | `full-medc-setup.sh:125`, re-applied `:14-15` | N | managed by Incus when network is created |
| FORWARD out | `iptables -I FORWARD -o lxcbr0 -j ACCEPT` | `full-medc-setup.sh:126`, re-applied `:17-18` | N | managed by Incus |
| Egress interface | `eth0` (hardcoded) | `full-medc-setup.sh:124`, `medc-k8s-powerup.sh:11` | **Y — must parameterize** | configurable in v1; Incus's `ipv4.nat=true` derives from default route, but operator override needed for the corp-lab scenario (see Connectivity Scenarios) |
| Persistence | not installed (no `iptables-persistent`); rules re-applied at boot by powerup script | `MEDC-overview.md` §5.2 | N | removed — Incus persists its rules |

**Net effect in v1:** ~30 lines of host iptables management goes away.
`medc-k8s-powerup.sh`'s entire NAT + FORWARD reconciliation block
disappears.

---

## 11. Cron / boot-time reconciliation

| Parameter | Value today | Source | Tunable? | Incus mapping |
|---|---|---|---|---|
| Boot-time NAT/FORWARD reconcile | `medc-k8s-powerup.sh` (manual or via missing systemd unit) | script body | N | removed — Incus owns its rules |
| Boot-time container start | loop in `medc-k8s-powerup.sh` | `medc-k8s-powerup.sh:24-29` | N | removed — `boot.autostart=true` |
| Boot-time module load | `modprobe br_netfilter overlay` | `medc-k8s-powerup.sh:7-8` | N | host-side, persistent via `/etc/modules` (already covered §1) |
| Sleep before container start | `sleep 10` | `medc-k8s-powerup.sh:21` | N | removed |
| Boot health check (cron) | `@reboot sleep 60 && /usr/local/bin/check-medc-health.sh > /var/log/medc-health-boot.log 2>&1` | `crontab-entry.txt:5` | Y | unchanged in shape, but the script itself becomes Incus-aware |

---

## 12. Backup and maintenance

| Parameter | Value today | Source | Tunable? | Incus mapping |
|---|---|---|---|---|
| Backup directory | `/var/backups/lxc` | `medc-production-ready.sh:135` | Y | `/var/backups/medc` (rename) |
| Backup mechanism | `lxc-snapshot` + `tar -czf snap-dir` + delete snapshot | `medc-production-ready.sh:148-154` | N | `incus snapshot <name>` (instant on btrfs/zfs) + optional `incus export <name> file.tar.gz` |
| Backup retention | 7 days (`find -mtime +7 -delete`) | `medc-production-ready.sh:163` | Y | unchanged shape; same retention logic on `incus export` files |
| Backup schedule | daily 02:00 (`crontab-entry.txt`) | `crontab-entry.txt:8` | Y | unchanged |
| Maintenance: `apt update && upgrade -y` per container | yes | `medc-production-ready.sh:187-190` | N | unchanged shape; `incus exec` instead of `lxc-attach` |
| Maintenance: `apt autoremove`, `apt clean` | yes | `medc-production-ready.sh:193-194` | N | unchanged shape |
| Maintenance: log cleanup `find /var/log -mtime +30 -delete` | yes | `medc-production-ready.sh:197-198` | Y | unchanged shape |
| Maintenance schedule | weekly Sun 03:00 | `crontab-entry.txt:11` | Y | unchanged |
| Logrotate (host-side) | rotates `/var/lib/lxc/*/rootfs/var/log/...` weekly, keep 4, compressed | `medc-production-ready.sh:108-126` | Y | path changes to `/var/lib/incus/storage-pools/<pool>/containers/<name>/rootfs/var/log/...` (or removed if we trust per-instance logrotate) |

---

## Connectivity scenarios

MEDC is meant to run in two qualitatively different environments. The
v1 design must work in both without code changes — only config:

### Scenario A — OVH (or similar) cloud VPS, host has a public IP
- Host is directly internet-reachable; egress is trivial.
- NAT MASQUERADE out of the public NIC works as v0 does today.
- Ingress can use Incus network forwards or the host's own iptables
  rules to expose specific container ports (k8s API, ingress
  controller, etc.) to the public internet.
- Tailscale optional but useful for management-plane access without
  exposing SSH on the public IP.

### Scenario B — Lab host behind a corporate firewall
- Host has only a private (RFC1918) IP; the corp firewall mediates
  everything.
- Outbound from containers → host's default route → corp firewall.
  May need an explicit HTTP/HTTPS proxy (corporate `http_proxy` /
  `https_proxy` envs) for `apt`, image pulls, k0rdent registries.
- Inbound from the operator's laptop → MEDC: typically not directly
  routable. **Tailscale is the intended path** — tailscaled provides
  point-to-point reachability without poking holes in the corp
  firewall. See §5 AppArmor / Tailscale caveat for the
  in-container-vs-host-side decision.

### Implications for v1 config schema
- `egress_interface` (default = host default route) — operator
  override for non-`eth0` host NICs (very common on cloud VPSes
  where the public NIC is `enp1s0` or similar).
- `http_proxy` / `https_proxy` / `no_proxy` (default = unset) — when
  set, propagated into apt config and into per-container env via
  cloud-init.
- `tailscale` block (two tiers — see §5 for posture rationale):
  - `tailscale.host` — host-side tailscaled, **superuser/operator
    tailnet**. Not exposed to application admins.
  - `tailscale.containers` — in-container tailscaled, **application
    admin tailnet**. Default tier, installed via cloud-init in each
    role profile.
  - `tailscale.remote_clusters` (future) — list of external
    k0rdent-style clusters reachable via tailscale (other on-prem
    sites). Schema-shape only in v1; no implementation required to
    ship.
- `ingress` block (default = empty list) — list of host-port →
  container-port forwards, applied as Incus network forwards in
  Scenario A; ignored in Scenario B (where corp firewall blocks it
  anyway, and tailscale is the path in).

## Summary of v1 design implications

Reading the inventory back, the v1 YAML config schema needs to express:

1. **Network block** — name, IPv4 address (CIDR), DNS domain, egress
   interface (default = host default route, override for cloud VPSes),
   NAT on/off (Incus). DHCP/DNS handled by **our own dnsmasq**, not
   Incus's; topology IPs feed `dhcp-host=` reservations.
2. **Topology block** — list of instances. Each instance has: name,
   role (mgmt / master / worker / generic), image (distro / release;
   arch defaults to host), IP (static, served by our dnsmasq), MAC
   (chosen at v1-apply time, persisted in topology), CPU, memory,
   `autostart` (default true, can be flipped per-instance for
   maintenance).
3. **Profile / hardening block** — k8s sysctls applied via
   **cloud-init `runcmd`** at first boot (must be loudly documented),
   kernel modules (host-side), swap-off, security posture
   (`security.privileged=true` default for systemd correctness; raw
   `lxc.apparmor.profile=unconfined` available as opt-in alternative).
4. **Auth block** — robot user + SSH keys list + optional password
   (default off) + sudo policy (default NOPASSWD for lab use, opt-in
   for stricter modes). Default to SSH-key auth, no root login;
   password auth becomes opt-in.
5. **Backup block** — pool driver (dir / btrfs / zfs), retention days,
   schedule, export-on-snapshot on/off.
6. **Connectivity block** — `egress_interface` override, optional
   `http_proxy` / `https_proxy` / `no_proxy` for the corp-firewall
   scenario, `tailscale` sub-block (scheme TBD), `ingress` forward
   list (used in cloud-VPS scenario, ignored in corp-lab).
7. **Operator block** — maintenance-mode toggle (clears `autostart`
   on all instances atomically). Three currently-manual v0 gaps
   (autostart, iptables persistence, systemd unit) all become
   Incus-native and the gaps close.

### Remaining open design calls

- **Maintenance-mode UX** (§5 boot.autostart row) — per-instance flag
  vs. global host toggle vs. both. Pure config-shape question;
  defer to schema-design time.

Everything else maps straightforwardly.
