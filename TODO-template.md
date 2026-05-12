# TODO (Template)

Single-page status index for a phased delivery project.
This file is the high-level control plane only; detailed execution and
test evidence live in per-phase checklist files under `docs/`.

---

## Status

<Current overall project status in 1-3 lines>

## Architecture / Delivery Context

<Optional: short diagram or bullets explaining repo boundaries and contracts>

## Done

- [x] <Milestone completed>
- [x] <Milestone completed>

## In flight

- [ ] <Current open PR(s) and review state>

## Implementation pipeline (next)

Each phase lands as its own PR.

- [ ] **PR1 — <phase name>**
      <short objective>
      Detailed execution tracker: `docs/pr1-<short-name>-checklist.md`.
- [ ] **PR2 — <phase name>**
      <short objective>
      Detailed execution tracker: `docs/pr2-<short-name>-checklist.md`.
- [ ] **PR3 — <phase name>**
      <short objective>
      Detailed execution tracker: `docs/pr3-<short-name>-checklist.md`.

## Open design items

- [ ] <Open item 1>
- [ ] <Open item 2>

## Out of scope

- <Explicitly deferred item 1>
- <Explicitly deferred item 2>

## Cross-repo follow-ons (optional)

- [ ] <Dependent repo/task 1>
- [ ] <Dependent repo/task 2>

## How to refresh this file

Update this file when:

- A PR opens or merges (move bullets between Done / In flight / Next).
- Scope or sequencing changes at milestone boundaries.
- A design item is promoted to implementation or deferred.

## Methodology (Reusable)

Use a two-layer tracking model:

- `TODO.md` = high-level status and sequencing.
- `docs/pr*-*-checklist.md` = phase execution details.

Workflow:

1. Add/maintain phase bullets in `TODO.md`.
2. Link each phase to a dedicated checklist file in `docs/`.
3. Break work into atomic checkboxes in the checklist.
4. Define mandatory tests and log command-level evidence.
5. Mark phase review-ready only when all mandatory tests pass.

## Phase checklist standard

For each phase PR, maintain:

- `docs/pr<phase>-<short-name>-checklist.md`

Checklist must include:

- Purpose
- Scope
- Non-goals
- Implementation Work Items
- Mandatory Test Requirements
- Test Evidence Log
- Exit Criteria
- Handoff Notes

Use template:

- `docs/pr-phase-checklist-template.md`

## References

| Document | Purpose |
|---|---|
| `README.md` | Concise landing page. |
| `docs/TRACKING-STANDARD.md` | Reusable phase tracking methodology. |
| `docs/pr-phase-checklist-template.md` | Template for per-phase checklists. |
| `docs/<architecture-doc>.md` | Definitive design/architecture reference. |
| `config/<example-config>.yaml` | Annotated reference config (if applicable). |
