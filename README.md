# MEDC — Minimal Extendable Data Centre

MEDC is a lightweight datacenter-simulation platform: the same role as Proxmox
or VMware, but an order of magnitude smaller and cheaper. It exists so a
developer can stand up a full multi-cluster Kubernetes topology on a single
beefy server and exercise tooling — particularly **k0rdent** and
**k0smotron** — against a layout that mirrors what a real customer runs.

k0rdent itself installs *on top of* MEDC as a post-deployment step. This
repo is the host-platform layer only.

## Status

Between **v0** (LXC MVP, in-tree, working) and **v1** (Incus + gateway,
designed, implementation underway). v0 LXC scripts still ship for now;
they get deleted in the final v1 PR.

For the current PR pipeline, open design items, and what's out of scope,
see [`TODO.md`](TODO.md). For the v1 architecture and rationale see
[`MEDC-overview.md`](MEDC-overview.md). For the full v1 blueprint see
[`docs/v1-design.md`](docs/v1-design.md).

## Default topology (MVP)

```
Host (Debian Trixie, ARM64 or x86_64)
    └── lxcbr0 (10.0.3.0/24)
         ├── k0rdent-mgmt     10.0.3.10   management / control
         ├── k0s-child-master 10.0.3.20   k8s master
         ├── k0s-child-worker1 10.0.3.21  k8s worker
         └── k0s-child-worker2 10.0.3.22  k8s worker
```

Per-container defaults: 4 GB RAM, ~2 CPU. Default user `robot` with a demo
password (see `full-medc-setup.sh` — **do not reuse these credentials
outside the lab**).

## Quick start

```bash
# 1. Bring up networking + containers + users/SSH
sudo ./full-medc-setup.sh      # menu-driven; choose option 1 for full setup

# 2. Harden for k8s (chrony, kernel params, cgroup limits, logrotate,
#    inline-generated backup + maintenance scripts)
sudo ./medc-production-ready.sh

# 3. Verify
sudo ./check-medc-health.sh
```

On reboot, run `sudo ./medc-k8s-powerup.sh` (or wire it into systemd — see
`MEDC-overview.md` §Known gaps).

## Access

```bash
sudo lxc-attach -n k0rdent-mgmt         # direct
ssh robot@10.0.3.10                     # management node
ssh robot@10.0.3.20                     # k0s master
```

## Requirements

- **Host OS:** Debian-based (tested on Trixie)
- **Arch:** ARM64 or x86_64
- **RAM:** ≥ 16 GB (4 GB × 4 containers, plus host headroom)
- **Disk:** ≥ 50 GB
- **CPU:** 4+ cores
- **Privilege:** root on the host

## Repo layout

| File                        | Purpose                                       |
|-----------------------------|-----------------------------------------------|
| `full-medc-setup.sh`        | End-to-end installer (menu-driven)            |
| `create-containers.sh`      | Standalone container-creation path            |
| `init-containers.sh`        | In-container package init                     |
| `medc-production-ready.sh`  | k8s-hardening pass                            |
| `check-medc-health.sh`      | Host-side health probe                        |
| `medc-k8s-powerup.sh`       | Boot-time / manual startup                    |
| `crontab-entry.txt`         | Suggested crontab for health + backup + maint |
| `MEDC-overview.md`          | Architecture, roadmap, known gaps             |
| `CLAUDE.md`                 | Agent-oriented repo guidance                  |
| `stacklit.{json,html}`      | Auto-generated source map (`stacklit generate`) |
| `DEPENDENCIES.md`           | Auto-generated dependency map                 |

## Contributing

Don't silently rename, re-IP, or re-credential: specific values are
configurable-in-flight, not throwaway. The default 1-mgmt + 1-master +
2-worker role layout matches k0rdent's child-cluster pattern and stays
as the default after parameterization. See `CLAUDE.md` for the full set
of invariants and the run policy for automated agents.

## License

MIT. See `LICENSE` if present.
