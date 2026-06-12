# Norman Subagent Reference

This file is read by the Haiku classifier during Step 3 of Mode 4 (Continue).
The orchestrator does NOT need this in its main context.

**Source of truth:** Available agents live in `~/.claude/agents/` (the installed count drifts — regenerate the list with the command below rather than trusting any number written here). This file is a curated guide over that directory — if you add or remove an agent there, update the tables below. Haiku is instructed to verify the chosen `subagent_type` against the directory before returning a classification.

To regenerate an authoritative list of installed agent names:
```
for f in ~/.claude/agents/*.md; do grep -m1 "^name:" "$f" | sed 's/name: *//'; done | sort -u
```

**Built-in agents** (always available, not files): `general-purpose`, `Explore`, `Plan`, `claude`, `statusline-setup`, `claude-code-guide`.

---

## Advisor Pattern

Norman uses a three-tier advisor model:

| Role | Model | Purpose |
|------|-------|---------|
| **Advisor** | `advisor_model` (opus default; fable where available) | Reviews plans before execution, reviews completed code, diagnoses failures |
| **Worker** | `default_model` (sonnet) | Implements all tasks (never the advisor model) |
| **Support** | `quick_model` (haiku) | Classifies tasks, gathers context, compresses progress |

Workers stay on the worker model. The advisor handles quality control through plan review (Step 3.1) and code review (Step 6.2). This separation means the strongest model spends tokens on reasoning about approach and quality rather than writing boilerplate. Note: all agent files in `~/.claude/agents/` use `model: inherit` in their frontmatter, so norman's explicit model parameter on the Agent tool (or the session model, outside norman) determines what they run on.

---

## Available Agent Types

### Language Specialists
Use when the task is primarily in one language.

| Language | subagent_type |
|----------|---------------|
| C / embedded | `c-pro` |
| C++ | `cpp-pro` |
| C# | `csharp-pro` |
| Elixir | `elixir-pro` |
| Go | `golang-pro` |
| Java | `java-pro` |
| JavaScript | `javascript-pro` |
| PHP | `php-pro` |
| Python | `python-pro` |
| Ruby / Rails | `ruby-pro` |
| Rust | `rust-pro` |
| Scala | `scala-pro` |
| SQL | `sql-pro` |
| TypeScript | `typescript-pro` |

### Framework / Platform Specialists
Use when the task targets a specific framework or platform.

| Framework / Platform | subagent_type |
|----------------------|---------------|
| Flutter / Dart | `flutter-expert` |
| Frontend (React / responsive UI) | `frontend-developer` |
| Godot 4 | `godot-developer` |
| GraphQL APIs | `graphql-architect` |
| htmx / Alpine.js frontends | `htmx-alpine-pro` |
| iOS native | `ios-developer` |
| Minecraft / Bukkit plugins | `minecraft-bukkit-pro` |
| Mobile (React Native / cross-platform) | `mobile-developer` |
| Serverpod | `serverpod-expert` |
| Unity | `unity-developer` |

### Infrastructure / DevOps Specialists

| Domain | subagent_type |
|--------|---------------|
| Cloud architecture (general) | `cloud-architect` |
| Hybrid cloud | `hybrid-cloud-architect` |
| Kubernetes architecture | `kubernetes-architect` |
| CI/CD / Docker / deployment | `deployment-engineer` |
| DevOps troubleshooting | `devops-troubleshooter` |
| Incident response | `incident-responder` |
| Network engineering | `network-engineer` |
| Terraform / IaC | `terraform-specialist` |

### Code Domain Specialists
Use when the task domain matters more than the language.

| Domain | subagent_type |
|--------|---------------|
| API design | `backend-architect` |
| Architecture review | `architect-reviewer` |
| Code review | `code-reviewer` |
| Database operations / migrations | `database-admin` |
| Database query optimization | `database-optimizer` |
| Debugging non-obvious issues | `debugger` |
| Developer experience tooling | `dx-optimizer` |
| Error / log analysis | `error-detective` |
| Legacy refactoring / modernization | `legacy-modernizer` |
| Payments / billing | `payment-integration` |
| Performance / profiling | `performance-engineer` |
| Security / auth | `security-auditor` |
| Testing | `test-automator` |
| UI / UX design | `ui-ux-designer` |

### Data / AI Specialists

| Domain | subagent_type |
|--------|---------------|
| AI feature engineering | `ai-engineer` |
| Data engineering / pipelines | `data-engineer` |
| Data science / analytics | `data-scientist` |
| ML model training | `ml-engineer` |
| MLOps | `mlops-engineer` |

### Documentation Specialists

| Domain | subagent_type |
|--------|---------------|
| API documentation | `api-documenter` |
| Long-form technical docs | `docs-architect` |
| Mermaid diagrams | `mermaid-expert` |
| Reference material | `reference-builder` |
| Tutorials / guides | `tutorial-engineer` |

### General Purpose / Built-in

| Use case | subagent_type |
|----------|---------------|
| No specialist match | `general-purpose` |
| Context gathering / classification (Haiku) | `general-purpose` |
| Read-only codebase search | `Explore` |
| Implementation planning | `Plan` |

---

## Classification Guide

### Complexity Classification

The classifier returns a `COMPLEXITY` level used to decide whether the Opus advisor reviews the task (in `auto` mode):

Return **high** if ANY of these apply:
- Task involves security (auth, encryption, tokens, permissions, input validation)
- Task requires designing new architecture or significant refactoring across 5+ files
- Task involves complex algorithms, concurrency, or race conditions
- Task requires debugging a non-obvious issue
- Task modifies core infrastructure (database schemas, middleware, CI/CD)
- Task involves payment processing or financial logic
- Task is a performance investigation requiring profiling and tradeoff analysis
- Task is an active incident or production outage

Return **medium** if ANY of these apply:
- Task touches 3-4 files
- Task involves non-trivial business logic
- Task has integration points with external services
- Task modifies shared utilities or common code

Otherwise return **low**.

In `always` mode, the advisor reviews every task regardless of complexity. In `never` mode, the advisor is skipped entirely.

### Agent Selection

Pick the **most specific** agent that matches:
1. If the task is clearly in one language and that's the main challenge → language specialist
2. If the task targets a specific framework / platform → framework specialist
3. If the task is infra/DevOps → infrastructure specialist
4. If the task domain dominates the language (writing tests, security audit, perf work) → domain specialist
5. If the task is data/AI/ML → data/AI specialist
6. If the task is documentation → documentation specialist
7. If nothing fits well → `general-purpose`

All workers run on Sonnet. The agent type determines the specialist prompt, not the model. The Opus advisor (Step 3.1, Step 6.2) handles complexity-based quality review separately — see Complexity Classification above.

### Verification Step (required)

Before returning a classification, verify the chosen `subagent_type` exists:
- It must be either a built-in (listed above), OR
- An agent with that `name:` in `~/.claude/agents/` (run the regeneration command above if unsure)

If the agent does not exist, fall back to `general-purpose` and note the missing agent in your `CONTEXT` field so the orchestrator can flag it.
