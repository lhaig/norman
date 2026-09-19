# Mode 2: Plan and Mode 3: Import

## Mode 2: Plan (Interactive Planning)

Start with: "norman plan" or "plan a norman"

### Phase 1: Discovery

Ask the user questions to understand scope, with structured options (see "Asking the user" in SKILL.md):

- **What are you building?** (new feature / refactor / bug fix / migration)
- **What's the scope?** (single file / multiple files / cross-cutting / full module)
- **What areas of the codebase?** (explore to identify, ask to confirm)
- **Existing patterns to follow?** (search for similar implementations)
- **Constraints?** (backward compat, performance, external deps)

Keep asking until you have enough detail to break into concrete tasks.

### Phase 2: Task Breakdown

Break into logical units, sequence by dependencies, size each task for one focused session. Present for review:

```
Phase 1: Foundation (3 tasks)
1. [Task] - [why it's first]
2. [Task] (needs: 1)
3. [Task] (needs: 1)

Phase 2: Core (4 tasks)
4. [Task] (needs: 2, 3)
...

Does this look right? Any tasks to add, remove, or reorder?
```

### Phase 3: Generate Files

Once approved:
1. Create `prds/` directory structure if it doesn't exist (research/, backlog/, active/, done/)
2. Add tasks to `prds/TASKS.md` (create if needed, append to existing if present)
3. Create `prds/config.md` (auto-detect project commands from package.json/Makefile/pyproject.toml/go.mod)
4. Create `prds/progress.md`
5. Commit with `chore: initialize norman for [project name]`

---

## Mode 3: Import (From Research PRD)

Start with: "norman import [path]" or "norman import"

### Process

1. **Find the document** — If no path provided, look in `prds/research/` for PRD files. List them and ask which to import. If a path is given, use that directly.
2. **Read and review** — Show a summary of the PRD: goals, user stories count, functional requirements count.
3. **Extract tasks** — Parse user stories (US-001), functional requirements (FR-1), and acceptance criteria. Transform each into a task.
4. **Analyze dependencies** — Order by explicit deps, logical sequence (schema > API > UI), and cross-references.
5. **Present for review** — Show extracted tasks grouped by phase, list excluded non-goals.
6. **Move PRD** — Move from `prds/research/` to `prds/backlog/` using git mv.
7. **Update TASKS.md** — Add tasks to `prds/TASKS.md` in the appropriate phase with links to the backlog PRD.
8. **Create execution files** — Create `prds/config.md` and `prds/progress.md` if they don't exist. Auto-detect project commands.

