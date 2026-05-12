# Tracking Standard

## Purpose

Define a reusable progress-tracking method for phased delivery work.
This document is intended to be portable across repositories.

## Model

Use a two-layer tracking model:

- High-level tracker: `TODO.md`
- Phase execution trackers: `docs/pr*-*-checklist.md`

`TODO.md` answers "what phase are we in?" and "what is next?".
Phase checklists answer "what exact work remains?" and "what tests prove it?".

## Required Structure

For each phase PR:

1. Add a high-level bullet in `TODO.md` under the pipeline section.
2. Add a dedicated checklist file in `docs/`.
3. Link the `TODO.md` phase bullet to that checklist file.

Checklist file naming convention:

- `docs/pr<phase>-<short-name>-checklist.md`

Examples:

- `docs/pr3-host-prereqs-checklist.md`
- `docs/pr4-medc-apply-core-checklist.md`

## Checklist Contents (Mandatory)

Each phase checklist must contain:

- Purpose
- Scope
- Non-goals
- Implementation Work Items (atomic checkboxes)
- Mandatory Test Requirements (checkboxes)
- Test Evidence Log (ID, command, expected, actual, pass/fail)
- Exit Criteria
- Handoff Notes

Use this template:

- `docs/pr-phase-checklist-template.md`

## Completion Rules

A phase is review-ready only when:

- all implementation items are complete,
- all mandatory tests are marked pass,
- command-level evidence is recorded in the checklist,
- out-of-scope items are not bundled.

## Operational Notes

- Keep `TODO.md` concise and status-oriented.
- Keep detailed execution/test evidence in phase checklists.
- Record deferred work explicitly in Handoff Notes with target phase.
- Prefer minimal, phase-scoped changes over broad refactors.

## Optional: Host-Phase Preflight Pattern

For phases that run on real hosts (package install, kernel/sysctl,
runtime checks), add a reusable preflight block to the phase README
or checklist before mandatory test execution.

Recommended preflight checks:

- OS and privilege readiness (`/etc/os-release`, `sudo -v`)
- default route/network availability
- package visibility in apt repos
- disk and memory headroom
- required files exist on the checked-out branch

Example:

```bash
set -euo pipefail

uname -a
cat /etc/os-release
sudo -v

ip -4 route show default
apt-cache policy incus tailscale iptables-persistent | sed -n '1,20p'

df -h /
free -h

test -f host/medc-host-prereqs.sh
test -f host/incus-init.yaml.tmpl
```
