# Norman

Custom skills and agents for [Claude Code](https://claude.ai/code) that help with planning and executing software projects.

## What's in this repo

```
norman/       # The norman skill (SKILL.md + subagents.md classifier guide + workflow.md execution reference)
prd/          # Thin shim skill that forwards to norman's PRD mode
agents/       # Specialized subagent library (wshobson/agents + custom additions)
statusline/   # Terminal status bar script
Makefile      # Symlinks everything into ~/.claude/
```

## Installation

```bash
make install     # symlink skills, agents, and statusline into ~/.claude/
make status      # verify link state
make uninstall   # remove the symlinks (backups are left in place)
```

Existing real files/dirs at the destinations are backed up to a timestamped folder under `~/.claude/` before linking.

## The norman skill

Executes projects with crash recovery and session persistence. The main agent orchestrates; every task runs in an isolated subagent with fresh context. An advisor-tier model reviews plans before execution and code after it; a worker-tier model implements; a fast model classifies and compresses.

**Modes:**

| Command | Action |
|---------|--------|
| `norman prd` | Generate a requirements document in `prds/research/` |
| `norman plan` | Interactive planning session, no PRD needed |
| `norman import [path]` | Review a PRD, move it to backlog, extract tasks |
| `norman` / `continue norman` | Execute tasks via subagents until done or stopped |
| `norman verify` | Validate the implementation against the PRD |
| `norman prune` | Collapse fully-done phases into the task archive |
| `norman reset` | Clear execution state and start fresh |

**Recommended workflow:**

```
norman prd        # create requirements (full lifecycle)
norman import     # extract tasks
continue norman   # execute
norman verify     # validate

norman plan       # or skip the PRD for smaller features
continue norman
```

**State lives in `prds/` at the project root:**

```
prds/
  TASKS.md           # Master task list — single source of truth
  TASKS-archive.md   # Completed phases, collapsed out of TASKS.md
  config.md          # Session limits, project commands, model strategy
  progress.md        # Append-only execution log (crash recovery)
  verification.md    # Verification results
  research/          # PRDs being drafted
  backlog/           # PRDs ready for implementation
  active/            # PRDs being worked on
  done/              # Completed PRDs
```

Because all state is in files and every task ends in a git commit, you can kill the session at any point and say `continue norman` later — including from a brand-new session.

**Key behaviors:**

- Tests-first: workers must write a failing test for the acceptance criteria before implementing, and DONE reports without test evidence are rejected
- Advisor gates: plan review before each task, code review after, failure diagnosis on errors (configurable via `advisor_mode`: always / auto / never)
- Execution runs as a schema-validated Workflow pipeline (classify -> advise -> implement -> review) on harnesses that support it, with plain agent calls as the fallback
- Parallel execution of independent tasks, with git worktree isolation when they might touch the same files
- Patterns discovered during execution are logged to `progress.md`, fed to later subagents, and can be promoted to `CLAUDE.md`

## The agents library

`agents/` is a pruned fork of the [wshobson/agents](https://github.com/wshobson/agents) collection (development-relevant agents only, all set to `model: inherit`) plus custom additions (`serverpod-expert`, `htmx-alpine-pro`). Norman's classifier picks the most specific agent for each task; `norman/subagents.md` is the curated guide it reads. All agents use `model: inherit`, so the agent type determines the specialist prompt while the caller (norman's worker model, or the session model outside norman) determines what it runs on.

## Statusline

A status bar showing model, context usage, cost, project, and git branch:

```
[Opus] [####------] 42% | $0.35 | myproject | main
```

Installed by `make install`, or manually:

```bash
cp statusline/statusline.sh ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
```

Then add to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh"
  }
}
```

See [statusline/README.md](statusline/README.md) for details.

## Requirements

- [Claude Code](https://claude.ai/code) CLI
- `jq` (for the statusline)

## License

MIT License - see [LICENSE](LICENSE) for details.
