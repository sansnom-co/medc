# AGENTS.md

## Purpose

This repository is maintained with AI-assisted development.

All agents must operate with:
- correctness over speed
- minimal, reversible changes
- explicit reasoning over assumption
- adherence to repository conventions

This file defines repository-wide rules that apply to all agents.

Agent-specific files may add constraints, but must not weaken these rules.

---

## Authority Model

Precedence order:

1. `AGENTS.md`
2. agent-specific files (e.g. `agents/*.md`)
3. task instructions

Higher levels constrain lower levels.

If rules conflict, follow the higher level.

---

## Repository Map

This repository may include a Stacklit index and/or Stacklit MCP tools.

Stacklit provides a structured repository map. It is used to understand:
- modules and boundaries
- dependencies between modules
- likely entry points
- structural relationships across the codebase

Stacklit is for orientation and scope control.

It provides structure, not implementation detail.

### Rules

When Stacklit is available:
- use it first
- identify the relevant module or subsystem before reading files
- use dependency information to reduce the search space

Do not modify code based only on Stacklit output.
Always read the affected files before making changes.

---

## Repository Navigation Tools

Use repository navigation tools deliberately.

### Preferred roles

- **Stacklit**: structural orientation
- **`rg` (ripgrep)**: fast content search across the repository
- **`fzf`**: interactive narrowing and selection of files or search results
- **direct file reads**: implementation verification before editing

### Rules

- use Stacklit first for structure when available
- use `rg` for targeted repository search instead of broad manual scanning
- use `fzf` to narrow candidate files or results when many matches exist
- prefer targeted search over opening many files
- do not browse directories blindly when search can identify likely files faster

### Search discipline

Prefer this sequence:

1. Stacklit or equivalent repository map
2. `rg` to identify candidate files, symbols, strings, or configuration
3. `fzf` to narrow or select the right file/result when needed
4. direct file reads for confirmation
5. edit
6. validate

### Notes

- `rg` is preferred over broad recursive grep for repository work
- `fzf` is a narrowing tool, not a substitute for reading code
- search results are hints, not proof; verify in source before editing

---

## Repository Orientation

Do not begin by scanning files.

When a repository map is available, use it first.

### Required sequence

1. obtain a high-level overview
2. identify the relevant module or subsystem
3. inspect dependencies and boundaries
4. read only the necessary files
5. perform changes
6. validate

### Rules

- do not read large parts of the repository without reason
- do not explore directories blindly
- prefer structure, then search, then detail

---

## File Reading Policy

- read the smallest number of files required
- confirm assumptions in source before editing
- do not modify code based only on summaries or inferred structure
- do not rely on memory of similar systems

All edits must be grounded in actual code.

---

## Change Discipline

For any task:

1. identify the smallest viable change
2. keep scope tightly bounded
3. avoid unrelated edits
4. preserve existing patterns

### Constraints

- no broad refactors unless explicitly requested
- no renaming of files, modules, or symbols without need
- no new dependencies without justification
- no opportunistic cleanup during focused tasks

Prefer local, controlled changes over wide speculative edits.

---

## Behavioural Safety

- do not introduce hidden behavioural changes
- do not silently alter defaults or configuration
- do not weaken validation, error handling, or security posture
- do not remove existing safeguards without explicit reason

If a change has side effects, state them.

---

## Tool Use Policy

Use tools deliberately and in order:

1. repository map / structural tools
2. search / symbol lookup
3. direct file reads
4. edit tools
5. validation tools

### Rules

- do not rely on a single tool when verification is required
- do not infer behaviour without reading source
- do not skip validation

---

## Validation

After making changes:

- run the smallest relevant validation first
- expand scope only if required

### Examples

- targeted unit test
- file-scoped lint or type-check
- narrow build step

### Reporting

Always state:
- what was run
- what passed
- what failed
- what remains unverified

Do not claim success without evidence.

---

## Handling Ambiguity

When requirements are unclear:

- state what is uncertain
- choose the least disruptive interpretation
- avoid speculative changes

If multiple approaches exist:
- prefer the simplest
- note alternatives briefly where useful

---

## Working Style

- keep edits small and readable
- preserve repository conventions
- avoid unnecessary abstraction
- avoid over-engineering
- prefer direct, factual explanations

Clarity over cleverness.

---

## Failure Modes to Avoid

Avoid:
- broad repository scanning without direction
- edits based on assumption
- large multi-file speculative changes
- mixing unrelated changes
- skipping validation
- claiming certainty without verification

---

## Escalation

Stop and escalate when:
- requirements conflict
- expected behaviour is unclear
- validation suggests broader impact than requested
- change requires architectural redesign rather than local modification
- security, data integrity, or operational boundaries may be affected

---

## When Repository Map Is Not Available

Fallback approach:

1. identify entry points manually
2. use `rg` to locate relevant files, symbols, and configuration
3. use `fzf` to narrow candidate files where useful
4. read only required files
5. proceed conservatively

Increase caution. Reduce scope.

---

## Output Expectations

All work should be:
- minimal in scope
- traceable to the request
- consistent with repository conventions
- validated or clearly marked as unvalidated

Explanations should be:
- concise
- factual
- grounded in observed code

---

## Summary

- orient using structure before reading code
- use `rg` and `fzf` to narrow search efficiently
- read only what is necessary
- make small, deliberate changes
- validate before concluding
