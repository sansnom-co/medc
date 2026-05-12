# PR3 Checklist — Host Prereqs + Incus Init Preseed

## Purpose

This file is the execution tracker for v1 PR3.
It breaks work into atomic implementation items and mandatory test requirements with evidence.

## Scope

- Host prerequisite automation for MEDC v1 foundation.
- Incus init preseed template for reproducible host bootstrap.

## Non-goals

- No `medc apply` implementation.
- No profile rendering/push logic.
- No instance launch/readiness sequencing.
- No state artifact emission.
- No destroy/maintenance/read verbs.

## Implementation Work Items

- [x] Create `host/medc-host-prereqs.sh` with strict mode (`set -euo pipefail`) and safe defaults.
- [x] Ensure script is executable and includes clear usage/help text.
- [x] Implement package install path for `incus`, `tailscale`, `iptables-persistent`.
- [x] Implement runtime kernel module load for `br_netfilter` and `overlay`.
- [x] Implement persistent kernel module configuration across reboot.
- [x] Implement runtime sysctl configuration for `net.ipv4.ip_forward=1`.
- [x] Implement persistent sysctl configuration across reboot.
- [x] Implement storage driver selection flow (interactive path).
- [x] Implement deterministic non-interactive storage selection behavior (flag/env/default).
- [x] Create `host/incus-init.yaml.tmpl` compatible with `incus admin init --preseed`.
- [x] Document rendering/usage path for the preseed template.
- [x] Add/update docs for PR3 usage and boundaries (what PR3 does vs PR4).
- [ ] Confirm changes remain PR3-scoped only (no PR4 logic leakage).

## Mandatory Test Requirements

- [ ] Script syntax validation passes (`bash -n`).
- [ ] Script executability validation passes (`test -x`).
- [ ] Package install verification passes (`dpkg -s incus tailscale iptables-persistent`).
- [ ] Runtime module verification passes (`lsmod` includes `br_netfilter`, `overlay`).
- [ ] Module persistence verification passes (file content + post-reboot validation).
- [ ] Runtime sysctl verification passes (`net.ipv4.ip_forward = 1`).
- [ ] Sysctl persistence verification passes (config file + post-reboot validation).
- [ ] Interactive storage-selection path verified.
- [ ] Non-interactive storage-selection path verified.
- [ ] Preseed render + `incus admin init --preseed` success verified.
- [ ] Incus storage/network objects match preseeded values.
- [ ] Idempotency verified (second run succeeds without harmful duplication/conflicts).
- [ ] Error-path behavior verified (non-zero exit + actionable error message).
- [ ] Scope guard verified (only PR3 files changed).

## Test Evidence Log

| ID | Test | Command(s) | Expected | Actual | Result |
|---|---|---|---|---|---|
| T01 | Script syntax | `bash -n host/medc-host-prereqs.sh` | Exit 0 | Exit 0 | PASS |
| T02 | Script executable | `test -x host/medc-host-prereqs.sh` | Exit 0 | Exit 0 | PASS |
| T03 | Packages installed | `dpkg -s incus tailscale iptables-persistent` | All installed | _TBD_ | ⬜ |
| T04 | Runtime modules | `lsmod` check | Both present | _TBD_ | ⬜ |
| T05 | Module persistence | file + reboot + `lsmod` | Persisted + loaded | _TBD_ | ⬜ |
| T06 | Runtime sysctl | `sysctl net.ipv4.ip_forward` | `= 1` | _TBD_ | ⬜ |
| T07 | Sysctl persistence | file + reboot + `sysctl` | Remains `1` | _TBD_ | ⬜ |
| T08 | Storage selection (interactive) | run script interactively | Selection applied | _TBD_ | ⬜ |
| T09 | Storage selection (non-interactive) | run with flag/env | Deterministic outcome | _TBD_ | ⬜ |
| T10 | Preseed init | `incus admin init --preseed` | Exit 0 | _TBD_ | ⬜ |
| T11 | Incus objects | `incus storage list`, `incus network list` | Match expected | _TBD_ | ⬜ |
| T12 | Idempotency | run script twice | Both succeed | _TBD_ | ⬜ |
| T13 | Error-path handling | run script without root | Non-zero + clear error | `ERROR: run as root (use sudo)` | PASS |
| T14 | Scope guard | `git diff --name-only <base>...HEAD` | PR3-only files | _TBD_ | ⬜ |

## Exit Criteria (PR3 Review-Ready)

- [ ] All implementation work items completed.
- [ ] All mandatory tests marked pass with evidence in the log.
- [ ] No out-of-scope PR4+ functionality included.
- [ ] Documentation updated for operator/reviewer usability.

## Handoff Notes

- Downstream phase: PR4 (`medc apply` core) consumes artifacts/patterns established here.
- Any deferred item must be explicitly recorded with rationale and target phase.
