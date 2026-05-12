# PR5 Checklist — Instance Launch + Readiness Gates

## Purpose

This file is the execution tracker for v1 PR5.
It covers gateway-first instance launch orchestration and readiness gating on top of PR4 apply core.

## Scope

- Extend `medc apply` to launch instances.
- Enforce gateway-first boot ordering.
- Implement two-gate gateway readiness checks.
- Launch remaining instances by tier, with parallelism within tier.
- Reconcile existing instances without destructive rebuilds by default.

## Non-goals

- No `medc destroy` or maintenance verbs (PR6).
- No read verbs or JSON output contract (PR7).
- No deletion of v0 LXC scripts.
- No force-rebuild behavior unless explicitly specified for this phase.

## Implementation Work Items

- [ ] Extend `medc apply` orchestration flow to include launch steps after PR4 validations/renders/ensure operations.
- [ ] Implement gateway instance create-or-reconcile path:
  - [ ] `incus init` with `medc-base` + `medc-gateway` profiles when missing.
  - [ ] Apply topology MAC, CPU, and memory settings.
  - [ ] Attach `eth1` macvlan device using resolved egress NIC.
  - [ ] Attach `binaries-data` disk device as defined by config/profile expectations.
  - [ ] Start gateway instance.
- [ ] Implement gateway readiness gate #1: cloud-init completion (`cloud-init status --wait` inside gateway).
- [ ] Implement gateway readiness gate #2: DNS service readiness (host-side query against `medc-gateway:53`).
- [ ] Abort downstream instance launch if either gateway readiness gate fails.
- [ ] Implement non-gateway launch sequencing by tier:
  - [ ] mgmt tier
  - [ ] k8s-control tier
  - [ ] k8s-worker tier
- [ ] Implement parallel launch within each tier where applicable.
- [ ] Implement existing-instance reconcile behavior (profiles/resources) without destroy/rebuild by default.
- [ ] Ensure autostart handling follows config and does not conflict with maintenance-mode semantics.
- [ ] Preserve non-interactive apply behavior (`--yes` / `MEDC_ASSUME_YES=1`) with no prompts.
- [ ] Preserve exit-code contract (`0`, `1`, `2`, `3`, `4`) for launch/readiness paths.
- [ ] Update docs for PR5 behavior, especially ordering, readiness semantics, and failure modes.

## Mandatory Test Requirements

- [ ] Fresh apply launches gateway before all other instances.
- [ ] Gateway readiness gate #1 passes in healthy path.
- [ ] Gateway readiness gate #2 passes in healthy path.
- [ ] Failure of gate #1 blocks subsequent instance launches with clear error.
- [ ] Failure of gate #2 blocks subsequent instance launches with clear error.
- [ ] Non-gateway launch order follows mgmt -> k8s-control -> k8s-worker tiers.
- [ ] Parallel launch within tier is verified where tier has multiple members.
- [ ] Existing-instance reconcile path updates profiles/resources without destructive rebuild.
- [ ] Re-run apply on converged state is idempotent and stable.
- [ ] Non-interactive apply path runs without prompts.
- [ ] Exit code behavior validated for representative success and failure cases.
- [ ] Scope guard passes (no PR6/PR7 behavior added).

## Test Evidence Log

| ID | Test | Command(s) | Expected | Actual | Result |
|---|---|---|---|---|---|
| T01 | Gateway-first ordering | apply on fresh host | Gateway launched first | _TBD_ | ⬜ |
| T02 | Gate #1 cloud-init | readiness check | Pass in healthy case | _TBD_ | ⬜ |
| T03 | Gate #2 DNS :53 | host-side DNS probe | Pass in healthy case | _TBD_ | ⬜ |
| T04 | Gate #1 failure path | induce cloud-init failure | Launch aborted downstream | _TBD_ | ⬜ |
| T05 | Gate #2 failure path | induce DNS readiness failure | Launch aborted downstream | _TBD_ | ⬜ |
| T06 | Tier sequencing | apply logs/state inspection | mgmt -> control -> workers | _TBD_ | ⬜ |
| T07 | In-tier parallelism | apply with >1 workers | Parallel worker launch observed | _TBD_ | ⬜ |
| T08 | Reconcile existing | modify limits/profiles then apply | Reconciled, no rebuild | _TBD_ | ⬜ |
| T09 | Idempotency | run apply twice | No harmful drift | _TBD_ | ⬜ |
| T10 | Non-interactive mode | `--yes` and env mode | No prompts | _TBD_ | ⬜ |
| T11 | Exit code contract | success/failure fixtures | Codes match contract | _TBD_ | ⬜ |
| T12 | Scope guard | `git diff --name-only <base>...HEAD` | PR5-only scope | _TBD_ | ⬜ |

## Exit Criteria (PR5 Review-Ready)

- [ ] All implementation work items completed.
- [ ] All mandatory tests marked pass with evidence in the log.
- [ ] Gateway-first ordering and both readiness gates are implemented and verified.
- [ ] No out-of-scope PR6+ behavior included.

## Handoff Notes

- PR6 consumes this launch flow and adds destroy/maintenance control plane behavior.
- Any deferred launch/reconcile edge case must be recorded with rationale and target phase.
