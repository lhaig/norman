# Mode 4: Continue (Task Execution)

Start with: "continue norman", "run the norman", or just "norman"

### Step 0: Initialize Session

Read `prds/config.md`, initialize `session_tasks_completed = 0`, extract session limits.

**Migration:** If `prds/config.md` doesn't exist but `.norman/config.md` does, offer to migrate files from `.norman/` to `prds/`.

**Config drift check (passive):** After reading `prds/config.md`, do a lightweight diff of its keys against the canonical schema in Mode 8 (`maintenance.md`). If any canonical keys are missing or hold invalid values, print a single non-blocking notice — e.g. `config.md is missing 2 settings (verify_rigor, advisor_mode); run 'norman upgrade' to reconcile.` — then continue with the session using read-time defaults for the missing keys. This is advisory only: do NOT prompt, apply changes, or halt execution. Show it at most once per session.

### Step 1: Read State

Read `prds/TASKS.md` and `prds/progress.md`. Parse task statuses from the table: `DONE` = complete, `TODO` = pending, `ACTIVE` = in progress, `BLOCKED` = blocked.

**Progress compression:** If completed tasks exceed `progress_compress_after`, spawn a support-tier subagent (`quick_model`) to compress progress.md into ~100 lines of deduplicated patterns, key decisions, and last 3 full entries.

### Step 2: Find Next Task

**First run of a session (or when multiple phases have TODO items):**
Present a summary of ready tasks grouped by phase and ask the user which task or phase to start with (see "Asking the user" in SKILL.md), with options like:

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

### Steps 3-6 via Workflow (Claude Code only)

When the harness has a Workflow tool (Claude Code), run Steps 3 through 6.2 for the chosen tasks as ONE Workflow script instead of hand-orchestrating subagent calls. Read `workflow.md` (same directory as this file) for the args contract, output schemas, and reference script. This skill's instruction is the user's opt-in to workflow orchestration. On any other harness, skip this section and run the numbered steps directly.

Order of operations:
1. Orchestrator first runs Step 3.5 (gather project rules) and Step 4 (mark ACTIVE, move PRDs, read acceptance criteria) for EVERY task in the batch.
2. Launch the workflow with the batch. A batch is the ready tasks in the chosen phase with no dependencies between them — a batch of 1 is the normal sequential case. Set `isolate: true` for batches larger than 1 (workers get git worktrees).
3. The workflow pipelines each task through classify -> advisor plan review -> implement (tests-first, evidence-gated) -> advisor code review with one fix round. Every agent output is JSON-schema validated — no text parsing. The workflow never touches `prds/`, never commits, never asks the user.
4. The orchestrator processes the returned results per Step 6: commit DONE tasks (Step 6.3 — merging worktree diffs first when isolated, see workflow.md), advisor-guided recovery for FAILED, user questions for BLOCKED, mark twice-REJECTED tasks BLOCKED.

The numbered steps below are the spec for what each pipeline stage must do, and double as the direct execution path when Workflow is unavailable.

### Step 3: Classify and Prepare (support tier)

Spawn a support-tier subagent (`quick_model`) to classify each ready task. The classification guide is `subagents.md`, in the same directory as this file — resolve its absolute path first, then include that path in the spawn prompt so the classifier reads it explicitly:

> Read `[absolute path to subagents.md]` for the classification guide. Then verify the agent you choose exists by listing the harness's agent directory (`[agent directory from the SKILL.md harness table]`) or confirming it is a harness built-in. Do NOT return an agent name that is not present in either source.

The classifier should:
1. Read the classification guide at the path above
2. Search the codebase for relevant files (Glob/Grep)
3. Read the most relevant files (max 5)
4. Verify the chosen `subagent_type` is installed
5. Return: `SUBAGENT: [agent type]`, `FILES: [paths]`, `CONTEXT: [summary]`, `COMPLEXITY: [low|medium|high]`

Classify multiple ready tasks in parallel.

**Classification is advisory, never load-bearing.** It runs on the smallest model
(`quick_model`), so treat its output as a suggestion to be checked, not a decision to be
obeyed. The self-verification asked for above is necessary but NOT sufficient: validate the
returned `subagent_type` against the agents actually available before spawning anything, and
if the classification is missing, malformed, or names an agent that does not exist, fall
back to `general-purpose` (or the harness's default subagent role) and CONTINUE.

Never let a classification failure end the task. Doing so skips the implement stage and the
advisor review, and a worker that already began still leaves its work on disk -- unreviewed,
and looking finished. A slightly less specialised worker whose output gets reviewed beats a
perfect choice that never runs.

### Step 3.1: Advisor Plan Review

Advisor agents in this step (and Steps 6.2, FAILED recovery, and Mode 5) run on the model set by `advisor_model` in config.md.

**When `advisor_mode` is `always`:** Spawn an advisor agent for every task.
**When `advisor_mode` is `auto`:** Only spawn if the classifier rated the task `COMPLEXITY: high` or `medium`.
**When `advisor_mode` is `never`:** Skip this step entirely.

The advisor receives the task description, acceptance criteria, classified files, and context from Step 3. It returns:
- **APPROACH:** A concise implementation plan (which files to change, what pattern to follow, edge cases to handle)
- **RISKS:** Anything the worker should watch out for (breaking changes, concurrency, security)
- **SEQUENCE:** If multiple tasks are being planned, recommended execution order
- **VERDICT:** `PROCEED` or `REVISE` — if REVISE, include what needs changing in the task definition

If the advisor returns `REVISE`, update the task description in TASKS.md before spawning the worker. Log the advisor's guidance in progress.md.

The advisor's APPROACH and RISKS are passed directly to the worker in Step 5.

### Step 3.5: Gather Project Rules (Once Per Session)

**CRITICAL:** Subagents do NOT inherit the project instructions file on any harness. Before spawning any worker, read and cache:
1. The project instructions file (`CLAUDE.md` on Claude Code, `AGENTS.md` on Codex — tech stack rules, forbidden libraries, conventions)
2. The global instructions file (`~/.claude/CLAUDE.md` or `~/.codex/AGENTS.md` — user preferences)
3. Referenced context files (e.g., `context/tech-stack.md`)

Extract key rules into a `project_rules` block included in every subagent prompt.

### Step 4: Start Task — Update Status and Move PRD

Before spawning the worker:
1. Update the task row in `prds/TASKS.md`: status `TODO` → `ACTIVE`
2. If the PRD file is in `prds/backlog/`, move it to `prds/active/` using git mv
3. Update the PRD link in the TASKS.md row to point to `active/`
4. Read the PRD file for full acceptance criteria to pass to the worker

### Step 5: Spawn Worker Subagent

Spawn a subagent of the type chosen in Step 3 on the worker model (`default_model`) — see "Spawning subagents" in SKILL.md. The prompt MUST include:
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

Spawn multiple independent workers in parallel if multiple tasks are ready. If parallel tasks could touch overlapping files, give each worker its own git worktree (`isolation: worktree` on Claude Code; on Codex, where subagents share the cwd, create the worktree yourself and instruct the worker to run everything inside it) or serialize them — otherwise concurrent edits clobber each other.

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
`REJECT` — Do NOT commit. Send the reviewer's specific issues back to the SAME worker agent as fix instructions (continue it — it keeps the context it built while implementing). Re-spawn a fresh worker only if continuation isn't available on this harness. After the second attempt, run the reviewer again. If rejected twice, mark BLOCKED and ask the user.

**Step 6.3: Commit**

1. Move PRD from `prds/active/` to `prds/done/` using git mv
2. Update TASKS.md row: status -> `DONE (date)`, PRD link -> `done/`, add summary note
3. **Auto-collapse phase if fully DONE** — After updating the row, check whether every task in the current phase is now `DONE`. If so:
   - Append the full phase heading + table to `prds/TASKS-archive.md` (create file if missing)
   - Replace the phase block in TASKS.md with a one-line summary: `## Phase N: [Name] — X tasks completed YYYY-MM-DD (see [TASKS-archive.md](TASKS-archive.md))`
   - Skip if any task is `PARTIAL`, `BLOCKED`, `ACTIVE`, or `TODO`
4. Append to `prds/progress.md` (date, task, changes, patterns, advisor review result)
5. Commit with `feat([scope]): [description]` (include the archive update in the same commit if a phase was collapsed)
6. If subagent or advisor reported broadly useful patterns, offer to promote to the project instructions file
7. **If a phase was collapsed in step 3**, trigger the sweep per `sweep_mode` — see Mode 9. Both modes are in scope here: `sweep invariants` mutation-tests whether the suite actually guards what the phase promised, and `sweep comments` strips the now-stale `Phase N`/`FR-n`/`T-n.n` references the phase left in the code.

**FAILED — Advisor-Guided Recovery:**

Instead of retrying the whole task on the advisor model, use the advisor as a diagnostician:
1. Spawn an advisor agent with the failure context (error messages, partial changes, worker's report)
2. The advisor returns: `DIAGNOSIS` (what went wrong), `FIX_GUIDANCE` (specific instructions for the worker to retry)
3. Continue the SAME worker agent with the fix guidance — it already knows what it tried. Re-spawn fresh with the original task + fix guidance only if continuation isn't available.
4. If the guided retry also fails, mark BLOCKED in TASKS.md, log both failures, ask user: retry/skip/stop

**BLOCKED:** Present subagent's question to user, get answer, continue the same agent with the answer. Re-spawn with additional context only if continuation isn't available.

### Step 7: Continue

Increment `session_tasks_completed`. Check limits:
- At `warn_at_tasks`: show warning, continue
- At `max_tasks_per_session`: stop, report progress, recommend fresh session

Then: more tasks ready -> Step 2. Nothing ready but some pending -> report blockers. All done -> report completion, suggest `norman verify`.

Auto-continue until: task fails, all complete, user interrupts, subagent blocked, or session limit reached.
