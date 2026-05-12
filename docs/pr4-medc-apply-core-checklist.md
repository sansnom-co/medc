# PR4 Checklist — medc apply Core

## Purpose

This file is the execution tracker for v1 PR4.
It breaks `medc apply` core work into atomic implementation items and mandatory test requirements with evidence.

## Scope

- Implement `medc apply` core command surface and library wiring.
- Implement config parse + schema validation.
- Implement profile rendering pipeline (`envsubst`-based).
- Ensure Incus storage pool and network reconciliation.
- Emit state artifact at `/etc/medc/state.yaml` with atomic rename semantics.

## Non-goals

- No instance launch/start sequencing (PR5).
- No gateway readiness gates (PR5).
- No destroy / maintenance verbs (PR6).
- No read verbs / JSON output surface (PR7).
- No v0 script deletion.

## Implementation Work Items

- [ ] Create `bin/medc` CLI entrypoint with `apply` verb routing.
- [ ] Create/extend `bin/medc-lib/` modules for config, validation, profiles, incus primitives, and state artifact.
- [ ] Implement config discovery order (`--config`, `MEDC_CONFIG`, default path).
- [ ] Implement YAML parse path and structured parse failure reporting.
- [ ] Implement schema validation before any Incus mutation.
- [ ] Implement validation rules for:
  - [ ] exactly one `gateway` role
  - [ ] gateway IP equals `network.gateway_ip`
  - [ ] instance IPs inside `network.ipv4`
  - [ ] instance IPs outside DHCP range
  - [ ] duplicate IP rejection
  - [ ] duplicate MAC rejection (post-autogen)
- [ ] Implement deterministic MAC autogeneration from IP last octet when omitted.
- [ ] Implement `egress_interface: auto` resolution; fail with precondition error if no default route.
- [ ] Implement profile render pipeline using `envsubst`.
- [ ] Implement rendered profile YAML parse-check before `incus profile edit`.
- [ ] Implement ensure/create/update for Incus storage pool.
- [ ] Implement ensure/create/update for Incus network (NAT off, DHCP off, DNS off per design).
- [ ] Implement apply non-interactive operation (`--yes` and `MEDC_ASSUME_YES=1`) with no interactive prompts.
- [ ] Implement stable exit-code mapping (`0`, `1`, `2`, `3`, `4`) for apply paths.
- [ ] Implement state artifact generation at `/etc/medc/state.yaml`.
- [ ] Implement atomic write flow (`state.yaml.new` then rename) and correct owner/mode semantics.
- [ ] Ensure state artifact is written only on successful apply completion.
- [ ] Add/update docs for PR4 behavior and boundaries.

## Mandatory Test Requirements

- [ ] CLI entrypoint test: `medc apply --help` works and documents flags.
- [ ] Config resolution test: `--config` overrides env/default correctly.
- [ ] Parse failure test: malformed YAML returns exit code `2` with actionable message.
- [ ] Schema failure test: invalid topology constraints return exit code `2` and aggregate errors.
- [ ] Gateway uniqueness test: zero/multiple gateway roles rejected.
- [ ] Gateway IP mismatch test rejected.
- [ ] DHCP overlap test rejected.
- [ ] Duplicate IP/MAC tests rejected.
- [ ] MAC autogen test produces deterministic values from IP octet.
- [ ] `egress_interface: auto` success path resolves expected NIC.
- [ ] `egress_interface: auto` no-default-route path returns exit code `4`.
- [ ] Profile rendering test succeeds for all required role templates.
- [ ] Rendered YAML parse-check test fails fast on broken substitution.
- [ ] Incus storage ensure test (create on missing, reconcile on existing).
- [ ] Incus network ensure test (create/reconcile with intended toggles).
- [ ] Non-interactive apply test (`--yes` and env mode) executes without prompts.
- [ ] Exit code contract test verifies representative `0/1/2/4` paths.
- [ ] State artifact path test verifies `/etc/medc/state.yaml` is produced.
- [ ] State artifact atomicity test verifies temp+rename behavior.
- [ ] State artifact write-on-success-only test verifies failure path leaves prior artifact intact.
- [ ] Idempotency test: consecutive successful applies converge without unintended drift.
- [ ] Scope guard test: no PR5/PR6/PR7 behavior added.

## Test Evidence Log

| ID | Test | Command(s) | Expected | Actual | Result |
|---|---|---|---|---|---|
| T01 | CLI help | `medc apply --help` | Usage + flags shown | _TBD_ | ⬜ |
| T02 | Config precedence | apply with flag/env/default permutations | Correct source selected | _TBD_ | ⬜ |
| T03 | Malformed YAML | apply with invalid YAML | Exit `2` + parse error | _TBD_ | ⬜ |
| T04 | Schema validation | apply with invalid topology fixtures | Exit `2` + aggregated errors | _TBD_ | ⬜ |
| T05 | Gateway uniqueness | zero/2 gateway fixtures | Rejected | _TBD_ | ⬜ |
| T06 | Gateway IP match | mismatch fixture | Rejected | _TBD_ | ⬜ |
| T07 | DHCP overlap | overlap fixture | Rejected | _TBD_ | ⬜ |
| T08 | Duplicate IP/MAC | duplicate fixture | Rejected | _TBD_ | ⬜ |
| T09 | MAC autogen | missing MAC fixture | Deterministic MACs | _TBD_ | ⬜ |
| T10 | Auto egress success | normal route table | NIC resolved | _TBD_ | ⬜ |
| T11 | Auto egress failure | no default route | Exit `4` | _TBD_ | ⬜ |
| T12 | Profile render success | render all profiles | Success | _TBD_ | ⬜ |
| T13 | Render parse-check failure | inject bad substitution | Fast fail (config error) | _TBD_ | ⬜ |
| T14 | Storage ensure | first + repeat apply | Created then reconciled | _TBD_ | ⬜ |
| T15 | Network ensure | first + repeat apply | Created then reconciled | _TBD_ | ⬜ |
| T16 | Non-interactive apply | `--yes` and env mode | No prompts | _TBD_ | ⬜ |
| T17 | Exit code contract | success/failure fixtures | Codes match contract | _TBD_ | ⬜ |
| T18 | State artifact path | check output file | `/etc/medc/state.yaml` exists | _TBD_ | ⬜ |
| T19 | Atomic write | observe temp+rename behavior | Atomic replacement | _TBD_ | ⬜ |
| T20 | Success-only write | force mid-apply failure | Prior artifact unchanged | _TBD_ | ⬜ |
| T21 | Idempotency | run apply twice | Converged/no harmful drift | _TBD_ | ⬜ |
| T22 | Scope guard | `git diff --name-only <base>...HEAD` | PR4-only scope | _TBD_ | ⬜ |

## Exit Criteria (PR4 Review-Ready)

- [ ] All implementation work items completed.
- [ ] All mandatory tests marked pass with evidence in the log.
- [ ] Exit-code behavior documented and verified.
- [ ] State artifact contract implemented at `/etc/medc/state.yaml` with atomic semantics.
- [ ] No out-of-scope PR5+ behavior included.

## Handoff Notes

- PR5 consumes PR4 apply core and adds gateway-first launch and readiness gates.
- Any deferred behavior must be recorded with rationale and target phase.
