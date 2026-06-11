# Agents

Specialized subagent definitions for Claude Code, installed to `~/.claude/agents/` by the repo Makefile. Each file is one agent: YAML frontmatter (`name`, `description`, `model`) followed by its system prompt.

Originally imported from [wshobson/agents](https://github.com/wshobson/agents), this collection has since diverged:

- **All agents use `model: inherit`** — the agent type picks the specialist prompt; the caller picks the model (norman passes its worker model explicitly; outside norman the session model applies).
- **Pruned** agents superseded by the modern harness (web research, context management, prompt engineering, screenshot validation are covered by built-in tools and skills) and the non-development set (SEO, sales, support, HR, legal, marketing).
- **Added** custom agents: `serverpod-expert`, `htmx-alpine-pro`.

The curated selection guide — which agent fits which kind of task — lives in [`norman/subagents.md`](../norman/subagents.md), which the norman skill's classifier reads. Keep that file in sync when adding or removing agents here.

To list the installed agent names:

```bash
for f in *.md; do grep -m1 "^name:" "$f" | sed 's/name: *//'; done | sort
```

## License

The imported agents retain their original MIT license — see [LICENSE](LICENSE).
