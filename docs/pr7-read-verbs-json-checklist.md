# PR7 Checklist — Read Verbs + JSON Output

## Purpose

This file is the execution tracker for v1 PR7.
It covers read/inspection verbs, JSON output support, and final v0 retirement actions defined for v1 completion.

## Scope

- Implement read/inspection verbs: `status`, `verify`, `wait-ready`, `state`, `snapshot`, `exec`, `logs`.
- Implement machine-readable output options as defined for read verbs.
- Implement/verify exit-code behavior for read paths.
- Execute final v0 LXC script deletion as the last v1 action.

## Non-goals

- No new apply-core orchestration beyond PR4/PR5.
- No new destroy semantics beyond PR6.
- No post-v1 feature expansion.

## Implementation Work Items

- [ ] Add read verb routing in `bin/medc` for:
  - [ ] `status`
  - [ ] `verify`
  - [ ] `wait-ready`
  - [ ] `state`
  - [ ] `snapshot`
  - [ ] `exec`
  - [ ] `logs`
- [ ] Implement default human-readable output and `--output json` for applicable read verbs per v1 contract.
- [ ] Implement `medc state` output modes and parse behavior against `/etc/medc/state.yaml`.
- [ ] Implement stable exit-code mapping (`0`, `1`, `2`, `3`, `4`) for read verbs and precondition failures.
- [ ] Implement `wait-ready` blocking behavior with clear timeout/failure messaging.
- [ ] Implement `verify` checks aligned with documented health expectations.
- [ ] Implement `snapshot` command surface required for v1 scope.
- [ ] Implement `exec` passthrough semantics and error forwarding.
- [ ] Implement `logs` shorthand behavior and failure reporting.
- [ ] Update docs for verb usage, output modes, and expected exit codes.
- [ ] Perform final removal of v0 LXC scripts only after PR7 functionality is validated.
- [ ] Ensure no unrelated cleanup/refactor is bundled with v0 removal.

## Mandatory Test Requirements

- [ ] `status` works in default human mode and documented machine mode.
- [ ] `verify` reports healthy and unhealthy states with expected exit behavior.
- [ ] `wait-ready` succeeds in healthy case and fails clearly in failure/timeout case.
- [ ] `state` reads `/etc/medc/state.yaml` and supports documented output modes.
- [ ] Missing state artifact path returns precondition exit code (`4`).
- [ ] `snapshot` command path works for success and handles invalid targets cleanly.
- [ ] `exec` executes command in target instance and forwards non-zero status correctly.
- [ ] `logs` returns instance logs and handles missing/stopped targets clearly.
- [ ] JSON output validity is verified for applicable read verbs.
- [ ] Exit-code contract validated across representative success/failure/config/precondition paths.
- [ ] v0 LXC script deletion occurs only after read-verb validation pass.
- [ ] Scope guard passes (only PR7-scoped additions + intentional v0 removals).

## Test Evidence Log

| ID | Test | Command(s) | Expected | Actual | Result |
|---|---|---|---|---|---|
| T01 | Status output modes | `medc status` (+ machine mode if implemented) | Correct format + content | _TBD_ | ⬜ |
| T02 | Verify behavior | `medc verify` in healthy/unhealthy fixtures | Expected diagnostics + exit codes | _TBD_ | ⬜ |
| T03 | Wait-ready success | `medc wait-ready` on healthy stack | Completes successfully | _TBD_ | ⬜ |
| T04 | Wait-ready failure | induce timeout/failure | Clear failure + non-zero | _TBD_ | ⬜ |
| T05 | State output modes | `medc state` with output variants | Reads/parses artifact correctly | _TBD_ | ⬜ |
| T06 | Missing state precondition | remove/rename artifact then `medc state` | Exit `4` | _TBD_ | ⬜ |
| T07 | Snapshot path | `medc snapshot <instance>` variants | Success + clear failures | _TBD_ | ⬜ |
| T08 | Exec passthrough | `medc exec <instance> -- <cmd>` | Output + status passthrough | _TBD_ | ⬜ |
| T09 | Logs behavior | `medc logs <instance>` | Logs shown or clear error | _TBD_ | ⬜ |
| T10 | JSON validity | parse outputs with `jq` | Valid JSON | _TBD_ | ⬜ |
| T11 | Exit code contract | representative fixture matrix | Codes match contract | _TBD_ | ⬜ |
| T12 | v0 removal gating | verify order in PR steps | v0 scripts removed last | _TBD_ | ⬜ |
| T13 | Scope guard | `git diff --name-only <base>...HEAD` | PR7 scope + intentional removals | _TBD_ | ⬜ |

## Exit Criteria (PR7 Review-Ready)

- [ ] All implementation work items completed.
- [ ] All mandatory tests marked pass with evidence in the log.
- [ ] Read verbs and machine-readable outputs documented and verified.
- [ ] Exit-code contract validated for operational paths.
- [ ] v0 LXC scripts removed as final action only after validations pass.

## Handoff Notes

- This phase completes the v1 implementation pipeline.
- Any deferred behavior must be recorded with rationale and post-v1 target.
