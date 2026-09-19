# Mode 9: Sweep

Start with: "norman sweep", or reached automatically from a phase collapse (Mode 4 Step 6.3, Mode 6) and from Mode 5 step 6 (post-verify).

Hands off to the `sweep` skill, which does the actual work. This mode is only the norman-side wiring: when it fires, what it gets scoped to, and what happens to the findings.

### Who runs it

**The orchestrator, by invoking the `sweep` skill (Skill tool on Claude Code, `$sweep` on Codex). Never a worker.** Two independent reasons:

- Sweep's own non-negotiable forbids running a full suite from inside an agent — concurrent suites starve each other and produce false failures that read as real findings. The orchestrator is the only place with a guarantee that nothing else is running.
- Both modes need the whole-phase view. A worker holds one task; the stale `Phase N` comments and the untested invariants are spread across every task in the phase.

Do NOT add sweep instructions to the worker prompt in Step 5. A worker that sweeps its own task proves nothing — it wrote both the guard and the test.

### Gating

Read `sweep_mode` from `prds/config.md`. If the key is absent (a project set up before this option existed), treat it as `offer`.

| Value | Behaviour when a trigger fires |
|-------|--------------------------------|
| `off` | Do nothing. Do not mention it. |
| `offer` | Ask the user once: run it now / skip / turn off for this project. On "turn off", write `sweep_mode: off` to config.md and commit with the sweep. |
| `auto` | Invoke the skill immediately, no prompt. |

`offer` is the default because both modes are slow and token-heavy — an unprompted mutation sweep mid-session can consume the rest of the task budget. Under `auto`, count the sweep against `max_tasks_per_session` as one task, so it cannot silently overrun the session limit.

An explicit `norman sweep` runs regardless of `sweep_mode`, including `off`. The setting gates the automatic triggers, not the command.

### Scope

Pass the skill an explicit scope — left unscoped it sweeps the whole codebase, which is rarely what the trigger meant.

| Trigger | Modes | Scope |
|---------|-------|-------|
| Phase collapse (Step 6.3, Mode 6) | invariants + comments | Files touched by the tasks in the collapsed phase (from their progress.md entries), and the `Phase N`/`T-N.n`/`FR-n` identifiers that phase used |
| Post-verify (Mode 5 step 6) | invariants only | The invariants behind requirements that verified `PASS` |
| `norman sweep` | ask which | Last collapsed phase by default; user may name a phase or path |

For the comments mode, the phase's own identifiers are the highest-value target: they became stale the moment the phase was archived into `TASKS-archive.md`, and no other trigger will ever revisit them.

### Findings

Sweep findings are coverage gaps, not bugs, and the sweep does not fix them. Norman's job is to make sure they do not evaporate:

1. Append the findings to `prds/progress.md` under the phase or verification they came from.
2. Offer to turn accepted gaps into tasks — a new phase in `prds/TASKS.md` with PRDs in `prds/backlog/`, same shape as Mode 5 step 7. Which gaps are worth a test is a priority call and belongs to the user.
3. The comments mode rewrites in place and does not commit. Review the diff, then fold it into the phase-collapse commit from Step 6.3 rather than committing separately.

If a sweep produces a behaviour change, that is a bug in the sweep. Revert it and report — do not commit it and do not open a task for it.
