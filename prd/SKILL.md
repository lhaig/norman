---
name: prd
description: "Generate a Product Requirements Document (PRD) for a new feature. Use when planning a feature, starting a new project, or when asked to create a PRD. Triggers on: create a prd, write prd for, plan this feature, requirements for, spec out."
---

# PRD Generator

**This skill is now part of Norman.** Use `norman prd` for the full workflow.

When triggered, execute Mode 1 (PRD) from the norman skill. The behavior is identical:

1. Ask 3-5 clarifying questions with lettered options
2. Generate a structured PRD
3. Save to `prds/research/prd-[feature-name].md`
4. Tell the user to run `norman import` when ready to extract tasks

Refer to the norman skill's Mode 1 reference (`references/prd.md` in the norman skill directory — `~/.claude/skills/norman/` on Claude Code, `~/.agents/skills/norman/` on Codex) for the full specification.
