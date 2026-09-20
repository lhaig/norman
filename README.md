# Norman

Custom skills and agents for [Claude Code](https://claude.ai/code) and [OpenAI Codex](https://developers.openai.com/codex) that help with planning and executing software projects. The skills follow the open [Agent Skills](https://agentskills.io) format, so one copy serves both harnesses.

## What's in this repo

```
norman/       # The norman skill: SKILL.md router + references/ (one file per mode, classifier guide, workflow reference)
prd/          # Thin shim skill that forwards to norman's PRD mode
sweep/        # Post-implementation cleanup skill (mutation sweep, comment cleanup)
agents/       # Specialized subagent library, markdown source of truth
tools/        # codex-agents: converts agents/*.md into Codex custom-agent TOML
statusline/   # Terminal status bar script (Claude Code)
Makefile      # Installs into ~/.claude/ (Claude Code) and ~/.agents/skills + ~/.codex/agents (Codex)
```

## Installation

**Claude Code**

```bash
make install     # symlink skills, agents, and statusline into ~/.claude/
make status      # verify link state
make uninstall   # remove the symlinks (backups are left in place)
```

Existing real files/dirs at the destinations are backed up to a timestamped folder under `~/.claude/` before linking.

**Codex CLI**

```bash
make install-codex     # symlink skills into ~/.agents/skills/, generate ~/.codex/agents/*.toml
make status-codex      # verify links and generated agent count
make uninstall-codex   # remove the links and the generated TOML (hand-written agents are left alone)
```

Skills are discovered from `~/.agents/skills/` and invoked as `$norman`, `$sweep`, `$prd` (or implicitly by description). Agents are generated rather than linked because Codex reads TOML, not the markdown frontmatter format; `tools/codex-agents` does the conversion and needs a Go toolchain. Re-run `make install-codex` after editing anything in `agents/`. `~/.codex/AGENTS.md` is linked to `~/.claude/CLAUDE.md` so both harnesses read the same global rules; every generated agent is told to read `AGENTS.md` before starting, since Codex subagents do not inherit it.

Both installs can coexist. `SKILL.md` files stay under Codex's 8 KB skill-body limit; everything longer lives in `references/` and is read on demand.

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
- Execution runs as a schema-validated Workflow pipeline (classify -> advise -> implement -> review) on Claude Code, with plain subagent calls as the path on Codex
- Harness differences (how to spawn, continue, or ask; where agents and instruction files live) are resolved by one table in `norman/SKILL.md`; the mode references are written harness-neutral
- Parallel execution of independent tasks, with git worktree isolation when they might touch the same files
- Patterns discovered during execution are logged to `progress.md`, fed to later subagents, and can be promoted to `CLAUDE.md`

## The agents library

`agents/` is a development-focused library of specialist agents, all set to `model: inherit`. Norman's classifier picks the most specific agent for each task; `norman/references/subagents.md` is the curated guide it reads. All agents use `model: inherit`, so the agent type determines the specialist prompt while the caller (norman's worker model, or the session model outside norman) determines what it runs on.

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

- [Claude Code](https://claude.ai/code) CLI and/or [Codex CLI](https://developers.openai.com/codex)
- Go 1.26+ (only for `make install-codex`)
- `jq` (for the statusline)

## License

MIT License - see [LICENSE](LICENSE) for details.
