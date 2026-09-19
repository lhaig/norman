# Agents

Specialized subagent definitions. Each file is one agent: YAML frontmatter (`name`, `description`, `model`) followed by its system prompt. `make install` symlinks the directory to `~/.claude/agents/` for Claude Code; `make install-codex` converts each file to a Codex custom agent at `~/.codex/agents/<name>.toml` via `tools/codex-agents` (the markdown here stays the single source of truth).

Conventions:

- **All agents use `model: inherit`** — the agent type picks the specialist prompt; the caller picks the model (norman passes its worker model explicitly; outside norman the session model applies).
- **Development-focused only** — no agents for work the harness already covers (web research, context management, prompt engineering, screenshot validation) and none for non-development domains (SEO, sales, support, HR, legal, marketing).
- **Short-form prompts** — focus areas, approach, output, and where the ecosystem moves fast, a modern-patterns and deprecated list pinned to versions (see `golang-pro.md` for the shape).

The curated selection guide — which agent fits which kind of task — lives in [`norman/references/subagents.md`](../norman/references/subagents.md), which the norman skill's classifier reads. Keep that file in sync when adding or removing agents here.

To list the installed agent names:

```bash
for f in *.md; do grep -m1 "^name:" "$f" | sed 's/name: *//'; done | sort
```

## License

MIT — see [LICENSE](LICENSE).
