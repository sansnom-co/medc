# PR6 Checklist — Destroy + Maintenance Verbs

## Purpose

This file is the execution tracker for v1 PR6.
It covers teardown behavior (`medc destroy`) and maintenance-mode controls (`medc maintenance on|off`).

## Scope

- Implement `medc destroy` with and without `--purge`.
- Implement `medc maintenance on|off` behavior integrated with apply semantics.
- Ensure teardown order is safe and predictable.
- Ensure maintenance-mode affects autostart behavior as defined.

## Non-goals

- No new read verbs or JSON output contract (PR7).
- No v0 LXC script deletion in this phase.
- No architectural expansion beyond destroy/maintenance surfaces.

## Implementation Work Items

- [ ] Add `destroy` verb routing in `bin/medc`.
- [ ] Add `maintenance on|off` verb routing in `bin/medc`.
- [ ] Implement `medc destroy` default path (no purge):
  - [ ] remove MEDC-managed forwards/rules as applicable
  - [ ] stop and remove MEDC instances
  - [ ] remove MEDC profiles
  - [ ] remove MEDC network
  - [ ] preserve storage pool by default
- [ ] Implement `medc destroy --purge` path:
  - [ ] remove MEDC storage pool
  - [ ] remove MEDC host-side state/config artifacts defined for purge
  - [ ] keep behavior explicit and documented
- [ ] Implement `maintenance on` to set operator maintenance mode and enforce non-autostart posture.
- [ ] Implement `maintenance off` to clear maintenance mode and restore declared autostart posture.
- [ ] Ensure maintenance semantics remain consistent with per-instance `autostart` and global toggle.
- [ ] Preserve non-interactive behavior for destructive operations (`--yes` / `MEDC_ASSUME_YES=1`) per CLI contract.
- [ ] Ensure no hidden destructive behavior outside declared scope.
- [ ] Preserve exit-code contract (`0`, `1`, `2`, `3`, `4`) for destroy/maintenance flows.
- [ ] Update docs for destroy order, purge behavior, and maintenance semantics.

## Mandatory Test Requirements

- [ ] `medc destroy` removes instances/profiles/network and preserves storage pool.
- [ ] `medc destroy --purge` additionally removes storage pool and defined host-side artifacts.
- [ ] Teardown order is verified and does not leave partial dangling resources in happy path.
- [ ] Re-running `medc destroy` on already-destroyed state is safe and returns expected status.
- [ ] `maintenance on` updates mode and results in non-autostart behavior on apply.
- [ ] `maintenance off` restores declared autostart behavior on apply.
- [ ] Maintenance-mode behavior works with mixed instance-level autostart values.
- [ ] Non-interactive destroy path works without prompts.
- [ ] Exit code behavior validated for representative success/failure/precondition paths.
- [ ] Scope guard passes (no PR7 read-verb surface added).

## Test Evidence Log

| ID | Test | Command(s) | Expected | Actual | Result |
|---|---|---|---|---|---|
| T01 | Destroy (no purge) | `medc destroy` | Instances/profiles/network removed; storage preserved | _TBD_ | ⬜ |
| T02 | Destroy (purge) | `medc destroy --purge` | Storage + purge targets removed | _TBD_ | ⬜ |
| T03 | Teardown ordering | observe logs/resource state | Ordered, no partial residue in healthy path | _TBD_ | ⬜ |
| T04 | Idempotent destroy | run destroy twice | Safe repeat behavior | _TBD_ | ⬜ |
| T05 | Maintenance on | `medc maintenance on` + apply | Non-autostart posture enforced | _TBD_ | ⬜ |
| T06 | Maintenance off | `medc maintenance off` + apply | Declared autostart restored | _TBD_ | ⬜ |
| T07 | Mixed autostart semantics | fixture with varied autostart | Global/local semantics hold | _TBD_ | ⬜ |
| T08 | Non-interactive destroy | `--yes`/env mode | No prompts | _TBD_ | ⬜ |
| T09 | Exit code contract | success/failure fixtures | Codes match contract | _TBD_ | ⬜ |
| T10 | Scope guard | `git diff --name-only <base>...HEAD` | PR6-only scope | _TBD_ | ⬜ |

## Exit Criteria (PR6 Review-Ready)

- [ ] All implementation work items completed.
- [ ] All mandatory tests marked pass with evidence in the log.
- [ ] Destroy and purge behavior documented and verified.
- [ ] Maintenance on/off semantics documented and verified.
- [ ] No out-of-scope PR7 behavior included.

## Handoff Notes

- PR7 consumes this operational baseline and adds read verbs + machine-readable output.
- Any deferred teardown/maintenance edge case must be recorded with rationale and target phase.
