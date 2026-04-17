# CLAUDE.md — agent guidance for the MEDC repo

## Authority

`AGENTS.md` in this repository is the top of the authority chain and
defines repo-wide rules (orientation, change discipline, tool use,
validation, reporting, escalation). **Read it first.** This file is an
agent-specific layer underneath: it adds MEDC-specific context and
invariants, but **must not weaken** `AGENTS.md`. If anything here
conflicts with `AGENTS.md`, follow `AGENTS.md`.

## What this repo is

**MEDC** (Minimal Extendable Data Centre) is a lightweight
datacenter-simulation platform — conceptually equivalent to Proxmox or
VMware but an order of magnitude lighter. It exists so a developer can
run a full multi-cluster Kubernetes environment on a single beefy host
and exercise **k0rdent** and **k0smotron** against a topology that
mirrors a real customer deployment.

k0rdent installation itself is a *post-MEDC* step and lives outside
this repo. MEDC is only the host-platform layer.

User-facing docs: `README.md` (landing) and `MEDC-overview.md`
(architecture + roadmap + known gaps). Start there for intent.

## Current state vs target state

| Axis            | v0 — today (MVP)                        | v1 — target                   |
|-----------------|-----------------------------------------|-------------------------------|
| Runtime         | Raw LXC + hand-rolled bridge/dnsmasq/iptables | Incus managed network + profiles |
| Topology        | Hardcoded: 4 named containers, fixed IPs | Driven by a config file       |
| Credentials     | Demo `robot` user, password in shell   | Sourced from config, SSH-key by default |
| Branding        | Rebranded to MEDC as of this pass       | (stable)                      |

Agents should expect both worlds to coexist in the tree during the
refactor. Don't "tidy up" one direction prematurely.

## Hard invariants

These survive the refactor. Do not silently change any of them.

- **Default role layout**: 1 management node + 1 k0s master + 2 k0s
  workers. Matches k0rdent's child-cluster pattern; stays as the
  *default* topology after parameterization. Node *count* becomes
  configurable; the *default roles* do not.
- **Default container names** (used throughout docs and scripts):
  `k0rdent-mgmt`, `k0s-child-master`, `k0s-child-worker1`,
  `k0s-child-worker2`.
- **Default network**: `lxcbr0`, `10.0.3.0/24`, gateway `10.0.3.1`,
  DNS domain `lxc.local`. Becomes configurable; defaults stay.
- **Addressing model**: DHCP with static reservations keyed on
  container MAC (dnsmasq `dhcp-host=<mac>,<ip>,<name>`). **Not**
  hardcoded per-container IPs on the container side. This matters —
  it lets you rebuild a container and have it land on the same IP
  without editing from inside. Preserve this model when parameterizing
  and when moving to Incus.
- **Per-container defaults**: 4 GB RAM, ~2 CPU. Configurable later.
- **Rootfs default**: Debian Trixie.
- **Credentials**: `robot:<demo-pass>` today, password-auth SSH
  enabled. **Demo only.** When parameterizing, default to SSH keys
  and require credentials to come from config; do not check a default
  password into the repo.

## Files and their roles

**Live scripts** (all root-required, all operate on the host):

- `full-medc-setup.sh` — menu-driven end-to-end installer. **Writes
  `/usr/local/bin/create-k8s-lxc.sh` and
  `/usr/local/bin/test-lxc-network.sh` inline during prereqs** — those
  paths being absent on a fresh host is expected before the script
  runs.
- `create-containers.sh` — standalone container-creation path. Assumes
  `/usr/local/bin/create-k8s-lxc.sh` is already present (created by
  `full-medc-setup.sh`).
- `init-containers.sh` — in-container package init.
- `medc-production-ready.sh` — hardening pass. **Writes
  `/usr/local/bin/backup-lxc-containers.sh` and
  `/usr/local/bin/maintain-lxc-containers.sh` inline.**
- `check-medc-health.sh` — bridge / IP-forward / NAT / connectivity
  probe.
- `medc-k8s-powerup.sh` — boot-time / manual reconciliation. Currently
  there is **no systemd unit** shipped that invokes it — see
  `MEDC-overview.md` §5.3 for the gap.

**Support files**:
- `crontab-entry.txt` — suggested crontab (install manually).
- `README.md`, `MEDC-overview.md` — user-facing docs.
- `stacklit.json`, `stacklit.html`, `DEPENDENCIES.md` — auto-generated
  by `stacklit`; regenerate with `stacklit generate`. **Do not
  hand-edit.**

## Run policy

These scripts mutate the host (iptables, sysctl, apt, `/var/lib/lxc`,
`/usr/local/bin`). Default: **static review only.**

Permitted without user authorization:
- `bash -n <script>` (syntax check)
- `shellcheck <script>`
- Reading, grepping, proposing edits
- `stacklit generate` (writes only the stacklit-managed files)

**Do not run** the setup / production / powerup scripts without
explicit per-script user authorization on a disposable Debian Trixie
host dedicated to MEDC. The user's primary workstation is not that
host.

If a script fails, investigate the root cause — don't bypass safety
checks or wrap the invocation to silence failure. Many of these
scripts cascade (e.g. `create-containers.sh` depends on a file written
by `full-medc-setup.sh`), and hiding the failure obscures the cascade.

## Refactor roadmap (agent-flavoured)

Mirrors `MEDC-overview.md` §4. Current phase and what not to touch:

- **Phase A — Parameterization design** *(open)* — choose a config
  format. Working default is shell-sourced `conf/medc.env`; YAML + a
  small parser is plausible. **Do not unilaterally pick one.** Ask.
- **Phase B — Parameterize LXC scripts** — blocked on A.
- **Phase C — LXC → Incus migration** — blocked on B. Preserve the
  DHCP-static-reservations model, not per-node hardcoded IPs.
- **Phase D — Verification suite** — blocked on C.
- **Phase E — k0rdent install** — documented only, never scripted in
  this repo.

Known gaps (from `MEDC-overview.md` §5) that the refactor must fold
into scripts: container autostart config, iptables persistence,
systemd unit for `medc-k8s-powerup.sh`.

## Workflow notes

- **Stacklit**: refresh with `stacklit generate`. Installed via
  `go install github.com/glincker/stacklit/cmd/stacklit@latest`,
  symlinked into `~/.local/bin`.
- **Commits**: a shared-commit method is pending user decision. Do
  not commit on the user's behalf without explicit instruction.
- **Workspace context**: `~/Devops/CLAUDE.md` describes the wider
  workspace; its rules apply outside this subproject but this
  subproject's CLAUDE.md takes precedence inside this directory.
- **Agent-specific guidance files** in parent directories (e.g. an
  `AGENTS.md` in a sibling subproject) do not apply to MEDC.
