# MEDC v1 design — Incus + parameterized

## 1. Status, scope, and inputs

**Status:** draft. Authoritative blueprint for MEDC v1. Retired or
folded into `MEDC-overview.md` once v1 ships.

**Scope:** the architectural and config-surface design for replacing
the v0 LXC implementation with an Incus-backed, YAML-driven platform.
*Implementation* lives in subsequent PRs; this doc says **what**
v1 looks like, not **when** each line of code lands.

**Inputs:**

- `docs/lxc-parameter-inventory.md` — every parameter the v0 LXC
  scripts produce or assume. Defines the surface v1 must cover.
- `~/Devops/incus-docs/medc-migration-notes.md` — Incus-side mapping
  for each v0 concern, with verdicts (clean / caveats / fundamentally
  different).
- `MEDC-overview.md` — vision and roadmap (v1 is Phase C of that
  roadmap, with parameterization folded in).

**Out of scope for this doc:**

- Installation of k0rdent / k0smotron on top of v1 (that remains
  outside the repo).
- Multi-host clustering of MEDC itself (deferred until single-host
  v1 is solid).
- Migration of *running* v0 instances to v1 (we ship a clean-rebuild
  path; live migration is not on the menu).

---

## 2. Architecture overview

```
┌───────────────────────────────────────────────────────────────────┐
│  Host  (Debian Trixie, x86_64 default — ARM64 supported)              │
│                                                                       │
│  Daemons on the host:                                                 │
│    • incusd            — instance lifecycle, profiles, storage        │
│    • tailscaled (host) — operator/superuser tailnet (admin path)      │
│                                                                       │
│  Host's primary uplink NIC ── (passed into gateway as eth1) ──────┐   │
│                                                                   │   │
│  ┌───────────────────────────────────────────────────────────┐    │   │
│  │  Incus-managed bridge:  medcbr0                           │    │   │
│  │     ipv4.address = 10.0.3.1/24                            │    │   │
│  │     ipv4.nat     = false   (gateway terminates NAT)       │    │   │
│  │     ipv4.dhcp    = false   (gateway runs dnsmasq)         │    │   │
│  │     ipv4.dns.mode = none                                  │    │   │
│  └───────────────────────────────────────────────────────────┘    │   │
│       │           │           │           │           │           │   │
│       │       ┌───┴────┐  ┌───┴────┐  ┌───┴────┐  ┌───┴────┐      │   │
│       │       │mgmt    │  │master  │  │worker1 │  │worker2 │      │   │
│       │       │.10  8G │  │.20  4G │  │.21  4G │  │.22  4G │      │   │
│       │       └────────┘  └────────┘  └────────┘  └────────┘      │   │
│       │                                                           │   │
│   ┌───┴────────────────────────────────────────┐                  │   │
│   │  gateway          (.5  on medcbr0 = eth0)  │ ──────  eth1  ───┘   │
│   │  • dnsmasq        (DHCP + DNS for lab)     │                      │
│   │  • tailscaled     (subnet router 10.0.3/24)│                      │
│   │  • wireguard      (alternative VPN)        │                      │
│   │  • registry:2     (registry.<domain>)      │                      │
│   │  • binary host    (binaries.<domain>)      │                      │
│   │  • iptables NAT   (eth1 ← MASQUERADE)      │                      │
│   │  • iptables ingress forwards               │                      │
│   └────────────────────────────────────────────┘                      │
│                                                                       │
└───────────────────────────────────────────────────────────────────────┘

  Two tailnets / tag scopes:
    • host tier       — host-side tailscaled, tag:medc-admin
                        Used only by superusers troubleshooting incusd,
                        kernel, host syslog, etc.
    • application tier — gateway-side tailscaled, tag:medc-app-admin
                        Advertises 10.0.3.0/24 as a subnet route.
                        App admins reach lab containers by IP/hostname
                        through the gateway. Containers themselves
                        are NOT tailnet members.
  Compromising the gateway tailscaled exposes lab containers but NOT
  the host. The two tiers are deliberately separated.
```

**What Incus owns:** instance lifecycle (create/start/stop/snapshot),
storage pool, profiles, the bridge interface. **NAT is no longer
Incus's job** — the gateway instance terminates it. The bridge's
`ipv4.nat=false` reflects this.

**What the gateway owns** (the new fifth instance): DHCP + DNS for the
lab subnet (dnsmasq), L3 routing/NAT to the host's uplink NIC, the
application-admin tailscaled (subnet router for 10.0.3.0/24), an
optional WireGuard endpoint as an alternative VPN, the container
registry, and a static-binary host. CNAMEs in the gateway's dnsmasq
let `registry.<domain>` and `binaries.<domain>` resolve to the
gateway's lab-side IP — clients see distinct hostnames, the gateway
is one process.

**What the host owns:** `incusd`, the host-tier tailscaled (superuser
access for host troubleshooting), and the storage pool. Nothing else
that the lab depends on. The host is a hypervisor; the gateway is the
router.

**What MEDC owns end-to-end:** the YAML config that drives both Incus
and the gateway's services, the `medc` CLI, and the gateway's
profile/cloud-init payload that materializes dnsmasq + iptables +
tailscaled + WG + registry in one place.

**What's gone vs. v0:** the hand-rolled `/etc/default/lxc-net`,
`/usr/local/bin/create-k8s-lxc.sh`, `/usr/local/bin/test-lxc-network.sh`,
the iptables NAT/FORWARD reconciliation in `medc-k8s-powerup.sh`,
the manual `/var/lib/lxc/<name>/config` appends in
`medc-production-ready.sh`, the `lxc.start.auto` gap, the missing
systemd unit, and the missing `iptables-persistent`. The
host-side dnsmasq the earlier draft proposed is also gone — moved
into the gateway instance for the same reason a real datacenter puts
DNS+DHCP on a router/services VM, not on the hypervisor.

---

## 3. YAML config schema

A single operator-facing config file: `medc.yaml`. The `medc apply`
CLI consumes this and produces all derived state (Incus network,
profiles, dnsmasq.conf, instance launches).

### 3.1 Top-level shape

```yaml
medc:
  version: 1                      # schema version

  network:                        # §3.2 — Incus bridge + lab subnet
    name: medcbr0
    ipv4: 10.0.3.0/24             # lab subnet (gateway-routed, NOT incus-NATed)
    bridge_address: 10.0.3.1      # the bridge's host-side IP (unused as gateway by lab)
    gateway_ip: 10.0.3.5          # the gateway INSTANCE's lab-side IP — clients use this as default route
    dns_domain: medc.local        # also used for the registry/binary CNAMEs
    dhcp_range: 10.0.3.100-10.0.3.199
    egress_interface: auto        # passed into the gateway as eth1 — "auto" | <ifname>

  topology:                       # §3.3 — instances (gateway first)
    instances:
      - name: medc-gateway
        role: gateway
        ip: 10.0.3.5
        mac: 02:medc:00:00:00:05
        cpu: 2
        memory: 4GiB
        autostart: true
      - name: k0rdent-mgmt
        role: mgmt
        ip: 10.0.3.10
        mac: 02:medc:00:00:00:10  # optional; auto-generated if omitted
        cpu: 2
        memory: 8GiB              # bumped from 4 — k0rdent MCM memory pressure observed
        autostart: true
      - name: k0s-child-master
        role: k8s-control
        ip: 10.0.3.20
        cpu: 2
        memory: 4GiB
        autostart: true
      - name: k0s-child-worker1
        role: k8s-worker
        ip: 10.0.3.21
        cpu: 2
        memory: 4GiB
        autostart: true
      - name: k0s-child-worker2
        role: k8s-worker
        ip: 10.0.3.22
        cpu: 2
        memory: 4GiB
        autostart: true

  image:                          # §3.4 — defaults applied to every instance
    distribution: debian
    release: trixie
    architecture: auto            # "auto" (= host arch) | x86_64 | arm64

  hardening:                      # §3.5 — security + k8s-readiness
    security_privileged: true     # default; required for systemd correctness
    apparmor_profile: default     # "default" | "unconfined" (raw.lxc)
    swap_in_container: false
    sysctls:
      net.bridge.bridge-nf-call-iptables: 1
      net.bridge.bridge-nf-call-ip6tables: 1
      net.ipv4.ip_forward: 1
      fs.inotify.max_user_instances: 524288
      fs.inotify.max_user_watches: 524288
    kernel_modules_host:          # loaded + persisted on the host
      - br_netfilter
      - overlay

  auth:                           # §3.6 — user + SSH posture
    user: robot
    ssh_authorized_keys:          # required; password auth is opt-in
      - ssh-ed25519 AAAA... operator@laptop
    sudo_nopasswd: true
    password_auth: false          # default off; flip on for lab/demo
    permit_root_login: false      # default off

  connectivity:                   # §3.7 — proxy, tailscale, wireguard, ingress
    http_proxy: ""                # empty = unset
    https_proxy: ""
    no_proxy: ""
    tailscale:
      host:                       # superuser tailnet (host-side tailscaled)
        enabled: true
        tailnet: ""               # "" = default tailnet for the auth key
        tags: [tag:medc-admin]
        auth_key_env: MEDC_TS_HOST_AUTH_KEY
      gateway:                    # application-admin tailnet (gateway-side tailscaled, subnet router)
        enabled: true
        tailnet: ""
        tags: [tag:medc-app-admin]
        advertise_routes: [10.0.3.0/24]
        auth_key_env: MEDC_TS_GATEWAY_AUTH_KEY
      remote_clusters: []         # future-proof; empty in v1
    wireguard:                    # optional alternative VPN, terminates on gateway
      enabled: false
      listen_port: 51820
      public_key: ""              # generated on first apply if empty; persisted
      peers: []                   # list of {name, public_key, allowed_ips}
    ingress: []                   # list of {host_port, target, target_port, protocol}

  infra:                          # §3.X — services hosted on the gateway
    registry:
      enabled: true
      product: registry           # "registry" (registry:2) | "harbor" | "nexus"
      port: 5000
      data_volume_size: 20GiB
      tls: false                  # plain HTTP for lab; flip on with cert source for realism
    binary_host:
      enabled: true
      port: 80
      root: /var/lib/medc/binaries
    cnames:                       # served by gateway dnsmasq
      - { alias: registry, target: medc-gateway }
      - { alias: binaries, target: medc-gateway }

  storage:                        # §3.8
    pool_driver: btrfs            # btrfs | zfs | dir
    pool_name: medc
    snapshot_retention_days: 7

  operator:                       # §3.9 — flags
    maintenance_mode: false       # global override; clears autostart on apply
    backup_dir: /var/backups/medc
```

### 3.2 `network` block

Drives the Incus bridge creation **and** is consumed by the gateway
profile (which renders the dnsmasq config + iptables NAT rules).

| Field | Required | Default | Notes |
|---|---|---|---|
| `name` | yes | — | Incus network name (`medcbr0` recommended) |
| `ipv4` | yes | — | CIDR, e.g. `10.0.3.0/24` |
| `bridge_address` | no | first usable in CIDR | the bridge interface's host-side IP. Not the lab gateway. |
| `gateway_ip` | yes | — | the gateway *instance's* lab-side IP. This is the default route for every other instance. |
| `dns_domain` | yes | `medc.local` | dnsmasq `domain=`; also the suffix for CNAMEs (registry, binaries) |
| `dhcp_range` | yes | — | range for unreserved clients; reserved instances get their pinned IP via `dhcp-host=` |
| `egress_interface` | no | `auto` | host NIC pulled into the gateway as `eth1`. `auto` = host default route. Override for cloud VPSes (`enp1s0`, etc.) |

**Note on Incus NAT:** `ipv4.nat` is forced to `false` on the Incus
network. NAT is the gateway instance's job (see §5).

### 3.3 `topology` block

`instances` is a flat list. Order does not matter for `apply` —
the CLI sorts by role precedence (gateway → mgmt → k8s-control →
k8s-worker) and launches gateway first because everything else
depends on its DHCP/DNS.

| Field | Required | Default | Notes |
|---|---|---|---|
| `name` | yes | — | Incus instance name = hostname |
| `role` | yes | — | `gateway` \| `mgmt` \| `k8s-control` \| `k8s-worker` \| `generic` |
| `ip` | yes | — | static IP (must lie in `network.ipv4`, must lie *outside* `dhcp_range`); the `gateway` role's IP must equal `network.gateway_ip` |
| `mac` | no | autogenerated | format `02:medc:XX:XX:XX:XX`; persisted into config on first apply if generated |
| `cpu` | no | `2` | int (CPU count) |
| `memory` | no | `4GiB` (`8GiB` for `mgmt`) | size string. The mgmt default is bumped from 4 → 8 GiB based on observed k0rdent MCM memory pressure. Tunable. |
| `autostart` | no | `true` | per-instance flag; `operator.maintenance_mode: true` forces `false` for all instances at apply time |

**Constraint:** exactly one instance must have `role: gateway`.
v1 doesn't support multi-gateway HA (single gateway is the v1 design;
HA is a future-roadmap item).

### 3.4 `image` block

Applied to every instance unless an instance-level override is added
(none defined for v1; trivial to add later if needed).

`architecture: auto` resolves to the host arch at apply time. Operator
override for explicit `x86_64` or `arm64` is supported; this lets a
mixed-arch operator (e.g. on Apple Silicon dev box) launch x86_64
instances if the host has the kernel support.

### 3.5 `hardening` block

The five sysctls and the swap-off bit migrate from v0 LXC's
`lxc.sysctl.*` and `swapoff` calls to **cloud-init `runcmd`** at first
boot of each instance. See §6 for the exact runcmd batch.

`security_privileged: true` is the default (preserves v0's
systemd-correctness posture; see inventory §5 AppArmor rationale).
Operators wanting a stricter posture can flip to `false` and use
`apparmor_profile: unconfined` to get LXC-style raw apparmor override.

`kernel_modules_host` is loaded via `modprobe` at apply time and
persisted to `/etc/modules-load.d/medc.conf` so they survive reboot
without our help.

### 3.6 `auth` block

**SSH-key auth by default.** `ssh_authorized_keys` is required —
v1 refuses to apply if it's empty *unless* `password_auth: true` is
explicitly set (in which case lab-mode passwords are honored).

`permit_root_login: false` and `password_auth: false` are the v1
defaults. The v0 `robot:123robot` posture is recovered by setting
both to `true` and adding a password — opt-in, not the default.

### 3.7 `connectivity` block

See §7 for the tailscale design, §7.5 for the WireGuard alternative,
and §8 for the ingress design. Proxy variables are propagated into
apt config and per-instance environment via cloud-init when set.

**Tailscale tier shape:**

- `tailscale.host` — host-side tailscaled. Tag `tag:medc-admin`. Used
  only by superusers troubleshooting the Incus host itself. Disabled
  if the host is reached by other means (out-of-band console, etc.).
- `tailscale.gateway` — gateway-instance tailscaled, **subnet router
  for `10.0.3.0/24`**. Tag `tag:medc-app-admin`. Single tailnet
  identity covers the whole lab; app admins reach lab containers by
  their lab IPs/hostnames over tailscale, routed via the gateway.
  **No per-container tailscaled** — that was the earlier draft and
  has been retracted in favor of the subnet-router model.
- `tailscale.remote_clusters` — future, see §7.6.

**WireGuard:** alternative VPN, terminates on the gateway. Useful
when the operator's environment doesn't allow tailscale (specific
egress firewall rules, regulatory) or when peering with an existing
WG network. Disabled by default. See §7.5.

### 3.8 `infra` block

The new top-level `infra` block describes services hosted on the
gateway instance. v1 ships `registry`, `binary_host`, and CNAMEs.
Future additions (NTP server, syslog collector, monitoring scrape
target) slot in here.

**`infra.registry`:** a container registry served by the gateway,
addressed via `registry.<dns_domain>` (a CNAME to the gateway). v1
defaults to **registry:2** (the OCI Distribution registry, plain).
The schema's `product` enum reserves `harbor` and `nexus` for
operators wanting fuller features; v1 ships only `registry` and
emits a "not yet implemented" error for the others.

| Field | Default | Notes |
|---|---|---|
| `enabled` | `true` | Disable to remove the registry container from the gateway profile |
| `product` | `registry` | `registry` only in v1; `harbor`/`nexus` reserved |
| `port` | `5000` | Listen port on the gateway's lab-side IP |
| `data_volume_size` | `20GiB` | Incus disk device on the gateway (btrfs sub-volume on btrfs pools) |
| `tls` | `false` | Plain HTTP for lab default. Flip on with cert source for realism. (TLS source not in v1 schema; future addition.) |

**`infra.binary_host`:** static-file server (caddy or nginx — TBD
implementation detail) at `binaries.<dns_domain>`. Hosts k0s/k0rdent
installer artifacts, kubectl/helm CLIs, and any tarballs the lab
needs. Air-gapped lab use case: pre-populate `root` once, then
`binaries.<dns_domain>` becomes the lab's only outbound dependency.

| Field | Default | Notes |
|---|---|---|
| `enabled` | `true` | |
| `port` | `80` | |
| `root` | `/var/lib/medc/binaries` | Path inside the gateway, backed by an Incus disk device |

**`infra.cnames`:** dnsmasq CNAME entries served by the gateway.
v1 emits one per entry: `cname=<alias>.<dns_domain>,<target>.<dns_domain>`.
Default seed includes `registry → medc-gateway` and
`binaries → medc-gateway` so a default-config lab has working
registry/binary URLs from day one.

### 3.9 `storage` block

Default `pool_driver: btrfs` for snapshot speed (instant CoW vs.
the v0 `tar -czf` of a snap dir). `dir` is the safe fallback for
hosts without btrfs/zfs. See §9.

The gateway instance gets an additional Incus disk device per
`infra.registry.data_volume_size` and per `infra.binary_host` —
allocated from the same pool. Sizing is operator-tunable; defaults
are conservative (20 GiB registry, no separate binary-host quota).

### 3.10 `operator` block

`maintenance_mode: true` is the global toggle: at next apply, every
instance gets `boot.autostart=false` and is stopped. `false` (or
omitted) restores per-instance `autostart` from `topology`.

---

## 4. Role profiles

Incus profiles realize the per-role config in a composable way. v1
ships four:

- `medc-base` — common config every instance gets.
- `medc-gateway` — the lab's router/services VM (dnsmasq, tailscaled
  subnet router, WireGuard, registry, binary host, NAT iptables, dual
  NIC). One per topology.
- `medc-mgmt` — minimal delta over base; default route is the gateway.
- `medc-k8s-control` — minimal delta over base.
- `medc-k8s-worker` — minimal delta over base.

Composition: every instance is created with `--profile medc-base
--profile medc-<role>`. Per-instance overrides (CPU, memory,
autostart, MAC, extra disk devices for the gateway) live on the
instance config, not in profiles.

### 4.1 `medc-base` profile (sketch)

```yaml
name: medc-base
description: MEDC base profile — applied to every instance
config:
  security.privileged: "true"
  boot.autostart: "true"
  boot.autostart.delay: "5"
  user.user-data: |
    #cloud-config
    package_update: true
    package_upgrade: false
    packages:
      - openssh-server
      - sudo
      - chrony
      - systemd-resolved
      - curl
      - ca-certificates
    users:
      - name: robot
        groups: [sudo]
        shell: /bin/bash
        sudo: ALL=(ALL) NOPASSWD:ALL
        ssh_authorized_keys: ${MEDC_AUTHORIZED_KEYS}
    write_files:
      - path: /etc/ssh/sshd_config.d/10-medc.conf
        content: |
          PermitRootLogin no
          PasswordAuthentication no
          PubkeyAuthentication yes
    runcmd:
      - systemctl enable systemd-resolved && systemctl start systemd-resolved
      - systemctl enable chrony && systemctl start chrony && chronyc makestep
      - swapoff -a
      - sed -i '/ swap / s/^/#/' /etc/fstab
      - sysctl -w net.bridge.bridge-nf-call-iptables=1
      - sysctl -w net.bridge.bridge-nf-call-ip6tables=1
      - sysctl -w net.ipv4.ip_forward=1
      - sysctl -w fs.inotify.max_user_instances=524288
      - sysctl -w fs.inotify.max_user_watches=524288
      - systemctl restart ssh
devices:
  eth0:
    type: nic
    network: medcbr0
    name: eth0
```

`${MEDC_AUTHORIZED_KEYS}` is templated by `medc apply` from the
`auth.ssh_authorized_keys` list. Same pattern for other variables.

### 4.2 `medc-gateway` profile (sketch)

The fattest profile in v1 — the gateway is doing real work. Sketch
focuses on the user-data shape; concrete templating lives in
`profiles/medc-gateway.yaml.tmpl`.

```yaml
name: medc-gateway
description: MEDC gateway profile — dnsmasq + tailscaled + registry + NAT
config:
  security.privileged: "true"
  boot.autostart: "true"
  boot.autostart.delay: "0"          # gateway boots first; no delay
  user.user-data: |
    #cloud-config
    packages:
      - openssh-server
      - sudo
      - chrony
      - systemd-resolved
      - curl
      - ca-certificates
      - dnsmasq
      - iptables
      - iptables-persistent
      - tailscale
      - wireguard
      - docker.io                    # for registry:2 container
    write_files:
      - path: /etc/medc/dnsmasq.conf
        content: ${MEDC_DNSMASQ_CONFIG}
      - path: /etc/medc/iptables.rules.v4
        content: ${MEDC_IPTABLES_V4}
      - path: /etc/sysctl.d/99-medc-gateway.conf
        content: |
          net.ipv4.ip_forward=1
          net.ipv4.conf.all.forwarding=1
      - path: /etc/systemd/network/10-eth1.network
        content: |
          [Match]
          Name=eth1
          [Network]
          DHCP=ipv4
    runcmd:
      - sysctl --system
      - systemctl enable systemd-networkd && systemctl restart systemd-networkd
      - iptables-restore < /etc/medc/iptables.rules.v4
      - netfilter-persistent save
      - systemctl enable dnsmasq && systemctl restart dnsmasq
      - tailscale up --authkey=${MEDC_TS_GATEWAY_AUTH_KEY}
                     --advertise-routes=10.0.3.0/24
                     --advertise-tags=tag:medc-app-admin
                     --hostname=medc-gateway
      - docker run -d --name registry --restart=always
                   -p 5000:5000
                   -v /var/lib/medc/registry:/var/lib/registry
                   registry:2
      - mkdir -p /var/lib/medc/binaries
      - docker run -d --name binaries --restart=always
                   -p 80:80
                   -v /var/lib/medc/binaries:/usr/share/nginx/html:ro
                   nginx:stable
devices:
  eth0:                              # lab-side NIC on medcbr0
    type: nic
    network: medcbr0
    name: eth0
  eth1:                              # uplink NIC, host-passed
    type: nic
    nictype: macvlan
    parent: ${MEDC_EGRESS_INTERFACE}
    name: eth1
  registry-data:                     # persistent registry volume
    type: disk
    pool: medc
    path: /var/lib/medc/registry
    size: 20GiB
  binaries-data:                     # persistent binary host volume
    type: disk
    pool: medc
    path: /var/lib/medc/binaries
    size: 10GiB
```

Notes on the sketch:

- **Why docker for the registry?** Pragmatic: the upstream `registry:2`
  Distribution is shipped as a container, not as a Debian package.
  Docker is the lightest runtime that runs it inside the gateway with
  zero compose. `podman` is a viable swap; just an implementation
  detail, not a design call. The registry-as-system-package option
  (Sonatype Nexus from `apt`) is what the schema's `product: nexus`
  enum value will eventually exercise.
- **`eth1` `nictype: macvlan`** lets the gateway have its own MAC on
  the host's uplink without bridging — the gateway looks like a
  separate L2 endpoint to upstream switches/firewalls. Suits both
  cloud-VPS and corp-lab scenarios.
- **`iptables-persistent`** lives here, not on the host — closing
  the v0 gap from `MEDC-overview.md` §5.2.

### 4.3 Other role profiles

Each remaining role profile is a thin delta over `medc-base`:

- **`medc-mgmt`** — sets the mgmt default memory via `limits.memory`
  on the profile (per-instance override possible). No additional
  cloud-init payload — mgmt is just a well-configured Debian with the
  right resources, ready for k0rdent install.
- **`medc-k8s-control`** — no functional delta over base in v1.
  Reserved for future k8s-control-specific tuning if it emerges.
- **`medc-k8s-worker`** — no functional delta over base in v1.
  Reserved for future k8s-worker-specific tuning.

The k8s sysctls stay in `medc-base` because they're either useful or
harmless on every role (the gateway also benefits from
`bridge-nf-call-iptables=1` since it bridges, and `ip_forward=1` is
core to its router role). The minimal-delta role profiles are
deliberately empty; they exist to reserve a per-role surface for
future tuning without restructuring.

**Per-container tailscaled — explicitly removed:** earlier drafts of
this design called for per-container tailscaled. v1 retracts that:
the gateway is a tailscale subnet router for `10.0.3.0/24`, so role
profiles do not install tailscale. See §7 for the rationale.

### 4.4 Profile lifecycle

`medc apply` renders the profiles fresh on each invocation
(idempotent). Operator-modified profiles are not preserved — drive
all changes through `medc.yaml`. This is deliberate: profiles are
derived state, not source of truth.

---

## 5. Network design

### 5.1 Incus network creation

`medc apply` produces:

```bash
incus network create medcbr0 \
    ipv4.address=10.0.3.1/24 \
    ipv4.nat=false \
    ipv4.dhcp=false \
    ipv4.dns.mode=none \
    ipv6.address=none \
    bridge.external_interfaces= \
    raw.dnsmasq=
```

All four `ipv4.*` knobs are off: NAT, DHCP, and DNS are the gateway
instance's job. The bridge is just an L2 fabric for the lab subnet —
no L3 services attach to it from the host side. `raw.dnsmasq=` keeps
Incus's bundled dnsmasq disabled.

### 5.2 dnsmasq on the gateway

dnsmasq runs **inside the gateway instance**, not on the host. It's
installed via cloud-init in the `medc-gateway` profile (§4.2) and
configured from `/etc/medc/dnsmasq.conf` rendered by `medc apply`
and templated into the profile's `write_files`.

Rendered shape:

```conf
# Generated by `medc apply` — do not edit by hand
interface=eth0                       # the gateway's lab-side NIC
bind-interfaces
no-resolv
expand-hosts
domain=medc.local

dhcp-range=10.0.3.100,10.0.3.199,12h

# Default route handed to clients = the gateway's lab-side IP
dhcp-option=option:router,10.0.3.5
dhcp-option=option:dns-server,10.0.3.5

# Static reservations (one per topology.instances entry except gateway itself)
dhcp-host=02:medc:00:00:00:10,10.0.3.10,k0rdent-mgmt
dhcp-host=02:medc:00:00:00:14,10.0.3.20,k0s-child-master
dhcp-host=02:medc:00:00:00:15,10.0.3.21,k0s-child-worker1
dhcp-host=02:medc:00:00:00:16,10.0.3.22,k0s-child-worker2

# DNS host records
host-record=medc-gateway.medc.local,medc-gateway,10.0.3.5
host-record=k0rdent-mgmt.medc.local,k0rdent-mgmt,10.0.3.10
host-record=k0s-child-master.medc.local,k0s-child-master,10.0.3.20
host-record=k0s-child-worker1.medc.local,k0s-child-worker1,10.0.3.21
host-record=k0s-child-worker2.medc.local,k0s-child-worker2,10.0.3.22

# CNAMEs (from infra.cnames; gateway by default also appears as registry/binaries)
cname=registry.medc.local,medc-gateway.medc.local
cname=binaries.medc.local,medc-gateway.medc.local
```

dnsmasq runs as a normal `dnsmasq.service` (the package's stock
unit) inside the gateway. No bespoke systemd unit on the host.

### 5.3 Gateway's own IP (chicken-and-egg)

The gateway can't get its lab-side IP from DHCP — it's the DHCP
server. v1 sets the gateway's `eth0` IP via cloud-init at first
boot, hardcoded to `network.gateway_ip`:

```yaml
# in medc-gateway profile user-data
write_files:
  - path: /etc/systemd/network/10-eth0.network
    content: |
      [Match]
      Name=eth0
      [Network]
      Address=10.0.3.5/24
      # No gateway here — we ARE the gateway
runcmd:
  - systemctl restart systemd-networkd
```

`eth1` (the uplink to the host's egress NIC) gets DHCP from the
host's upstream network, or static config if specified — TBD
schema item if static is needed.

### 5.4 NAT (gateway-side)

The gateway runs `iptables` MASQUERADE out of `eth1` for traffic
sourced from the lab subnet:

```
*nat
:POSTROUTING ACCEPT [0:0]
-A POSTROUTING -s 10.0.3.0/24 -o eth1 -j MASQUERADE
COMMIT

*filter
:FORWARD ACCEPT [0:0]
-A FORWARD -i eth0 -o eth1 -j ACCEPT
-A FORWARD -i eth1 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
COMMIT
```

Persisted via `iptables-persistent` (apt-installed inside the
gateway, also via `runcmd: netfilter-persistent save`). This finally
closes the v0 gap from `MEDC-overview.md` §5.2 — persistence lives
in the gateway, not on the host.

### 5.5 Ingress

For ingress (Scenario A — cloud VPS, public IP), the
`connectivity.ingress` list maps to `iptables -t nat -A PREROUTING`
DNAT rules **on the gateway's `eth1`**, not on the host. Each entry:

```
-A PREROUTING -i eth1 -p <protocol> --dport <host_port> -j DNAT \
   --to-destination <target_ip>:<target_port>
```

The matching FORWARD rule is implicit in §5.4's `eth1 → eth0` rule.

Ingress is intentionally minimal in v1 — Tailscale (gateway tier,
§7) is the primary inbound path for both Scenario A and B. The
ingress block is for the OVH-style case where a specific public
service must live behind the host's public IP (e.g. exposing a
k0rdent webhook).

### 5.6 Why not `incus network forward`?

The earlier draft used `incus network forward` for ingress. With the
gateway-pattern, that doesn't compose — Incus's network forwards
target the host's NIC, but in v1 the lab subnet doesn't NAT through
the host, it routes through the gateway. Putting ingress on the
gateway via iptables DNAT keeps all the lab's L3 plumbing in one
place (the gateway) and matches what a real datacenter does (one
ingress termination point, not split between hypervisor and router).

---

## 6. Cloud-init payload design

The `runcmd` batch in `medc-base` (§4.1) handles everything that
v0 did via `init-containers.sh`, parts of `full-medc-setup.sh`'s
`configure_users_ssh`, and parts of `medc-production-ready.sh`:

| v0 source | v1 cloud-init equivalent |
|---|---|
| `init-containers.sh` apt install loop | `packages:` list |
| `init-containers.sh` `hostnamectl` | dropped — Incus sets hostname from instance name |
| `init-containers.sh` `systemctl enable systemd-resolved` | `runcmd:` |
| `medc-production-ready.sh` chrony install + start | `packages: chrony` + `runcmd:` |
| `medc-production-ready.sh` `swapoff -a` + fstab edit | `runcmd:` |
| `medc-production-ready.sh` sysctl writes | `runcmd: sysctl -w` per key |
| `full-medc-setup.sh` user create + sudo | `users:` |
| `full-medc-setup.sh` sshd config | `write_files:` |

**Documentation requirement** carried over from inventory §6: this
shift from "applied at container start by the supervisor" to
"applied once at first-boot by the guest" must be loud in
`MEDC-overview.md`. The implication: a misconfigured sysctl is only
visible after first-boot completes, not at `incus launch` time.
Verification (§9) gates on cloud-init `boot-finished`.

---

## 7. Tailscale design (two-tier, gateway-routed)

The two tiers are kept from the earlier design but the
*application-admin* tier is now a **single tailscaled on the
gateway acting as a subnet router**, not per-container. Per-container
tailscaled is explicitly retracted.

### 7.1 Host tier — operator/superuser tailnet

A tailscaled installed on the **host**, joined to the tailnet under
the `tag:medc-admin` ACL tag. Used only by MEDC superusers
troubleshooting incusd, kernel-level state, host syslog, storage
pools, etc.

- Install: `apt install tailscale` on the host (one of the
  `medc-host-prereqs.sh` steps).
- Auth: `tailscale up --authkey=$MEDC_TS_HOST_AUTH_KEY
  --advertise-tags=tag:medc-admin --hostname=<host-shortname>`.
- Auth key sourced from `connectivity.tailscale.host.auth_key_env`
  (default `MEDC_TS_HOST_AUTH_KEY`).
- The host tailnet does **not** advertise any subnet route; it's
  only for reaching the host itself.

### 7.2 Application tier — gateway subnet router

A single tailscaled inside the gateway instance, joined under
`tag:medc-app-admin` and **advertising `10.0.3.0/24` as a subnet
route**. Application admins reach lab containers (mgmt, k8s nodes)
by their lab IPs/hostnames over tailscale, with the gateway doing
the routing.

- Install: cloud-init in `medc-gateway` profile (§4.2):
  `packages: [tailscale]` + `runcmd: tailscale up --authkey=...
  --advertise-routes=10.0.3.0/24 --advertise-tags=tag:medc-app-admin
  --hostname=medc-gateway`.
- Auth key sourced from
  `connectivity.tailscale.gateway.auth_key_env` (default
  `MEDC_TS_GATEWAY_AUTH_KEY`).
- Subnet route must be **approved** in the tailnet admin UI (or
  pre-approved via tailnet ACL config) — this is a one-time op
  outside MEDC.
- App admins on the tailnet hit `k0rdent-mgmt.medc.local` (resolved
  by tailnet's MagicDNS pointing back at the gateway, or by the
  app admin's resolver pointing at the gateway's `eth0` IP via
  tailscale routing).

**What's gone vs. the earlier design:** every container running its
own tailscaled. Reasons for retraction:
- Doesn't match the "real datacenter" model the user asked for —
  real datacenters have one ingress/router, not N tailnet members.
- Operationally simpler — one tailscale node to manage, not five.
- Tailnet identity per-role can still be expressed via dnsmasq
  hostname + tailscale ACLs on the gateway tailnet IP — see §7.3.

### 7.3 ACL design (sketch — not enforced by MEDC)

The two tiers exist so that gateway-tier compromise doesn't yield
host-tier reach. Operators set up tailnet ACLs accordingly:

```hujson
{
  "tagOwners": {
    "tag:medc-admin":     ["group:medc-superusers"],
    "tag:medc-app-admin": ["group:medc-superusers"]
  },
  "autoApprovers": {
    "routes": {
      "10.0.3.0/24": ["tag:medc-app-admin"]
    }
  },
  "acls": [
    {"action": "accept",
     "src": ["group:medc-superusers"],
     "dst": ["tag:medc-admin:*", "tag:medc-app-admin:*", "10.0.3.0/24:*"]},
    {"action": "accept",
     "src": ["group:medc-app-admins"],
     "dst": ["10.0.3.0/24:*"]}
    /* app admins reach the lab subnet via the gateway, but cannot
       reach tag:medc-admin (the host tailscaled). */
  ]
}
```

The `autoApprovers.routes` entry is the one-line ACL bit that
auto-approves `10.0.3.0/24` advertised by any node tagged
`tag:medc-app-admin` — without it, every gateway re-create needs
manual approval in the tailnet UI.

**Out of scope for MEDC the tool:** MEDC doesn't manage tailnet
ACLs. The above is documentation of intent for the operator who
sets up the tailnet alongside MEDC.

### 7.4 Compromise blast radius

| If this is compromised | Attacker reach |
|---|---|
| App-admin user account on tailnet | Lab containers (10.0.3.0/24) over tailscale; *not* the host. |
| Gateway tailscaled (token theft) | Same as above — gateway already routes for the lab. |
| Gateway instance itself (RCE) | Lab containers + ability to NAT/forward; *not* the host directly, but: gateway has `eth1` on the host's uplink, so the attacker reaches the same network the host is on. Mitigation: tailnet ACLs gate the gateway's tailscale identity; uplink-side reach depends on the host's network. |
| Host root | Everything, by definition. |

The gateway is a meaningful security boundary, but it is not a
firewall against a compromised host. Treat it as the lab's perimeter,
not the operator's perimeter.

### 7.5 WireGuard alternative

`connectivity.wireguard` is an optional alternative VPN, also
terminating on the gateway. Reasons to enable:

- The operator's environment forbids tailscale (egress-rule
  whitelisting only, regulatory, or company policy bans third-party
  coordination services).
- Peering MEDC into an existing WireGuard mesh.

When `wireguard.enabled: true`, the `medc-gateway` profile's
cloud-init installs `wireguard` (apt) and writes
`/etc/wireguard/wg0.conf` with the listen port + peer list from the
schema. `wg-quick@wg0` is enabled.

WireGuard and tailscale can coexist on the gateway — they don't
collide on ports, and they advertise different routes. v1 ships
with tailscale enabled and WireGuard disabled by default.

### 7.6 Remote-clusters block (future)

`connectivity.tailscale.remote_clusters` is a list, empty in v1 ship,
shape reserved:

```yaml
remote_clusters:
  - name: site-b
    tailnet_endpoint: site-b-gateway.tailnet-a1b2.ts.net
    role: k8s-control                # how MEDC views this cluster
    tags: [tag:medc-remote]
    auth_scope: read                 # "read" | "manage"
```

When implemented, this lets MEDC reach external k0rdent clusters at
other on-prem sites via tailscale (via the gateway's tailscale
membership) and surface them through `medc status`. Schema-shape-only
in v1; no implementation needed to ship.

---

## 8. Ingress (cloud-VPS scenario)

`connectivity.ingress` is a list of host-port → lab-target
forwards realized as **iptables DNAT rules on the gateway's `eth1`**
(see §5.5). The schema:

```yaml
ingress:
  - host_port: 6443
    target: k0s-child-master
    target_port: 6443
    protocol: tcp
  - host_port: 80
    target: k0rdent-mgmt
    target_port: 8080
    protocol: tcp
```

`medc apply` resolves `target` to the topology IP and renders the
gateway's `/etc/medc/iptables.rules.v4` with the corresponding
`PREROUTING` DNAT entry. The gateway's `iptables-restore` +
`netfilter-persistent save` make them durable.

The earlier `incus network forward` model is gone with the gateway
pattern — see §5.6.

In Scenario B (corp lab), the corp firewall blocks public ingress
anyway — leave `ingress: []` and rely on the gateway's tailscale
subnet route.

---

## 8.5 Registry and binary host (gateway-resident services)

These are the §3.8 `infra` block in concrete form.

### 8.5.1 Container registry

The default `infra.registry.product: registry` runs the upstream
**OCI Distribution registry** (image `registry:2`) inside the
gateway via Docker, listening on `0.0.0.0:5000` (or whatever
`infra.registry.port` sets). Storage backed by an Incus disk device
(`registry-data` in §4.2's profile sketch) sized per
`infra.registry.data_volume_size`.

Addressed by clients as `registry.medc.local:5000` (the dnsmasq
CNAME from §3.8 and §5.2 maps `registry.medc.local` to
`medc-gateway.medc.local`, which resolves to the gateway's lab IP).

TLS is off by default in v1. Clients pulling from
`registry.medc.local:5000` need to opt into HTTP via
`/etc/docker/daemon.json` `insecure-registries` (or k0s/containerd
equivalent). For lab use this is fine; for realism, flipping
`infra.registry.tls: true` is a future schema item that pulls a
cert source — not in v1 ship.

`infra.registry.product: harbor` and `nexus` are reserved enum
values; v1 implements only `registry` and emits a clear
not-implemented error for the others. Adding Harbor or Nexus is
purely additive (drop new docker-compose / cloud-init blocks into
the gateway profile) — not a breaking change.

### 8.5.2 Binary host

A static-file HTTP server on the gateway (default: nginx running in
a docker container, mount `/var/lib/medc/binaries` read-only at
`/usr/share/nginx/html`). Listening on `0.0.0.0:80` (or
`infra.binary_host.port`). Addressed by clients as
`http://binaries.medc.local`.

Use cases:
- Pre-staged k0s/k0rdent installers, kubectl, helm.
- Custom builds operators want every lab instance to pull during
  bootstrap.
- Air-gapped lab pattern: pre-populate `infra.binary_host.root` once,
  then `binaries.medc.local` becomes the lab's only outbound
  dependency. (The registry covers OCI; the binary host covers
  everything else.)

Operators populate the binaries directory by `incus file push` to
the gateway, by syncing into the underlying volume from the host,
or (eventually) via a `medc binaries push` CLI shortcut — that's
an open ergonomic item, not a v1 blocker.

### 8.5.3 Same host, different DNS names

Per the user's call: `registry.medc.local` and `binaries.medc.local`
are CNAMEs to `medc-gateway.medc.local`. They're separate ports on
the same instance, addressed by separate hostnames so clients see
clean URLs and operators can swap the registry product or the binary
server without breaking the URL contract.

The schema lists these CNAMEs explicitly (`infra.cnames`) rather
than hardcoding them, so an operator with a real DNS infrastructure
can omit them and provide the names externally.

---

## 9. Storage and backup

### 9.1 Pool driver

| Driver | Snapshot cost | Recommended use |
|---|---|---|
| `btrfs` | instant (CoW) | **strong preference** — modern, ships in Debian, supports `incus snapshot`/`copy` efficiently |
| `zfs` | instant (CoW) | preferred when host already runs ZFS for other workloads |
| `dir` | tar-style copy | fallback when no CoW filesystem available — slow but works; explicitly opt-in |
| `lvm` / `lvm-thin` | snapshot via LVM | viable on hosts whose disk layout is already LVM-managed |

`medc-host-prereqs.sh` flags btrfs as the strong preference and
prompts before falling back to `dir`. Operators with a constraint
that prevents btrfs (existing fs choices on the host, mandated
storage tooling, etc.) can pass `--storage-driver dir` non-interactively
and accept the slower-snapshot trade-off. ZFS is a viable equivalent
to btrfs when already in play.

#### Why not bcachefs (yet)?

Bcachefs is in the mainline kernel since 6.7 and is the natural
successor candidate to btrfs for CoW-with-snapshots semantics. It is
**not** in MEDC v1's supported set because **Incus has no bcachefs
storage driver** as of this writing — the supported drivers are
`dir`, `btrfs`, `zfs`, `lvm`, `lvm-thin`, `ceph` / `cephfs` /
`cephobject`, and `linstor`. Once upstream Incus lands a `bcachefs`
driver, MEDC adds it to the enum in §3.8 and updates this section.
Tracked as a watch item; revisit annually.

`medc apply` runs `incus storage create medc <driver>` on first
apply if the pool doesn't exist. Switching drivers post-init
requires a manual `incus storage` migration — out of scope for
`medc apply`.

### 9.2 Snapshot schedule

Per-instance snapshots driven by Incus's built-in scheduler:

```yaml
config:
  snapshots.schedule: "0 2 * * *"     # daily 02:00
  snapshots.expiry: "7d"
  snapshots.pattern: "auto-{{creation_date}}"
```

Set in `medc-base`. Replaces the v0 `/usr/local/bin/backup-lxc-containers.sh`
+ cron approach. Snapshots live on the storage pool; no `tar -czf`
to a separate backup dir unless explicitly requested.

### 9.3 Off-host backup

Optional. `medc snapshot --export <instance>` produces an
`incus export` tarball in `operator.backup_dir` (`/var/backups/medc`
by default). For Scenario A (cloud VPS) this can be rsync'd to
durable off-host storage; for Scenario B (corp lab) typically
unneeded — the lab box itself is the dev environment, not the source
of truth.

---

## 10. Bring-up flow

End-to-end, on a fresh Debian Trixie host:

```bash
# 1. Host prerequisites — installs incus, dnsmasq, tailscale, modprobe
sudo medc-host-prereqs.sh

# 2. Initialize Incus (one-shot; idempotent)
sudo incus admin init --preseed < /etc/medc/incus-init.yaml

# 3. Apply the MEDC config
sudo medc apply --config medc.yaml

# 4. Wait for first-boot cloud-init to complete on every instance
sudo medc wait-ready

# 5. Verify
sudo medc status
sudo medc verify
```

### 10.1 What `medc apply` does, in order

1. **Validate** `medc.yaml` against the schema (refuse early if bad).
   Schema validation rejects: missing `gateway` role, multiple
   `gateway` instances, IPs outside `network.ipv4`, IPs inside
   `dhcp_range`, gateway IP mismatch with `network.gateway_ip`.
2. **Render** Incus profiles (`medc-base`, `medc-gateway`,
   `medc-<role>`) from the YAML — including the gateway's full
   cloud-init payload (dnsmasq config, iptables rules, tailscale
   auth, registry/binaries docker run lines, CNAMEs). Push via
   `incus profile`.
3. **Ensure storage pool** exists (`incus storage create` if not).
4. **Ensure network** exists with NAT off, DHCP off, DNS off
   (§5.1). `incus network create` or `incus network edit`.
5. **Launch the gateway first.** `incus init` with profiles + MAC
   + memory + CPU; attach `eth1` macvlan device on the host's
   egress NIC; attach the `registry-data` and `binaries-data`
   disk devices; `incus start medc-gateway`.
6. **Wait for the gateway to be ready.** Two gates:
   - `cloud-init status --wait` returns inside the gateway
     (signals `runcmd` finished).
   - `medc-gateway:53` answers a test DNS query from the host
     (signals dnsmasq is serving).
7. **Launch remaining instances** (mgmt → k8s-control → k8s-workers
   in parallel within each tier):
   - if missing: `incus init --profile medc-base --profile medc-<role>
     <name>`, set `volatile.eth0.hwaddr` to the topology MAC,
     set `limits.cpu`/`limits.memory`, `incus start`.
   - if present: reconcile profile membership and resource limits
     (no destroy/rebuild without `--force`).
8. **No host-side ingress step.** Ingress lives in the gateway's
   iptables rules (rendered into the profile in step 2). Step 7
   started the gateway, so ingress is already live.

### 10.2 Gateway-first ordering: why it matters

Every other instance gets its IP, default route, and DNS resolver
from the gateway's dnsmasq. Bringing them up before the gateway is
serving leads to either DHCP failure (no lease) or stale leases from
a previous run. The two-gate readiness check in step 6 makes the
ordering hard.

The gateway's own IP comes from cloud-init writing
`/etc/systemd/network/10-eth0.network` with a hardcoded
`Address=10.0.3.5/24` (§5.3) — it doesn't DHCP from itself. This
breaks the chicken-and-egg.

### 10.3 `incus admin init` preseed

`/etc/medc/incus-init.yaml` is shipped by `medc-host-prereqs.sh`
and minimal — it only sets the storage backend and creates the
`medc` storage pool. The MEDC network is created by `medc apply`
(not by `incus admin init`) so it can be edited atomically with
the rest of the topology.

```yaml
storage_pools:
  - name: medc
    driver: btrfs
    config:
      size: 100GiB                   # bumped from 50: registry + binaries + 5 instances
networks: []                          # MEDC owns this; not init's job
profiles: []                          # MEDC owns these; not init's job
```

---

## 11. Teardown / rebuild flow

```bash
# Stop and remove all MEDC instances + profiles + network.
# Storage pool is preserved unless --purge is given.
sudo medc destroy

# Full purge: also drop the storage pool, the dnsmasq config, and
# the prereq state (modules-load.d, sysctls). Leaves the host
# the way it was before MEDC.
sudo medc destroy --purge
```

`medc destroy` is the inverse of `medc apply` step-for-step:
forwards → instances → profiles → network → dnsmasq config →
(optional purge of storage pool, /etc/medc, /etc/modules-load.d/medc.conf).

Rebuild: `medc destroy --purge && medc apply --config medc.yaml`.
On a btrfs storage pool this is in the order of seconds for the
Incus side; the bottleneck is cloud-init first-boot inside each
instance (~30-60s per instance).

---

## 12. CLI surface

`medc <verb> [args]` — single binary (or shell script wrapper) on the
host. Verbs:

| Verb | Purpose |
|---|---|
| `apply [--config <file>]` | reconcile host state to match config; idempotent |
| `destroy [--purge]` | tear down instances/network/profiles; `--purge` also removes storage pool + host-side files |
| `status` | tabular view: instance state, IP, role, tailscale connectivity, last snapshot |
| `verify` | runs the v1 equivalent of `check-medc-health.sh` — bridge OK, dnsmasq running, instances reachable on tagged tailnet, sysctls applied inside |
| `wait-ready` | blocks until cloud-init `boot-finished` exists on every instance |
| `maintenance on \| off` | toggles `operator.maintenance_mode`; on apply, all autostart flags clear/restore |
| `snapshot <instance> [--export]` | one-shot Incus snapshot; `--export` produces a tarball in `backup_dir` |
| `restore <instance> <snapshot>` | restore an instance from a named snapshot |
| `exec <instance> -- <cmd>` | thin wrapper over `incus exec` for parity with the operator's mental model |
| `logs <instance>` | `incus console --show-log` shorthand |

All verbs read `medc.yaml` from `MEDC_CONFIG` env or `--config`,
defaulting to `/etc/medc/medc.yaml`.

---

## 13. File layout

```
.
├── README.md                         # landing page (rewritten in v1 to match new flow)
├── MEDC-overview.md                  # architecture + roadmap (v1 fold-in pending)
├── CLAUDE.md                         # agent guidance — invariants update at v1 ship
├── AGENTS.md                         # repo-wide agent policy (no v1 changes expected)
├── docs/
│   ├── lxc-parameter-inventory.md    # retired at v1 ship
│   ├── v1-design.md                  # this file; retired or folded post-ship
│   └── operator-runbook.md           # new in v1; day-2 ops
├── config/
│   └── medc.yaml.example             # commented reference config
├── profiles/
│   ├── medc-base.yaml.tmpl
│   ├── medc-gateway.yaml.tmpl        # the fat one (dnsmasq + ts + WG + registry + NAT)
│   ├── medc-mgmt.yaml.tmpl
│   ├── medc-k8s-control.yaml.tmpl
│   └── medc-k8s-worker.yaml.tmpl
├── host/
│   ├── medc-host-prereqs.sh          # apt install incus + tailscale, modprobe, sysctl persist
│   └── incus-init.yaml.tmpl          # incus admin init preseed template
├── bin/
│   └── medc                          # main CLI (shell or Go — see open items)
├── stacklit.json                     # auto-generated source map
├── DEPENDENCIES.md                   # auto-generated
└── stacklit.html                     # auto-generated, untracked
```

The v0 scripts (`full-medc-setup.sh`, `medc-production-ready.sh`,
`medc-k8s-powerup.sh`, `check-medc-health.sh`, `create-containers.sh`,
`init-containers.sh`, `crontab-entry.txt`) are **deleted** at v1
ship. They live in git history; no `legacy/` directory.

---

## 14. Migration from v0

**Clean cut.** No in-place migration tooling.

For an operator with a v0 MEDC running:

1. (Optional) `tar -czf v0-backup.tar.gz /var/lib/lxc` — snapshot the
   v0 state for paranoia, even though the lab is rebuildable.
2. `sudo systemctl stop lxc-net` and `for c in <names>; do
   lxc-stop -n $c && lxc-destroy -n $c; done` — tear down v0.
3. `sudo apt purge lxc lxc-templates dnsmasq-base` — remove v0 host
   surface. (Keep `iptables`; `dnsmasq` will be reinstalled as a
   v1 dep, distinct from the v0 `dnsmasq-base`.)
4. `sudo apt install incus dnsmasq tailscale` — pick up v1 surface.
   (Or use `medc-host-prereqs.sh` from the v1 repo, which does this.)
5. `sudo medc apply --config medc.yaml` — v1 brings up.

The v0 → v1 transition is not zero-downtime by design. The lab is
rebuildable in seconds on btrfs; live migration is engineering effort
for a use case that doesn't exist (no v0 deployment is "production"
in any sense that needs preserving).

---

## 15. Open items

### 15.1 Maintenance-mode UX

§3.9 specifies `operator.maintenance_mode: bool` as a global toggle.
Open: should there *also* be a per-instance flag (`autostart: false`
in the topology) so an operator can keep most instances running
while pulling one for maintenance?

**Working answer:** yes, both. Per-instance `autostart` is already
in the schema (§3.3); `maintenance_mode: true` overrides it for all.
This means there are two paths to "instance won't autostart": the
explicit per-instance flag and the global toggle. Confirm before
schema lock-in.

### 15.2 `medc` CLI implementation language

**Decision:** start in **shell**. Switch to Go (or Python) only if
shell becomes the limiter — i.e. if YAML parsing, schema validation,
or structured output (§15.5) start fighting us harder than they're
worth.

Concrete shell triggers that would justify the swap:
- YAML parsing pain. We'll lean on `yq` for now; if the schema grows
  past flat key/value lookups (nested lists, anchors, conditionals)
  and shell + `yq` becomes brittle, that's a switch trigger.
- Structured output. JSON for the read verbs (§15.5) is achievable
  in shell with `jq` templating, but if a verb needs to assemble a
  rich tree of state across many sources, that's a switch trigger.
- Concurrency. `medc apply` over many instances may benefit from
  parallel launches; if shell makes that gnarly, switch.

Until any of those bite, shell is the right call: faster to iterate,
fewer dependencies, consistent with the rest of the v0 codebase, and
trivial for an operator to read end-to-end.

### 15.3 Tailscale auth-key distribution

The schema sources auth keys from env vars
(`MEDC_TS_HOST_AUTH_KEY`, `MEDC_TS_GATEWAY_AUTH_KEY`). Open: should
v1 also support sealed-secret files, or HashiCorp Vault, or
tailscale's OAuth client-credentials flow?

**Working answer:** env vars only in v1. Operators with Vault/SOPS
can `export MEDC_TS_*=$(vault kv get ...)` ahead of `medc apply`.
Building secret-store integrations into MEDC itself isn't earning
its keep yet. Now that the application tier is gateway-routed
(single tailscaled), there's only one container-side auth key to
manage instead of N — this open is much smaller than it was in the
per-container draft.

### 15.4 IPv6

§3.2 says `ipv6.address=none` on the Incus network. Open: do we
support v6 in v1 at all, or punt?

**Working answer:** punt. v0 doesn't support v6 either (containers
got autoconfigured ULAs but nothing else used them). v1 ships v4-only;
v6 lands as a follow-up when there's a concrete demand.

### 15.5 Agent-friendly surface and a future API

MEDC is going to be driven by AI agents (Claude, internal automation)
as much as by human operators. v1 doesn't ship a programmatic API,
but **the design choices we make now should not preclude one** and
should make the CLI scriptable today. Concrete implications:

- **`--output json` for every read verb** in v1. `medc status`,
  `medc verify`, `medc wait-ready`, `medc snapshot --list` must
  emit machine-parseable JSON when asked. A human-readable table is
  the default; JSON is opt-in via the flag. No verb should require
  scraping human-formatted output.
- **Predictable exit codes.** `0` = success, `1` = generic failure,
  `2` = config validation error, `3` = state divergence (drift
  detected, no action taken), `4` = pre-condition not met. Document
  these as part of the CLI surface.
- **No interactive prompts in `apply`/`destroy`.** v1 must support
  fully non-interactive runs (`medc apply --yes` or `MEDC_ASSUME_YES=1`).
  Prompts are fine in `medc-host-prereqs.sh` (one-time bring-up) but
  forbidden in the daily-driver verbs.
- **Stable input shape.** The YAML schema is contract. Schema
  changes get a `medc.version` bump and a documented migration path.
  Agents pinning to `version: 1` should not break silently across
  point releases.
- **Idempotence.** `medc apply` re-runs converge to the declared
  state; agents can call it on every state change without worrying
  about cumulative side effects. Already in §10.1 but restating
  because it's the load-bearing property for agent use.

**Future REST API (post-v1):** when an agent surface beyond CLI is
needed, the natural shape is a small HTTP server on a Unix socket
(`/run/medc.sock`) exposing the same verbs. JSON-in, JSON-out,
authenticated by socket-peer-uid (root-equivalent only — same as
`medc` the CLI today). MCP-server packaging on top is straightforward
once the socket API exists. **Not in v1 ship, but listed here so
the CLI verbs and exit-code scheme are designed to lift cleanly.**

Concrete v1 deliverable from this: every verb's JSON output schema
gets documented in `docs/operator-runbook.md` (or a new
`docs/agent-surface.md` if it grows enough), versioned alongside
`medc.version`.

### 15.6 Registry product evolution path

v1 ships only `infra.registry.product: registry` (registry:2). The
`harbor` and `nexus` enum values are reserved.

Open: when the user asks for Harbor or Nexus, do we ship them as:
- (a) Additional `docker run` blocks in the gateway profile —
  simple but bloats the gateway as features grow.
- (b) A separate "services" instance role (split off from gateway) —
  cleaner but reintroduces the multi-instance complexity we just
  collapsed.
- (c) An external service the operator already runs — MEDC just
  points at it via the schema. The leanest option.

**Working answer:** (a) for `harbor` and `nexus` if/when they land,
keep the gateway "just keep it simple" framing the user articulated.
Revisit if gateway grows past one disk's worth of services.

### 15.7 WireGuard config schema details

§3.7's `wireguard` block has `peers: []` as a flat list. The peer
shape isn't fully specified in v1:

```yaml
peers:
  - name: alice-laptop
    public_key: ...
    allowed_ips: [10.0.3.0/24]
    persistent_keepalive: 25      # optional
```

Open: do we want PSK-per-peer support, endpoint-per-peer for
mesh setups, or stick to the simple road-warrior model? **Working
answer:** road-warrior only in v1; mesh is future. Document the
peer shape concretely once we've stress-tested it on a real
gateway.

### 15.8 Air-gapped binary host populate workflow

`infra.binary_host.root` is a directory inside the gateway. v1 doesn't
specify how operators put files there. Options:

- (a) `incus file push <path> medc-gateway/var/lib/medc/binaries/...`
  per file — works today, no MEDC code needed.
- (b) `medc binaries push <local-path>` CLI shortcut — thin wrapper
  around (a), nicer ergonomics.
- (c) `infra.binary_host.sources: [...]` schema item — declarative
  list of remote URLs MEDC fetches and stages on apply.

**Working answer:** (a) ships in v1 (it's free). (b) is an
ergonomic add-on; punt. (c) is the air-gapped operator's wishlist
item; punt with a note that the schema will accommodate it later.

### 15.9 Implementation-blocker resolutions (locked in PR1)

Five items the design left open and which were resolved during PR1
planning. Locked unless evidence to revisit emerges.

1. **Profile templating language: shell `envsubst`.**
   Zero dependency, matches the shell-first CLI choice (§15.2),
   profile substitution needs are flat (`${MEDC_DNSMASQ_CONFIG}`,
   `${MEDC_AUTHORIZED_KEYS}`, etc. — no conditionals, no loops).
   Switch trigger: if templating ever needs branching or nested
   iteration, that's a §15.2 limiter and we move to Go `text/template`
   (or equivalent) at the same time the CLI moves.

2. **MAC autogeneration: deterministic from the IP's last octet.**
   Format: `02:6d:65:64:63:XX` where `XX` = last octet of the
   instance's lab IP, in hex (i.e. literally the bytes spelling
   `02:medc:...:XX` — `medc` is the four hex bytes `6d 65 64 63`).
   Examples:
   - `medc-gateway` (10.0.3.5) → `02:6d:65:64:63:05`
   - `k0rdent-mgmt` (10.0.3.10) → `02:6d:65:64:63:0a`
   - `k0s-child-master` (10.0.3.20) → `02:6d:65:64:63:14`
   Idempotent across rebuilds. If the user supplies `mac` in the
   topology, `medc apply` honors it verbatim. If omitted, the
   autogenerated value is persisted into the config on first apply
   so it shows up in subsequent diffs.

3. **Binary host server: nginx (in Docker, on the gateway).**
   Already shown in §4.2's gateway profile sketch. Caddy was the
   alternative — nginx wins on familiarity and matches the existing
   sketch. Switch trigger: if registry+binaries grow to need shared
   TLS termination or auth, evaluate Caddy at that point.

4. **`egress_interface: auto` resolution.**
   `medc apply` resolves to the host's first default-route NIC:
   ```
   ip -4 route show default | awk '/default/ {print $5; exit}'
   ```
   If `ip route` returns no default, refuse to apply with exit code
   4 (precondition not met). Documented in `medc verify` output
   so operators see the resolution result on every status read.

5. **IP / DHCP-range overlap validation.**
   `medc apply` runs these checks before any Incus call. All
   failures collected and printed; exit code 2 (config error).
   Pseudocode:
   ```
   for inst in topology.instances:
     refuse_if not inst.ip in network.ipv4
     refuse_if inst.ip in network.dhcp_range
   refuse_unless exactly_one(role == "gateway")
   refuse_unless gateway.ip == network.gateway_ip
   refuse_if duplicate_ips(topology.instances)
   refuse_if duplicate_macs(topology.instances)  # after autogen
   ```

The state artifact (a sixth resolution, large enough to deserve its
own section) is documented in §16 below.

---

## 16. State artifact

### 16.1 Purpose

`medc apply` writes a structured state artifact at
`/etc/medc/state.json` after a successful apply. The artifact is
**MEDC's contract with downstream repos**: a machine-readable
description of the as-built lab that the k0s installer (separate
repo) and any other downstream tooling can consume without scraping
`incus list` or re-deriving from `medc.yaml`.

Three-repo architecture:

```
  ┌─────────────────────────────────────────────────────────┐
  │  MEDC (this repo)         — produces state.json         │
  └──────┬──────────────────────────────────────────────────┘
         │ /etc/medc/state.json
         ▼
  ┌─────────────────────────────────────────────────────────┐
  │  k0s installer (separate)  — reads state.json,          │
  │                              installs k0s on mgmt +     │
  │                              child cluster              │
  └──────┬──────────────────────────────────────────────────┘
         │ kubeconfig
         ▼
  ┌─────────────────────────────────────────────────────────┐
  │  k0rdent-deployment (separate) — `kubectl --context`    │
  │                                  helm-installs kcm/ksm  │
  └─────────────────────────────────────────────────────────┘
```

MEDC has no other interface obligations to downstream — no SSH
preconditions on mgmt, no preinstalled tools, nothing in
`/etc/k0rdent/`. Just the artifact.

### 16.2 Schema

```json
{
  "medc_version": "1",
  "applied_at": "2026-04-30T17:23:00Z",
  "host": {
    "egress_interface": "eth0"
  },
  "network": {
    "name": "medcbr0",
    "ipv4": "10.0.3.0/24",
    "bridge_address": "10.0.3.1",
    "gateway_ip": "10.0.3.5",
    "dns_domain": "medc.local",
    "dhcp_range": "10.0.3.100-10.0.3.199"
  },
  "instances": [
    {
      "name": "medc-gateway",
      "role": "gateway",
      "ip": "10.0.3.5",
      "mac": "02:6d:65:64:63:05",
      "fqdn": "medc-gateway.medc.local",
      "cpu": 2,
      "memory": "4GiB",
      "services": ["dnsmasq", "tailscale-subnet-router",
                   "wireguard", "registry", "binary-host", "nat"]
    },
    {
      "name": "k0rdent-mgmt",
      "role": "mgmt",
      "ip": "10.0.3.10",
      "mac": "02:6d:65:64:63:0a",
      "fqdn": "k0rdent-mgmt.medc.local",
      "cpu": 2,
      "memory": "8GiB",
      "services": []
    }
    /* k0s-child-master, k0s-child-worker1, k0s-child-worker2 ... */
  ],
  "endpoints": {
    "registry":    "registry.medc.local:5000",
    "binary_host": "http://binaries.medc.local",
    "gateway_ssh": "robot@medc-gateway.medc.local"
  },
  "downstream_hints": {
    "k8s_install_target_mgmt":   "k0rdent-mgmt",
    "k8s_install_target_master": "k0s-child-master",
    "k8s_install_target_workers":["k0s-child-worker1", "k0s-child-worker2"],
    "ingress_via":               "medc-gateway"
  }
}
```

### 16.3 Field semantics

- **`medc_version`** — matches `medc.yaml`'s schema version. Bumped
  on breaking changes. Consumers pin and refuse-on-mismatch.
- **`applied_at`** — RFC3339 timestamp of the last successful apply.
  Useful for "is this state stale?" checks.
- **`host.egress_interface`** — the resolved host NIC pulled into the
  gateway as `eth1`. If config said `auto`, this records the
  resolution result.
- **`network.*`** — copy of the operative network config. Consumers
  use `gateway_ip` as the lab's default route, `dns_domain` for
  building hostnames.
- **`instances[]`** — ordered list (gateway first, then mgmt, then
  k8s tier). Each entry's `services` field summarizes what the
  instance runs from MEDC's perspective; non-empty for the gateway,
  empty for instances MEDC just stands up as Debian boxes.
- **`endpoints.registry`** — `host:port` form, ready for
  `containerd`'s `registry.medc.local:5000` config or a
  `--registry` flag.
- **`endpoints.binary_host`** — full URL ready for `curl`.
- **`endpoints.gateway_ssh`** — `user@host` form. The user is
  pulled from `auth.user`. Consumers bouncing through the gateway
  to reach lab containers use this.
- **`downstream_hints`** — explicit name-to-role mapping for the k0s
  installer. Hints, not directives — the consumer can ignore and
  re-derive from `instances[]` if it prefers. Naming kept
  role-explicit (`k8s_install_target_mgmt`) so a consumer doesn't
  need MEDC-internal vocabulary.

### 16.4 Write semantics

- **Path**: `/etc/medc/state.json`. Mode `0644`. Owner `root:root`.
- **Atomicity**: `medc apply` writes to `state.json.new`, then
  `rename(2)`s. Consumers reading mid-apply see either the previous
  state or the new state, never partial.
- **Idempotence**: every successful apply writes the artifact, even
  if no instance state changed. The `applied_at` timestamp is the
  only field guaranteed to differ run-to-run on a no-op apply.
- **Failure**: if apply fails before all instances are up, the
  artifact is **not** written. Consumers see the previous successful
  state, which may be stale; that's better than seeing partial state.
  `medc verify` is the way to confirm freshness.

### 16.5 Read semantics — `medc state`

```
medc state                    # pretty-print to stdout
medc state --output json      # raw JSON to stdout
```

Both modes read `/etc/medc/state.json` directly. Exit codes:
- `0` if the file exists and parses.
- `4` (precondition) if the file is missing — `medc apply` hasn't
  been run yet.
- `1` (generic) on parse failure.

The pretty-printed mode is for humans (table of instances + summary
of endpoints). The JSON mode is the contract — consumers should
prefer `medc state --output json` over reading `/etc/medc/state.json`
directly so that future implementations could move the path.

### 16.6 Compatibility expectations

The state artifact is a **stable public contract** — same status as
the YAML schema. Within a major version:
- Fields are added at the end of an object.
- Fields are never renamed or removed.
- New `services[]` entries may appear on the gateway.

Across major versions: the `medc_version` bumps; consumers see the
bump and refuse-or-migrate per their own contract.

---

## 17. What's deliberately not in v1

- **k0rdent / k0smotron install on top of MEDC** — out of repo.
- **Multi-host Incus clustering** — single-host v1 first, cluster
  story later.
- **OCI / VM instances** — Incus supports both, but v1 ships
  containers only. The schema's `image` block doesn't preclude
  adding `type: vm` later; explicitly noting now so the schema
  doesn't grow that field prematurely.
- **GUI / TUI** — `medc` is CLI-only.
- **Live-migration of v0 → v1** — see §14.
- **Tailscale ACL management from MEDC** — see §7.3.
- **Non-Debian guest distros** — v1 hardcodes Debian Trixie for
  cloud-init compatibility. Adding more is a schema enum extension,
  not a structural change.
