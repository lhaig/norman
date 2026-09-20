---
name: norman
description: "Autonomous project execution with crash recovery. Triggers on: norman, start norman, continue norman, run the norman, set up project, resume project, norman plan, norman import, norman verify, norman upgrade, norman sweep, norman prd, create a prd, write prd for, plan this feature, requirements for, spec out."
---

# Norman - Project Execution

Plan, research, execute, and verify projects with crash recovery and session persistence.

## How this skill is organised

This file is the router: it holds the architecture, the mode table, and the rules that apply in every mode. Each mode's full procedure lives in `references/` next to this file. **Before running a mode, read its reference file** (resolve the absolute path from this file's directory). Read only the file for the mode you are running.

| Mode | Trigger | Reference |
|------|---------|-----------|
| 1 PRD | `norman prd`, create a prd, spec out | `references/prd.md` |
| 2 Plan | `norman plan` | `references/plan.md` |
| 3 Import | `norman import [path]` | `references/plan.md` |
| 4 Continue | `norman`, `continue norman` | `references/continue.md` |
| 5 Verify | `norman verify` | `references/verify.md` |
| 6 Prune / 7 Reset / 8 Upgrade | `norman prune|reset|upgrade` | `references/maintenance.md` |
| 9 Sweep | `norman sweep`, or auto after a phase collapse | `references/sweep.md` |

Also in `references/`: `state.md` (formats of every file under `prds/` — read before creating or editing one), `subagents.md` (agent classification guide, read by the classifier), `workflow.md` (Claude Code Workflow-tool pipeline, ignore on other harnesses).

Recommended lifecycle: `norman prd` -> `norman import` -> `continue norman` -> `norman verify`. Smaller features: `norman plan` -> `continue norman`.

## Architecture

All state lives in files under `prds/` at the project root, and every completed task ends in a git commit, so a session can be killed at any point and resumed with `continue norman`.

```
prds/
  TASKS.md           # Master task list — single source of truth for ACTIVE/TODO/BLOCKED
  TASKS-archive.md   # Fully-DONE phases, collapsed out of TASKS.md
  config.md          # Session limits, project commands, model strategy
  progress.md        # Append-only execution log (crash recovery, patterns)
  verification.md    # Output of norman verify
  research/ backlog/ active/ done/   # PRD lifecycle folders
```

**Roles.** The main agent is the orchestrator: it reads state, spawns subagents, updates `prds/`, and commits. Every task runs in a fresh subagent. Workers implement and report; they never commit and never modify `prds/`.

**Model tiers** (roles fixed, models set in `config.md`):
- **Advisor** (`advisor_model`) — reviews plans before execution, reviews code after, diagnoses failures.
- **Worker** (`default_model`) — implements every task.
- **Support** (`quick_model`) — classifies tasks, gathers context, compresses progress.

**Non-negotiables, every mode:**
- Task status lives ONLY in `prds/TASKS.md` and `prds/TASKS-archive.md`.
- Workers write a failing test for the acceptance criteria before implementing. A DONE report without test file paths and passing test output is treated as FAILED.
- Subagents do not inherit the project instructions file. The orchestrator reads it once and injects the rules into every subagent prompt.
- Classification is advisory. A bad or missing classification falls back to the default agent and continues; it never ends a task.
- Sweep runs from the orchestrator, never from a worker.

## Harness mapping

Norman runs on Claude Code and on OpenAI Codex. The references use harness-neutral wording; this table resolves it.

| Concept | Claude Code | Codex CLI |
|---------|-------------|-----------|
| Spawning subagents | `Agent` tool with `subagent_type` and `model` | `spawn_agent` with `agent_type` set to the agent name and `reasoning_effort` set per tier (below), then `wait_agent`; if the role is missing, use `default` with the agent file's instructions in the prompt |
| Continuing a subagent | `SendMessage` to the same agent | `followup_task` to the same agent |
| Asking the user | `AskUserQuestion` with options | numbered options in plain text, wait for the reply |
| Agent directory | `~/.claude/agents/*.md` | `~/.codex/agents/*.toml` |
| Default agent | `general-purpose` | `default` |
| Project instructions file | `CLAUDE.md`, global `~/.claude/CLAUDE.md` | `AGENTS.md`, global `~/.codex/AGENTS.md` |
| Model tiers | `opus` / `sonnet` / `haiku` | `reasoning_effort` `high` (advisor) / `medium` (worker) / `low` (support) on every spawn — the session default is often `low`, so always pass it; add `model` only if `config.md` names Codex model ids |
| Worktree isolation | `isolation: worktree` on spawn | subagents share the cwd — `git worktree add` a checkout and instruct the worker to run everything inside it, or serialize overlapping tasks |
| Workflow pipeline | Workflow tool (see `workflow.md`) | not available — run the numbered steps directly |
| Invoking the sweep skill | `Skill` tool | `$sweep` |

If `config.md` names a model the current harness does not offer, use the tier mapping above instead of failing.

## Commands

| Command | Action |
|---------|--------|
| `norman` / `continue norman` | Execute next task(s) |
| `norman prd` / `plan` / `import [path]` | Requirements, planning, task extraction |
| `norman status` | Progress summary from TASKS.md |
| `norman task [N]` / `skip [N]` / `add [desc]` / `pause` | Task control |
| `norman verify` / `prune` / `sweep` / `upgrade` / `reset` | Validation and maintenance |
| `norman learnings` | Review patterns in progress.md, promote to the project instructions file |

## Recovery

- **Session crashed** — say `continue norman`; state is in `prds/`.
- **Task partially complete** — check `git status`; commit partial progress or `git checkout .` and retry.
- **Wrong task executed** — revert the commit, set the row back to TODO, move the PRD back, continue.
- **Subagent failed or timed out** — inspect changes, commit or reset, mark BLOCKED, continue or retry.
- **TASKS.md out of sync with PRD folders** — trust the file system, fix the links.
- **Context getting long** — session limits in `config.md` are a cost checkpoint; a fresh session is always safe.

## Knowledge persistence

Subagents report `PATTERN: [category] - [description]`. The orchestrator always appends these to `progress.md`, feeds relevant ones to later subagents, and offers to promote broadly useful ones to the project instructions file.
