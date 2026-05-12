# AGENTS.md

## Purpose

Repository-wide operating rules for all agents.

Always optimize for:
- correctness over speed
- minimal, reversible changes
- explicit verification over assumption
- consistency with repository conventions

Agent-specific guidance may add constraints, but must not weaken this file.

## Authority

Rule precedence:
1. `AGENTS.md`
2. agent-specific files (for example `CLAUDE.md`)
3. task instructions

If rules conflict, follow the higher level.

## Orientation and Navigation

Do not start with broad file scanning.

When a repository map is available (Stacklit):
1. orient on structure and boundaries
2. identify relevant module/subsystem
3. narrow with search
4. read only necessary files
5. edit
6. validate

Preferred tools:
- Stacklit: structure and boundaries
- `rg`: targeted content search
- `fzf`: narrowing large result sets
- direct file reads: source-of-truth verification

Rules:
- use Stacklit first when available
- use targeted search instead of blind directory browsing
- never modify code based only on structural summaries or search hits

Fallback when Stacklit is unavailable:
1. identify likely entry points manually
2. use `rg`/`fzf` to narrow candidates
3. read only required files
4. proceed conservatively

## Reading and Change Discipline

For every task:
1. identify the smallest viable change
2. keep scope tightly bounded
3. preserve existing patterns
4. avoid unrelated edits

Hard constraints:
- no broad refactors unless explicitly requested
- no unnecessary renames of files/modules/symbols
- no new dependencies without clear justification
- no opportunistic cleanup in focused tasks

All edits must be grounded in current source, not memory or inference.

## Behavioral Safety

Do not:
- introduce hidden behavioral changes
- silently alter defaults or configuration
- weaken validation, error handling, or security posture
- remove safeguards without explicit reason

If a change has side effects, state them explicitly.

## Validation and Reporting

After edits:
- run the smallest relevant validation first
- expand validation scope only as needed

Examples: targeted tests, file-scoped lint/type-check, narrow build step.

Always report:
- what was run
- what passed
- what failed
- what remains unverified

Do not claim success without evidence.

## Ambiguity and Escalation

When requirements are unclear:
- state uncertainty
- choose the least disruptive interpretation
- avoid speculative changes

Stop and escalate when:
- requirements conflict
- expected behavior is unclear and materially affects outcome
- validation indicates broader impact than requested
- change requires architectural redesign
- security/data-integrity/operational boundaries may be affected

## Output Expectations

Outputs must be:
- minimal in scope
- traceable to the request
- convention-consistent
- validated or explicitly marked unvalidated

Explanations should be concise, factual, and grounded in observed code.

## Progress Tracking Standard

Use a two-layer tracking model:
- `TODO.md`: high-level status and sequencing
- `docs/pr*-*-checklist.md`: per-phase execution (atomic tasks, mandatory tests, evidence, exit criteria)

Agent requirements:
- when opening/advancing a phase PR, update the matching checklist first
- keep `TODO.md` status-oriented; do not store detailed test evidence there
- mark phase items complete only after evidence is recorded in checklist
- treat checklist as implementation truth and `TODO.md` as phase-status truth

References:
- `docs/TRACKING-STANDARD.md`
- `docs/pr-phase-checklist-template.md`
- `TODO-template.md`

## Quick Summary

- orient with structure first
- narrow with `rg`/`fzf`
- read only what is necessary
- make small, deliberate changes
- validate before concluding
