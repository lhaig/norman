# Modes 6-8: Prune, Reset, Upgrade

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
4. Trigger the sweep per `sweep_mode` (Mode 9), scoped to the collapsed phases — this is the same phase-collapse event as Step 6.3, so it gets the same treatment. Offer once for the whole batch, not per phase.
5. Commit with `chore: prune completed phases from TASKS.md`.

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

4. **Present the diff** — Show a grouped summary: additions (key, default, purpose), invalid values, unknowns. If there are no differences, report "config.md is already current" and exit. Otherwise ask the user:
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

This table is the source of truth for the diff. **Keep it in sync with the `config.md` template in `state.md`** whenever a new setting is introduced — the upgrade mode is only as complete as this list.

Project-specific keys (`name`, `repo`, `created` under Project; `build`, `test`, `lint` under Commands) are NOT defaulted — they're auto-detected or user-supplied. The upgrade mode reports them as missing if absent but does not invent values; it prompts the operator or re-runs auto-detection.

| Section | Key | Default | Allowed values |
|---------|-----|---------|----------------|
| Session Limits | `max_tasks_per_session` | `15` | positive integer |
| Session Limits | `warn_at_tasks` | `12` | positive integer `< max_tasks_per_session` |
| Subagent Defaults | `default_subagent` | `general-purpose` | any installed agent type |
| Model Strategy | `advisor_mode` | `always` | `always` \| `auto` \| `never` |
| Model Strategy | `advisor_model` | `opus` | `opus` \| any valid model |
| Model Strategy | `default_model` | `sonnet` | any valid model |
| Model Strategy | `quick_model` | `haiku` | any valid model |
| Model Strategy | `progress_compress_after` | `10` | positive integer |
| Model Strategy | `verify_rigor` | `single` | `single` \| `adversarial` |
| Cleanup | `sweep_mode` | `offer` | `off` \| `offer` \| `auto` |

