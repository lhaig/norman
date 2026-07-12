---
name: norman
description: "Autonomous project execution with crash recovery. Triggers on: norman, start norman, continue norman, run the norman, set up project, resume project, norman plan, norman import, norman verify, norman upgrade, norman prd, create a prd, write prd for, plan this feature, requirements for, spec out."
---

# Norman - Project Execution

Plan, research, execute, and verify projects with crash recovery and session persistence.

---

## Overview

Norman uses **local files in `prds/`** to track all state and **subagents for each task**, so you can:
- Resume after crashes or session ends
- Have git commits as safe checkpoints
- Keep context fresh (each task runs in isolated subagent)

**Architecture:**
- **Main agent** = Orchestrator (reads state, spawns subagents, updates files)
- **Subagents** = Workers (execute one task each with fresh context)

**Advisor model strategy** (roles are fixed, models are configurable in config.md):
- **Advisor** (`advisor_model`, default `opus`) = reviews plans before execution, reviews completed work, diagnoses failures, makes architectural calls. Set to `fable` on harnesses where Mythos-class models are available.
- **Worker** (`default_model`, default `sonnet`) = implements all tasks
- **Support** (`quick_model`, default `haiku`) = classify tasks, gather context, parse results, compress progress

**Five modes:**
1. **PRD** - Generate a requirements document in `prds/research/`
2. **Plan** - Interactive planning session that generates tasks in TASKS.md
3. **Import** - Move PRD from research to backlog, extract tasks into TASKS.md
4. **Continue** - Execute tasks via subagents until done or stopped
5. **Verify** - Validate implementation against original PRD/requirements

### Recommended Workflow

**Full lifecycle:**
```
norman prd               # Create requirements document (saves to prds/research/)
norman import            # Review PRD, move to backlog, extract tasks
continue norman          # Execute tasks
norman verify            # Validate against PRD
```

**Quick start (no PRD needed):**
```
norman plan              # Discuss and plan directly
continue norman          # Execute tasks
```

---

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
advisor_model: opus         # or fable, where available
default_model: sonnet
quick_model: haiku
progress_compress_after: 10
verify_rigor: single        # single | adversarial — Mode 5 verification depth
```

### progress.md

Append-only log for crash recovery. Each entry records:
- Date and task number
- What changed (files, commits)
- Patterns discovered (`PATTERN: [category] - [description]`)

This file is what allows norman to resume after a crash or new session. Subagents also receive relevant patterns from it.

---

## Mode 1: PRD (Requirements Generation)

Start with: "norman prd", "create a prd", "write prd for", "plan this feature", "requirements for", "spec out"

### Step 1: Clarifying Questions

Ask 3-5 critical questions where the initial prompt is ambiguous. Focus on:

- **Problem/Goal:** What problem does this solve?
- **Core Functionality:** What are the key actions?
- **Scope/Boundaries:** What should it NOT do?
- **Success Criteria:** How do we know it's done?

Format with lettered options so users can respond quickly (e.g. "1A, 2C, 3B"):

```
1. What is the primary goal?
   A. Option one
   B. Option two
   C. Other: [please specify]
```

### Step 2: Generate PRD

Generate the PRD with these sections:

#### 1. Introduction/Overview
Brief description of the feature and the problem it solves.

#### 2. Goals
Specific, measurable objectives (bullet list).

#### 3. User Stories
Each story should be small enough to implement in one focused session.

```markdown
### US-001: [Title]
**Description:** As a [user], I want [feature] so that [benefit].

**Acceptance Criteria:**
- [ ] Given [precondition], when [action], then [observable outcome]
- [ ] Or: [concrete input/state] produces [concrete output/state]
```

**Important:** Each criterion must be directly translatable into a test assertion — concrete enough that the worker can write a failing test for it *before* writing any implementation code (see tests-first directive in Mode 4, Step 5).

- Bad: "Works correctly", "Handles errors gracefully", "Performs well"
- OK: "Button shows confirmation dialog before deleting"
- Good: "Clicking Delete on a record with id=42 opens a modal containing the text 'Delete record 42?' with Confirm and Cancel buttons"
- Good: "POST /users with `{email: 'x@y.com', age: -1}` returns 400 with body `{error: 'age must be >= 0'}`"

When in doubt, ask yourself: "Could a junior developer read this and write a passing test without further clarification?" If not, make it more concrete.

#### 4. Functional Requirements
Numbered list: "FR-1: The system must..."

#### 5. Non-Goals (Out of Scope)
What this feature will NOT include.

#### 6. Technical Considerations (Optional)
Known constraints, dependencies, integration points, performance requirements.

#### 7. Success Metrics
How will success be measured?

#### 8. Open Questions
Remaining questions or areas needing clarification.

### Step 3: Save

- Save to `prds/research/prd-[feature-name].md` (kebab-case)
- Create `prds/` directory structure if it doesn't exist
- Do NOT add to TASKS.md yet (that happens during import)
- Tell the user: "PRD saved to research/. Run `norman import` when ready to extract tasks."

### Writing Style

The PRD reader may be a junior developer or AI agent. Therefore:
- Be explicit and unambiguous
- Avoid jargon or explain it
- Number requirements for easy reference
- Use concrete examples where helpful

---

## Mode 2: Plan (Interactive Planning)

Start with: "norman plan" or "plan a norman"

### Phase 1: Discovery

Ask the user questions to understand scope using AskUserQuestion with structured options:

- **What are you building?** (new feature / refactor / bug fix / migration)
- **What's the scope?** (single file / multiple files / cross-cutting / full module)
- **What areas of the codebase?** (explore to identify, ask to confirm)
- **Existing patterns to follow?** (search for similar implementations)
- **Constraints?** (backward compat, performance, external deps)

Keep asking until you have enough detail to break into concrete tasks.

### Phase 2: Task Breakdown

Break into logical units, sequence by dependencies, size each task for one focused session. Present for review:

```
Phase 1: Foundation (3 tasks)
1. [Task] - [why it's first]
2. [Task] (needs: 1)
3. [Task] (needs: 1)

Phase 2: Core (4 tasks)
4. [Task] (needs: 2, 3)
...

Does this look right? Any tasks to add, remove, or reorder?
```

### Phase 3: Generate Files

Once approved:
1. Create `prds/` directory structure if it doesn't exist (research/, backlog/, active/, done/)
2. Add tasks to `prds/TASKS.md` (create if needed, append to existing if present)
3. Create `prds/config.md` (auto-detect project commands from package.json/Makefile/pyproject.toml/go.mod)
4. Create `prds/progress.md`
5. Commit with `chore: initialize norman for [project name]`

---

## Mode 3: Import (From Research PRD)

Start with: "norman import [path]" or "norman import"

### Process

1. **Find the document** — If no path provided, look in `prds/research/` for PRD files. List them and ask which to import. If a path is given, use that directly.
2. **Read and review** — Show a summary of the PRD: goals, user stories count, functional requirements count.
3. **Extract tasks** — Parse user stories (US-001), functional requirements (FR-1), and acceptance criteria. Transform each into a task.
4. **Analyze dependencies** — Order by explicit deps, logical sequence (schema > API > UI), and cross-references.
5. **Present for review** — Show extracted tasks grouped by phase, list excluded non-goals.
6. **Move PRD** — Move from `prds/research/` to `prds/backlog/` using git mv.
7. **Update TASKS.md** — Add tasks to `prds/TASKS.md` in the appropriate phase with links to the backlog PRD.
8. **Create execution files** — Create `prds/config.md` and `prds/progress.md` if they don't exist. Auto-detect project commands.

---

## Mode 4: Continue

Start with: "continue norman", "run the norman", or just "norman"

### Step 0: Initialize Session

Read `prds/config.md`, initialize `session_tasks_completed = 0`, extract session limits.

**Migration:** If `prds/config.md` doesn't exist but `.norman/config.md` does, offer to migrate files from `.norman/` to `prds/`.

**Config drift check (passive):** After reading `prds/config.md`, do a lightweight diff of its keys against the canonical schema in Mode 8. If any canonical keys are missing or hold invalid values, print a single non-blocking notice — e.g. `config.md is missing 2 settings (verify_rigor, advisor_mode); run 'norman upgrade' to reconcile.` — then continue with the session using read-time defaults for the missing keys. This is advisory only: do NOT prompt, apply changes, or halt execution. Show it at most once per session.

### Step 1: Read State

Read `prds/TASKS.md` and `prds/progress.md`. Parse task statuses from the table: `DONE` = complete, `TODO` = pending, `ACTIVE` = in progress, `BLOCKED` = blocked.

**Progress compression:** If completed tasks exceed `progress_compress_after`, spawn a Haiku agent to compress progress.md into ~100 lines of deduplicated patterns, key decisions, and last 3 full entries.

### Step 2: Find Next Task

**First run of a session (or when multiple phases have TODO items):**
Present a summary of ready tasks grouped by phase and ask the user which task or phase to start with. Use AskUserQuestion with options like:

```
Ready tasks:

Phase 3: Sovereign Tier
  3.1 Write service account
  3.3 SIEM/SOAR event export (independent)

Phase 4: Scale and Distribution
  4.1 Cloud AI option

Which would you like to work on?
A. Start Phase 3 from the top (3.1)
B. Specific task: [number]
C. Your choice — pick the highest priority
```

**After the user picks:** auto-continue top-down within that phase. When a phase completes, ask before jumping to the next one.

**Resuming (ACTIVE tasks exist from a previous session):** skip the question and continue with the in-progress task(s).

If only one task is ready across all phases, skip the question and start it directly.

If no tasks are ready: report completion or what's blocking.

### Steps 3-6 via Workflow (default when available)

When the Workflow tool is available, run Steps 3 through 6.2 for the chosen tasks as ONE Workflow script instead of hand-orchestrating Agent calls. Read `workflow.md` (same directory as this SKILL.md) for the args contract, output schemas, and reference script. This skill's instruction is the user's opt-in to workflow orchestration.

Order of operations:
1. Orchestrator first runs Step 3.5 (gather project rules) and Step 4 (mark ACTIVE, move PRDs, read acceptance criteria) for EVERY task in the batch.
2. Launch the workflow with the batch. A batch is the ready tasks in the chosen phase with no dependencies between them — a batch of 1 is the normal sequential case. Set `isolate: true` for batches larger than 1 (workers get git worktrees).
3. The workflow pipelines each task through classify -> advisor plan review -> implement (tests-first, evidence-gated) -> advisor code review with one fix round. Every agent output is JSON-schema validated — no text parsing. The workflow never touches `prds/`, never commits, never asks the user.
4. The orchestrator processes the returned results per Step 6: commit DONE tasks (Step 6.3 — merging worktree diffs first when isolated, see workflow.md), advisor-guided recovery for FAILED, user questions for BLOCKED, mark twice-REJECTED tasks BLOCKED.

The numbered steps below are the spec for what each pipeline stage must do, and double as the direct execution path when Workflow is unavailable.

### Step 3: Classify and Prepare (Haiku)

Spawn a Haiku agent to classify each ready task. The classification guide is `subagents.md`, in the same directory as this SKILL.md — resolve its absolute path first, then include that path in the spawn prompt so Haiku reads it explicitly:

> Read `[absolute path to subagents.md]` for the classification guide. Then verify the agent you choose exists by checking `ls ~/.claude/agents/` (or confirm it is a built-in: `general-purpose`, `Explore`, `Plan`). Do NOT return an agent name that is not present in either source.

Haiku should:
1. Read the classification guide at the path above
2. Search the codebase for relevant files (Glob/Grep)
3. Read the most relevant files (max 5)
4. Verify the chosen `subagent_type` is installed
5. Return: `SUBAGENT: [agent type]`, `FILES: [paths]`, `CONTEXT: [summary]`, `COMPLEXITY: [low|medium|high]`

Classify multiple ready tasks in parallel.

### Step 3.1: Advisor Plan Review

Advisor agents in this step (and Steps 6.2, FAILED recovery, and Mode 5) run on the model set by `advisor_model` in config.md.

**When `advisor_mode` is `always`:** Spawn an advisor agent for every task.
**When `advisor_mode` is `auto`:** Only spawn if Haiku classified the task as `COMPLEXITY: high` or `medium`.
**When `advisor_mode` is `never`:** Skip this step entirely.

The Opus advisor receives the task description, acceptance criteria, classified files, and context from Step 3. It returns:
- **APPROACH:** A concise implementation plan (which files to change, what pattern to follow, edge cases to handle)
- **RISKS:** Anything the worker should watch out for (breaking changes, concurrency, security)
- **SEQUENCE:** If multiple tasks are being planned, recommended execution order
- **VERDICT:** `PROCEED` or `REVISE` — if REVISE, include what needs changing in the task definition

If the advisor returns `REVISE`, update the task description in TASKS.md before spawning the worker. Log the advisor's guidance in progress.md.

The advisor's APPROACH and RISKS are passed directly to the worker in Step 5.

### Step 3.5: Gather Project Rules (Once Per Session)

**CRITICAL:** Subagents do NOT inherit CLAUDE.md. Before spawning any worker, read and cache:
1. Project `CLAUDE.md` (tech stack rules, forbidden libraries, conventions)
2. Global `~/.claude/CLAUDE.md` (user preferences)
3. Referenced context files (e.g., `context/tech-stack.md`)

Extract key rules into a `project_rules` block included in every subagent prompt.

### Step 4: Start Task — Update Status and Move PRD

Before spawning the worker:
1. Update the task row in `prds/TASKS.md`: status `TODO` → `ACTIVE`
2. If the PRD file is in `prds/backlog/`, move it to `prds/active/` using git mv
3. Update the PRD link in the TASKS.md row to point to `active/`
4. Read the PRD file for full acceptance criteria to pass to the worker

### Step 5: Spawn Worker Subagent

Use Agent tool with subagent type from Step 3 and model `sonnet`. The prompt MUST include:
- **Project Rules** from Step 3.5 (non-negotiable)
- **Task description** from TASKS.md
- **Acceptance criteria** from the PRD file
- **Advisor guidance** — APPROACH and RISKS from Step 3.1 (if advisor was run). Frame these as requirements: "The advisor has reviewed this task and recommends the following approach..."
- **Relevant files** and **current state** from Step 3
- **Patterns & learnings** from progress.md
- **Project commands** for build/lint/test
- **Tests-first directive:** Write a failing test that encodes the acceptance criteria BEFORE writing implementation code. Then implement until the test goes green. Exception: tasks explicitly tagged `(spike)` in TASKS.md skip this — they prototype first and a follow-up task adds tests.
- Instructions to report: DONE/FAILED/BLOCKED, files changed, summary, and any `PATTERN: [category] - [description]` discoveries
- **Required evidence in DONE report:** path(s) to the test file(s) added or modified, and the final test command output showing the relevant tests pass. Reports missing this evidence will be rejected (treated as FAILED).
- Rules: do NOT commit, do NOT modify `prds/` files

Spawn multiple independent workers in parallel if multiple tasks are ready. If parallel tasks could touch overlapping files, spawn each worker with `isolation: worktree` (each gets its own git worktree) or serialize them — otherwise concurrent edits clobber each other.

### Step 6: Process Result

**DONE — Step 6.1: Verify Test Evidence**

Confirm the report includes a test file path and passing test output for the acceptance criteria. If missing (and the task is not `(spike)`-tagged), treat as FAILED and re-spawn with an explicit reminder of the tests-first directive. Do NOT proceed to advisor review or commit without tests.

**Step 6.2: Advisor Code Review**

**When `advisor_mode` is `always`:** Spawn an advisor code-reviewer agent for every completed task.
**When `advisor_mode` is `auto`:** Only spawn if the task was classified as `COMPLEXITY: high` or `medium`.
**When `advisor_mode` is `never`:** Skip to Step 6.3.

The reviewer receives: the task description, acceptance criteria, advisor's original APPROACH from Step 3.1, and the worker's reported file changes. It reads the changed files and returns:
- **QUALITY:** `PASS`, `MINOR`, or `REJECT`
- **ISSUES:** List of specific problems (if any), each with file path and description
- **PATTERNS:** Any broadly useful patterns discovered

`PASS` — Proceed to commit (Step 6.3).
`MINOR` — Log issues in progress.md as improvement notes, proceed to commit. These are suggestions, not blockers.
`REJECT` — Do NOT commit. Send the reviewer's specific issues back to the SAME worker agent as fix instructions (continue it via SendMessage — it keeps the context it built while implementing). Re-spawn a fresh worker only if continuation isn't available on this harness. After the second attempt, run the reviewer again. If rejected twice, mark BLOCKED and ask the user.

**Step 6.3: Commit**

1. Move PRD from `prds/active/` to `prds/done/` using git mv
2. Update TASKS.md row: status -> `DONE (date)`, PRD link -> `done/`, add summary note
3. **Auto-collapse phase if fully DONE** — After updating the row, check whether every task in the current phase is now `DONE`. If so:
   - Append the full phase heading + table to `prds/TASKS-archive.md` (create file if missing)
   - Replace the phase block in TASKS.md with a one-line summary: `## Phase N: [Name] — X tasks completed YYYY-MM-DD (see [TASKS-archive.md](TASKS-archive.md))`
   - Skip if any task is `PARTIAL`, `BLOCKED`, `ACTIVE`, or `TODO`
4. Append to `prds/progress.md` (date, task, changes, patterns, advisor review result)
5. Commit with `feat([scope]): [description]` (include the archive update in the same commit if a phase was collapsed)
6. If subagent or advisor reported broadly useful patterns, offer to promote to CLAUDE.md

**FAILED — Advisor-Guided Recovery:**

Instead of retrying the whole task on the advisor model, use the advisor as a diagnostician:
1. Spawn an advisor agent with the failure context (error messages, partial changes, worker's report)
2. The advisor returns: `DIAGNOSIS` (what went wrong), `FIX_GUIDANCE` (specific instructions for the worker to retry)
3. Continue the SAME worker agent (SendMessage) with the fix guidance — it already knows what it tried. Re-spawn fresh with the original task + fix guidance only if continuation isn't available.
4. If the guided retry also fails, mark BLOCKED in TASKS.md, log both failures, ask user: retry/skip/stop

**BLOCKED:** Present subagent's question to user, get answer, continue the same agent (SendMessage) with the answer. Re-spawn with additional context only if continuation isn't available.

### Step 7: Continue

Increment `session_tasks_completed`. Check limits:
- At `warn_at_tasks`: show warning, continue
- At `max_tasks_per_session`: stop, report progress, recommend fresh session

Then: more tasks ready -> Step 2. Nothing ready but some pending -> report blockers. All done -> report completion, suggest `norman verify`.

Auto-continue until: task fails, all complete, user interrupts, subagent blocked, or session limit reached.

---

## Mode 5: Verify

Start with: "norman verify"

### Process

1. **Locate requirements** — Read `prds/TASKS.md`, find DONE tasks with PRD links in `prds/done/`. If verifying a specific PRD, ask user which one.

2. **Extract requirements (Haiku)** — Parse the PRD(s) into a structured checklist: user stories with acceptance criteria, functional requirements, non-functional requirements, explicit constraints. Skip non-goals.

3. **Verify each requirement (advisor model)** — Verification is inherently an advisory task; verifiers run on `advisor_model`. Depth is controlled by `verify_rigor` in config.md (if the key is absent — e.g. a project set up before this option existed — treat it as `single`):

   - **`single` (default)** — One verifier per requirement. For each: search the codebase for the implementation, read the code, check acceptance criteria, run the relevant tests. Report `PASS`, `FAIL`, or `PARTIAL` with evidence.
   - **`adversarial`** — Two to three verifiers per requirement, each with a distinct lens (implementation-exists / tests-actually-exercise-it / edge-cases-and-constraints). Combine by majority: `PASS` only if a majority vote PASS; `FAIL` if a majority vote FAIL; otherwise `PARTIAL`. This catches confident-but-wrong single verdicts on the requirements where a false PASS is most costly.

   On harnesses with the Workflow tool, run this step as a workflow pipeline (one branch per requirement) with JSON-schema-validated verdicts instead of parsing free text — see `workflow.md`.

4. **Completeness critic (adversarial only)** — After per-requirement verdicts, spawn one advisor-model critic over the full checklist and the DONE task list. It hunts for what a per-requirement sweep structurally cannot see: acceptance criteria that no test actually exercises, requirements with no corresponding implementation, anything claimed DONE without evidence. Fold each gap it returns into the results by downgrading the affected requirement to `PARTIAL` or `FAIL`. Skipped when `verify_rigor` is `single`.

5. **Present results** — Show pass/partial/fail counts and details.

6. **Handle gaps** — Offer via AskUserQuestion:
   - **Create tasks for gaps** — Add fix tasks to `prds/TASKS.md` as a new phase, create PRDs in `prds/backlog/`, continue norman
   - **Accept as-is** — Log results, update TASKS.md notes
   - **Re-verify specific items** — Re-check individual requirements after manual fixes

Save verification report to `prds/verification.md` and commit.

---

## Mode 6: Prune

Start with: "norman prune"

Manual trigger for the same phase-collapse logic that runs automatically on task completion. Use when:
- Auto-collapse was skipped because of a stale `BLOCKED` or `PARTIAL` row that should now be re-classified
- TASKS.md was edited by hand and accumulated fully-DONE phases
- Migrating an existing project to the archive format

### Process

1. Scan `prds/TASKS.md` for phases where every task is `DONE`.
2. List them and ask the user to confirm which to collapse (default: all).
3. For each confirmed phase:
   - Append full heading + table to `prds/TASKS-archive.md`
   - Replace the phase block in TASKS.md with the one-line summary
4. Commit with `chore: prune completed phases from TASKS.md`.

If TASKS.md has no fully-DONE phases, report that and exit.

---

## Mode 7: Reset

Start with: "norman reset"

Check current state (incomplete tasks, uncommitted changes), then offer:
- **Archive** — Move `prds/config.md`, `prds/progress.md`, `prds/verification.md` to `prds/.archive/[date]/`. TASKS.md and PRD folders are NOT touched.
- **Delete** — Remove config.md, progress.md, verification.md. TASKS.md and PRD folders are NOT touched.
- **Cancel**

---

## Mode 8: Upgrade

Start with: "norman upgrade"

Reconcile an existing project's `prds/config.md` with the config schema of the current skill version. Projects set up by an older norman keep working (missing keys fall back to hardcoded defaults at read-time), but their `config.md` never gains the newer settings unless added by hand. This mode surfaces exactly what's missing, stale, or invalid and applies operator-approved changes.

**Non-destructive by contract:** existing keys with valid values are NEVER overwritten — an operator's chosen values (custom models, session limits, project commands) are preserved. The mode only ever *adds* missing keys and *flags* problems for the operator to decide on.

### Process

1. **Locate config** — Read `prds/config.md`.
   - If it doesn't exist: there's nothing to upgrade. Tell the user to run `norman plan` or `norman import` to create one, and exit.
   - If `prds/config.md` is absent but `.norman/config.md` exists: run the Mode 4 Step 0 migration (`.norman/` → `prds/`) first, then continue.

2. **Parse existing keys** — Build a map of `key → value` from the current file. Preserve section grouping and any comments.

3. **Diff against the canonical schema** (below). Classify every difference:
   - **Missing** — a canonical key not present locally. Propose adding it under its section with the default value and a one-line comment describing its options.
   - **Invalid value** — key present, but its value is not in the allowed set (e.g. `verify_rigor: strict`). Propose correcting to the nearest valid value or the default; ask.
   - **Unknown / deprecated** — a local key not in the canonical schema. FLAG it, explain it may be a removed setting or an operator customisation, and ask whether to keep or remove. NEVER auto-remove.
   - Keys present with valid values → left untouched, reported as "up to date".

4. **Present the diff** — Show a grouped summary: additions (key, default, purpose), invalid values, unknowns. If there are no differences, report "config.md is already current" and exit. Otherwise ask via AskUserQuestion:
   - **A. Apply all proposed changes** (add all missing keys with defaults; leave flagged unknowns in place)
   - **B. Choose per change** — walk each proposed addition/correction individually
   - **C. Cancel** — make no changes

5. **Apply** — Write only the approved changes:
   - Append each approved missing key under the correct `##` section (create the section if absent), with its default and comment.
   - Apply approved value corrections in place.
   - Remove unknown keys ONLY if the operator explicitly chose to.
   - Leave all other lines, values, comments, and ordering intact.

6. **Commit** — `chore: upgrade norman config.md to current schema`. Summarise what changed (added N keys, corrected M values).

### Canonical config schema

This table is the source of truth for the diff. **Keep it in sync with the `config.md` template above** whenever a new setting is introduced — the upgrade mode is only as complete as this list.

Project-specific keys (`name`, `repo`, `created` under Project; `build`, `test`, `lint` under Commands) are NOT defaulted — they're auto-detected or user-supplied. The upgrade mode reports them as missing if absent but does not invent values; it prompts the operator or re-runs auto-detection.

| Section | Key | Default | Allowed values |
|---------|-----|---------|----------------|
| Session Limits | `max_tasks_per_session` | `15` | positive integer |
| Session Limits | `warn_at_tasks` | `12` | positive integer `< max_tasks_per_session` |
| Subagent Defaults | `default_subagent` | `general-purpose` | any installed agent type |
| Model Strategy | `advisor_mode` | `always` | `always` \| `auto` \| `never` |
| Model Strategy | `advisor_model` | `opus` | `opus` \| `fable` \| any valid model |
| Model Strategy | `default_model` | `sonnet` | any valid model |
| Model Strategy | `quick_model` | `haiku` | any valid model |
| Model Strategy | `progress_compress_after` | `10` | positive integer |
| Model Strategy | `verify_rigor` | `single` | `single` \| `adversarial` |

---

## Commands

| Command | Action |
|---------|--------|
| `norman` / `continue norman` | Execute next task(s) |
| `norman prd` | Generate a PRD in prds/research/ |
| `norman plan` | Interactive planning session |
| `norman import [path]` | Review PRD, move to backlog, extract tasks |
| `norman status` | Show progress summary from TASKS.md |
| `norman task [N]` | Execute specific task |
| `norman skip [N]` | Skip a blocked task |
| `norman add [desc]` | Add new task to TASKS.md |
| `norman pause` | Stop after current task |
| `norman verify` | Verify implementation against PRD/requirements |
| `norman prune` | Collapse fully-DONE phases into TASKS-archive.md |
| `norman upgrade` | Reconcile config.md with the current skill's config schema |
| `norman reset` | Clear execution state and start fresh |
| `norman learnings` | Review and promote patterns to CLAUDE.md |

---

## Recovery

- **Session crashed** — Just say "continue norman", state is in prds/
- **Task partially complete** — Check git status, either commit partial progress or `git checkout .` and retry
- **Wrong task executed** — Revert commit, update TASKS.md status back to TODO, move PRD back to previous folder, continue
- **Subagent failed/timed out** — Check changes, commit or reset, mark BLOCKED in TASKS.md, continue or retry
- **Context getting long** — Modern harnesses auto-summarize long sessions, so norman can keep going; the session limits in config.md are mainly a cost and quality checkpoint now. All state persists in files, so a fresh session is always safe.
- **TASKS.md out of sync** — If PRD files are in a different folder than TASKS.md links suggest, trust the file system and update TASKS.md links to match

---

## Subagent Architecture

Every task runs in a subagent for fresh context and isolation. The orchestrator reads/updates `prds/` files, spawns subagents, processes results, and commits. Workers implement tasks and report results but do NOT commit or modify `prds/` files.

**Specialized agents:** The full list of agent types with classification guidance is in `subagents.md` (same directory as this file). The list must be kept in sync with the actual contents of `~/.claude/agents/` — Haiku is instructed to verify chosen agents exist before returning them.

**Parallel execution:** If multiple tasks are ready with no dependency conflicts, classify and execute in parallel. Use `isolation: worktree` when parallel workers might touch overlapping files.

**Workflow orchestration (default when available):** Mode 4 Steps 3-6 and Mode 5 verification run as Workflow scripts with JSON-schema agent outputs instead of the text protocols (`SUBAGENT:`, `DONE/FAILED`) — see `workflow.md` for the contract and reference script. This skill's instruction counts as the user's opt-in to workflow orchestration. Fall back to plain Agent calls when Workflow is unavailable. Orchestrator-only duties (TASKS.md updates, PRD moves, commits) always stay in the main loop.

**Auto-escalation:** Worker failure -> advisor-guided diagnosis and retry (see Mode 4, FAILED). Second failure -> mark BLOCKED in TASKS.md, ask user.

---

## Knowledge Persistence

- **Session learnings** (`prds/progress.md`) — Patterns discovered during execution, passed to each subagent via the "Patterns & Learnings" section
- **Permanent learnings** (`CLAUDE.md`) — Broadly useful patterns promoted from progress.md. Subagents report patterns as `PATTERN: [category] - [description]`. Orchestrator always adds to progress.md and offers CLAUDE.md promotion if broadly useful.
- **Manual review** (`norman learnings`) — Review all patterns, grouped by category, choose which to promote
