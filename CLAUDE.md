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
(architecture + roadmap + known gaps). Design docs:
`docs/v1-design.md` (blueprint for the Incus + gateway implementation,
≈1450 lines, definitive) and `docs/lxc-parameter-inventory.md` (v0
parameter snapshot, retired at v1 ship). Start there for intent.

## Where we are

The repo is between v0 (the running LXC MVP, rebranded to MEDC) and
v1 (Incus + gateway, fully designed but not yet implemented).

| Axis | v0 — in-tree today (MVP) | v1 — designed, not yet coded |
|---|---|---|
| Runtime | Raw LXC + hand-rolled bridge/dnsmasq/iptables on host | Incus + a **gateway instance** holding dnsmasq/NAT/tailscale/registry |
| Topology | Hardcoded: 4 named containers, fixed IPs | YAML-driven; default = 5 instances (gateway + mgmt + master + 2 workers) |
| Mgmt RAM | 4 GiB | **8 GiB** (k0rdent MCM memory pressure observed) |
| Networking | `lxcbr0`, `lxc.local`, NAT on host | `medcbr0` (NAT off), `medc.local`, gateway terminates NAT and runs dnsmasq |
| Tailscale | n/a | Two-tier: host (superuser) + gateway subnet router (no per-container) |
| Credentials | Demo `robot` user, password in shell | SSH-key by default, password auth opt-in only |
| Branding | Rebranded to MEDC | (stable) |

**Implication for agents:** `docs/v1-design.md` is the definitive
spec; the LXC scripts in the repo root are the v0 implementation
that v1 replaces wholesale. Don't "tidy up" v0 LXC scripts in
preparation for v1 — they're going to be deleted in the v1 ship PR.
Conversely, don't start writing v1 code without checking the design
doc first.

## Hard invariants

These survive the refactor. Do not silently change any of them.

- **Default role layout (v1)**: 1 **gateway** + 1 mgmt + 1 k8s-control
  + 2 k8s-workers (= 5 instances). The gateway instance is the lab's
  router/services VM (dnsmasq, tailscale subnet router, WireGuard,
  registry, binary host, NAT, ingress). Exactly one gateway per
  topology — multi-gateway HA is post-v1. Other roles' counts become
  configurable; the *default roles* don't.
- **Default container names**: `medc-gateway`, `k0rdent-mgmt`,
  `k0s-child-master`, `k0s-child-worker1`, `k0s-child-worker2`.
- **Default network**: bridge `medcbr0`, subnet `10.0.3.0/24`, lab
  gateway IP `10.0.3.5` (the gateway instance), bridge address
  `10.0.3.1`, DNS domain `medc.local`. Configurable in `medc.yaml`;
  defaults stay.
- **Addressing model**: DHCP with static reservations keyed on MAC,
  served by the **gateway's dnsmasq** (`dhcp-host=<mac>,<ip>,<name>`).
  **Not** hardcoded per-container IPs on the container side. Lets
  you rebuild any non-gateway instance and have it land on the same
  IP without editing from inside. The gateway itself uses a static
  config (chicken-and-egg).
- **Default resources**: mgmt = 8 GiB RAM, others = 4 GiB; 2 CPU
  each. The mgmt 8 GiB default is from observed k0rdent MCM memory
  pressure — don't drop it back to 4 without evidence the pressure is
  gone.
- **Rootfs default**: Debian Trixie.
- **Architecture default**: x86_64; ARM64 supported via config.
  v0's hardcoded `-a arm64` was a bug, fixed in v1.
- **Credentials**: SSH keys by default in v1, password auth opt-in
  only. Do not check default passwords into the repo. (v0's
  `robot:123robot` is demo-only and stays in v0 scripts as historical
  state until v1 deletes those scripts.)
- **Tailscale shape**: two tiers, **host tailscaled (superuser) +
  gateway tailscaled (subnet router for `10.0.3.0/24`)**. No
  per-container tailscaled — that pattern was explicitly retracted.
- **Storage**: btrfs strongly preferred, ZFS equivalent, `dir`
  explicit fallback. Bcachefs not yet supported (Incus driver gap).
- **Agent-friendly CLI surface**: every read verb must support
  `--output json`; predictable exit codes (0 success, 2 config error,
  3 drift, 4 precondition); no interactive prompts in `apply`/
  `destroy`. Schema changes bump `medc.version`. These are bake-in-now
  constraints because the future REST/MCP API depends on them.

## Files and their roles

**v0 LXC scripts** (in repo root; root-required; all operate on the
host; deleted at v1 ship):

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
- `medc-k8s-powerup.sh` — boot-time / manual reconciliation. No
  systemd unit ships invoking it — known v0 gap (see
  `MEDC-overview.md` §5.3); fixed wholesale in v1.

**Design docs** (definitive references for v1 work):

- `docs/v1-design.md` — the v1 blueprint (architecture, YAML schema,
  profiles, network, tailscale, registry, bring-up flow, CLI). Read
  this before proposing v1 code or schema changes.
- `docs/lxc-parameter-inventory.md` — every v0 parameter mapped to
  its v1 equivalent. Useful for "what does v0 do for X?" lookups.
  Retired at v1 ship.

**External research** (outside the repo, but relevant):

- `~/Devops/incus-docs/` — vendored Incus doc tree (Sphinx/Markdown,
  ~3.4 MB). Authoritative for Incus-side questions.
- `~/Devops/incus-docs/medc-migration-notes.md` — the curated
  Incus-mapping notes from earlier research; cites the doc paths.

**Support files**:
- `crontab-entry.txt` — suggested crontab (install manually).
- `README.md`, `MEDC-overview.md` — user-facing docs.
- `stacklit.json`, `stacklit.html`, `DEPENDENCIES.md` — auto-generated
  by `stacklit`; regenerate with `stacklit generate`. **Do not
  hand-edit.**

**Authority files**:
- `AGENTS.md` — repo-wide agent policy (top of authority chain).
- `CLAUDE.md` — this file.

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

## Decisions baked in

Don't re-litigate these without a concrete reason. They're settled
across `docs/v1-design.md`, `docs/lxc-parameter-inventory.md`, and
this file.

- **Architecture pattern**: gateway model. One instance terminates
  NAT, runs dnsmasq, hosts registry/binaries, runs tailscale subnet
  router. Mirrors a real-datacenter router/edge VM.
- **Config format**: YAML (`medc.yaml`). Schema in `docs/v1-design.md`
  §3. `medc.version` is contract; agents may pin to it.
- **Implementation language**: shell first (`bin/medc`). Switch to
  Go/Python only if shell becomes the limiter (concrete triggers in
  `docs/v1-design.md` §15.2).
- **Tailscale model**: two tiers (host superuser + gateway subnet
  router). No per-container tailscaled.
- **Registry default**: `registry:2` via Docker on the gateway.
  Schema reserves `harbor` and `nexus` enum values; not implemented
  in v1.
- **Storage default**: btrfs strongly preferred. Bcachefs blocked
  on upstream Incus driver.
- **CLI scriptability**: JSON output mandatory on read verbs;
  predictable exit codes; no prompts in apply/destroy. The future
  REST/MCP API depends on these being correct now.
- **Migration from v0**: clean cut. v1 ship deletes the v0 LXC
  scripts wholesale. No `legacy/` directory; git history is the
  archive.

## Roadmap (agent-flavoured)

Mirrors `MEDC-overview.md` §4 and `docs/v1-design.md`:

- **Phase A — Parameterization design** *(closed)* — config format
  decided (YAML); parameter inventory complete
  (`docs/lxc-parameter-inventory.md`).
- **Phase B — In-place LXC parameterization** *(skipped)* — the
  Incus migration *is* the parameterization. No reason to touch
  v0 LXC scripts before deletion.
- **Phase C — Incus + gateway implementation** *(in progress: design
  complete, code not started)* — see `docs/v1-design.md` for the
  spec. Implementation lands in feature branches off `master`.
  Direct push to `master` is policy-blocked; PRs only.
- **Phase D — Verification suite** — blocked on C.
- **Phase E — k0rdent install** — documented only, never scripted
  in this repo.

## Open items pending decision

From `docs/v1-design.md` §15. None block C from starting; some need
answers before specific sub-features lock in:

- **15.1 Maintenance-mode UX** — global toggle vs per-instance flag
  vs both. Working answer: both. Confirm at schema lock-in.
- **15.3 Tailscale auth-key distribution** — env vars only in v1
  (working answer); secret-store integrations punted.
- **15.6 Registry product evolution path** — when Harbor/Nexus
  land, do they stay as docker blocks on the gateway or split into
  a services instance? Working answer: stay on gateway.
- **15.7 WireGuard config schema details** — peer shape, PSK
  support. Working answer: road-warrior only in v1.
- **15.8 Air-gapped binary host populate** — how operators stage
  files. Working answer: `incus file push` is the v1 mechanism;
  CLI shortcut and remote-source schema item are punts.

## Workflow notes

- **Repo orientation**: per `AGENTS.md`, use stacklit first
  (`stacklit.json`, `DEPENDENCIES.md` are kept current — refresh
  with `stacklit generate`). Then `rg` for content search, `fzf`
  for narrowing. Both are installed and on PATH.
- **Stacklit install**: `go install
  github.com/glincker/stacklit/cmd/stacklit@latest`, symlinked into
  `~/.local/bin`. Regenerate after any rename, file add, or file
  delete.
- **Commits and pushes**: direct push to `master` is policy-blocked
  on this repo; create a feature branch, push it, open a PR. The
  v1 implementation will land as a series of PRs (one per logical
  unit; see `docs/v1-design.md` for the slice candidates). Do not
  commit on the user's behalf without explicit instruction.
- **GitHub remote**: `sansnom-co/medc` (renamed from
  `k0rdent-vcd-lab` during the rebrand; old URL still redirects).
- **Workspace context**: `~/Devops/CLAUDE.md` describes the wider
  workspace; its rules apply outside this subproject, but this
  subproject's `CLAUDE.md` and `AGENTS.md` take precedence inside
  this directory.
- **Agent-specific guidance files** in sibling subprojects
  (e.g. an `AGENTS.md` in `~/Devops/asus-fan-curve/`) do not apply
  to MEDC.
- **External research lives outside the repo**: Incus docs at
  `~/Devops/incus-docs/`, migration notes at
  `~/Devops/incus-docs/medc-migration-notes.md`. Do not vendor
  these into the repo.
