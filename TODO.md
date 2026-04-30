# TODO

Single-page status of where MEDC is, what's in flight, and what's
pending. Detail lives in `docs/v1-design.md` and `MEDC-overview.md`;
agent guidance lives in `CLAUDE.md` and `AGENTS.md`. **This file is the
short index.**

---

## Status

Between **v0** (LXC MVP, in-tree, working as the legacy implementation)
and **v1** (Incus + gateway, designed, implementation underway across
a stacked PR series). v0 LXC scripts get deleted in the final PR of
the v1 series; until then they stay so the lab keeps working.

## Three-repo layered architecture

```
MEDC (this repo) ──> k0s installer (separate, being rebuilt) ──> k0rdent-deployment (separate, exists)
   produces                  reads                                    helm-installs
   state.yaml             state.yaml                                  kcm/ksm/k0rdent-ui
                          installs k0s + registry
```

MEDC's **only** contract with downstream is `/etc/medc/state.yaml`
(see `docs/v1-design.md` §16).

## Done

- [x] Rebrand from VCD/VDC to MEDC — PR #1 (`medc-rebrand-blueprint`)
- [x] v1 design docs (`docs/v1-design.md`, `docs/lxc-parameter-inventory.md`) — PR #2 (`medc-v1-design`)
- [x] Schema + reference config (`config/medc.yaml.example`) + state artifact spec (`docs/v1-design.md` §16) + blocker resolutions — PR #3 (`medc-v1-pr1-schema-spec`)

## In flight

- [ ] PRs #1, #2, #3 — open, awaiting review/merge.

## v1 implementation pipeline (next)

Each lands as its own stacked PR. Plan in
`~/.claude/plans/this-repo-contains-the-groovy-cosmos.md`.

- [ ] **v1 PR2 — profile templates**
      `profiles/medc-{base,gateway,mgmt,k8s-control,k8s-worker}.yaml.tmpl`
      Templating via shell `envsubst`. The gateway template is the fat
      one (dnsmasq + tailscale subnet router + iptables NAT + nginx
      binary host).
- [ ] **v1 PR3 — host prereqs + Incus init preseed**
      `host/medc-host-prereqs.sh`, `host/incus-init.yaml.tmpl`.
      apt installs (incus, tailscale, iptables-persistent),
      modprobe + persist (`br_netfilter`, `overlay`), sysctls
      (`ip_forward`), btrfs/dir storage choice prompt.
- [ ] **v1 PR4 — `medc apply` core**
      `bin/medc` + `bin/medc-lib/*.sh`. YAML parse, schema validation,
      profile render via `envsubst`, network + storage create, state
      artifact emit (atomic-rename).
- [ ] **v1 PR5 — `medc apply` instance launch + readiness gates**
      Gateway-first sequence with two-gate readiness (cloud-init
      finished + DNS query against `medc-gateway:53`). Other
      instances launched in parallel within tier.
- [ ] **v1 PR6 — `medc destroy` + maintenance verbs**
      `medc destroy [--purge]`, `medc maintenance on|off`.
- [ ] **v1 PR7 — read verbs + JSON output**
      `medc status`, `verify`, `wait-ready`, `state`, `snapshot`,
      `exec`, `logs`. Exit codes per `docs/v1-design.md` §15.5.
      v0 LXC scripts deleted as the final action.

## Open design items (not blocking PR2)

From `docs/v1-design.md` §15. Working answers exist; revisit at
schema lock-in or when the relevant feature lands.

- [ ] 15.1 Maintenance-mode UX — both per-instance `autostart` + global
      `operator.maintenance_mode`. Confirm both at PR4.
- [ ] 15.3 Tailscale auth-key distribution — env vars only in v1
      (`MEDC_TS_HOST_AUTH_KEY`, `MEDC_TS_GATEWAY_AUTH_KEY`). Vault /
      sealed-secrets integration is post-v1.
- [ ] 15.6 Air-gapped binary host populate — `incus file push` for v1;
      `medc binaries push` ergonomic shortcut + remote-source schema
      item are punts.

## Out of scope for v1

From `docs/v1-design.md` §17. Each is cleanly additive when an ask
emerges.

- WireGuard support (deferred — no concrete operator ask)
- Container registry (k0s installer's job; MEDC has CNAME-extensible
  dnsmasq for the operator to wire `registry.<dns_domain>` → wherever)
- k0rdent / k0smotron install (separate repo, `k0rdent-deployment`)
- Multi-host Incus clustering (single-host v1 first)
- IPv6 (punted)
- OCI / VM instances (containers only in v1)
- Non-Debian guest distros
- GUI / TUI (`medc` is CLI-only)
- Live-migration of v0 → v1 (clean rebuild only)
- Tailscale ACL management from MEDC

## Cross-repo follow-ons (not MEDC's PRs, listed for context)

- [ ] **k0s installer (second repo, being rebuilt)** — reads
      `/etc/medc/state.yaml`, installs k0s on mgmt + child cluster,
      deploys the registry/Harbor/Nexus the operator wants.
- [ ] **k0rdent-deployment** (separate repo, exists) — helm-installs
      kcm/ksm/k0rdent-ui via `kubectl --context` once the k0s mgmt
      cluster is up.
- [ ] **medc-suite meta-repo** (post-v1, all three working) — git
      submodules over the three repos + a top-level `Makefile` /
      `install.sh` orchestrator. Single `git clone --recursive`
      installs everything. Submodules over a monorepo to keep each
      tool's lifecycle independent.

## How to refresh this file

`TODO.md` is hand-edited. Update it when:

- A PR opens or merges (move bullet between Done / In flight / Pending).
- A new open design item lands in `docs/v1-design.md` §15.
- Something moves to/from §17 deliberately-not-in-v1.

The roadmap in `MEDC-overview.md` §4 and the Phase tracker in
`CLAUDE.md` are the longer-form versions of the same picture; keep
them in sync at the milestone boundaries (rebrand done, design done,
PR1 done, etc.).

## References

| Document | Purpose |
|---|---|
| `docs/v1-design.md` | Definitive v1 blueprint (1500+ lines). §3 schema, §4 profiles, §5 network, §7 tailscale, §10 bring-up, §15 open items, §16 state artifact, §17 deliberately-not-in-v1. |
| `docs/lxc-parameter-inventory.md` | Every v0 parameter mapped to its v1 equivalent. Retired at v1 ship. |
| `MEDC-overview.md` | User-facing architecture + refactor roadmap + known gaps. |
| `README.md` | Concise landing page. |
| `CLAUDE.md` | Agent guidance: hard invariants, decisions baked in, run policy, open items. |
| `AGENTS.md` | Repo-wide agent policy (top of authority chain). |
| `config/medc.yaml.example` | Annotated reference YAML — copy and edit. |
