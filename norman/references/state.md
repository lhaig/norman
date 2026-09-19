# Norman state files

Reference for the norman skill. Read when creating or editing anything under `prds/`.

## File Structure

Everything lives in `prds/` at the project root. One level only.

```
prds/
  TASKS.md           # Master task list — single source of truth for ACTIVE/TODO/BLOCKED tasks
  TASKS-archive.md   # Append-only archive of fully-completed phases (keeps TASKS.md short)
  config.md          # Project config, session limits, commands
  progress.md        # Append-only execution log (crash recovery)
  verification.md    # Verification results (created by norman verify)
  research/          # PRDs being drafted or researched (norman prd output)
  backlog/           # PRDs reviewed and ready for implementation
  active/            # PRDs currently being worked on
  done/              # Completed PRDs
```

**CRITICAL:** Task status lives ONLY in `prds/TASKS.md` (active) and `prds/TASKS-archive.md` (collapsed phases). Norman does NOT maintain a separate task file.

### TASKS.md context budget

TASKS.md is read every session, so its size is a recurring context cost. Norman auto-collapses fully-DONE phases into a one-line summary and moves their full table to `TASKS-archive.md`. This keeps TASKS.md focused on what's left without losing history. Collapse only triggers when **every** task in a phase is `DONE` — phases with `PARTIAL`, `BLOCKED`, `ACTIVE`, or `TODO` tasks stay fully expanded.

### PRD Lifecycle

Norman manages PRD file moves to match task status:
- **PRD created** → `prds/research/prd-{name}.md`
- **PRD imported** → move from `research/` to `backlog/`, extract tasks into TASKS.md
- **Task starts** → move PRD from `backlog/` to `active/`, update link in TASKS.md
- **Task completes** → move PRD from `active/` to `done/`, update link in TASKS.md
- **Task blocked/failed** → PRD stays in `active/`, status updated in TASKS.md

### TASKS.md Format

```markdown
## Phase N: [Name]

| # | Task | PRD | Status | Notes |
|---|------|-----|--------|-------|
| N.1 | Task description | [prd-name.md](backlog/prd-name.md) | TODO | |
| N.2 | Another task | [prd-name.md](active/prd-name.md) | ACTIVE | Started 2026-03-29 |
| N.3 | Done task | [prd-name.md](done/prd-name.md) | DONE (2026-03-29) | Summary note |
| N.4 | Blocked task | [prd-name.md](active/prd-name.md) | BLOCKED | Waiting on N.1 |
```

**Status values:** `TODO`, `ACTIVE`, `DONE (date)`, `BLOCKED`, `PARTIAL`

**Collapsed phase format** (after every task in a phase is DONE):

```markdown
## Phase 2: Core API — 8 tasks completed 2026-05-10 (see [TASKS-archive.md](TASKS-archive.md))
```

The full table is appended to `TASKS-archive.md` under the same heading. Phase numbers are preserved so cross-references like "needs: 2.3" still resolve via the archive.

### config.md

```markdown
# Norman Config

## Session Limits
max_tasks_per_session: 15
warn_at_tasks: 12

## Project
name: [Project Name]
repo: [repo path or URL]
created: [date]

## Commands (auto-detect from project)
build: go build -o app ./cmd/app
test: go test ./...
lint: gosec ./...

## Subagent Defaults
default_subagent: general-purpose

## Model Strategy
advisor_mode: always        # always | auto | never — controls advisory review
advisor_model: opus
default_model: sonnet
quick_model: haiku
progress_compress_after: 10
verify_rigor: single        # single | adversarial — Mode 5 verification depth

## Cleanup
sweep_mode: offer           # off | offer | auto — post-phase sweep (Mode 9)
```

Model values are the Claude tier aliases (`opus`, `sonnet`, `haiku`) or any model id the harness accepts. On a harness that does not know the alias, apply the tier mapping in the SKILL.md harness table rather than failing.

### progress.md

Append-only log for crash recovery. Each entry records:
- Date and task number
- What changed (files, commits)
- Patterns discovered (`PATTERN: [category] - [description]`)

This file is what allows norman to resume after a crash or new session. Subagents also receive relevant patterns from it.
