# Mode 5: Verify

Start with: "norman verify"

### Process

1. **Locate requirements** — Read `prds/TASKS.md`, find DONE tasks with PRD links in `prds/done/`. If verifying a specific PRD, ask user which one.

2. **Extract requirements (support tier)** — Parse the PRD(s) into a structured checklist: user stories with acceptance criteria, functional requirements, non-functional requirements, explicit constraints. Skip non-goals.

3. **Verify each requirement (advisor model)** — Verification is inherently an advisory task; verifiers run on `advisor_model`. Depth is controlled by `verify_rigor` in config.md (if the key is absent — e.g. a project set up before this option existed — treat it as `single`):

   - **`single` (default)** — One verifier per requirement. For each: search the codebase for the implementation, read the code, check acceptance criteria, run the relevant tests. Report `PASS`, `FAIL`, or `PARTIAL` with evidence.
   - **`adversarial`** — Two to three verifiers per requirement, each with a distinct lens (implementation-exists / tests-actually-exercise-it / edge-cases-and-constraints). Combine by majority: `PASS` only if a majority vote PASS; `FAIL` if a majority vote FAIL; otherwise `PARTIAL`. This catches confident-but-wrong single verdicts on the requirements where a false PASS is most costly.

   On Claude Code (Workflow tool available), run this step as a workflow pipeline (one branch per requirement) with JSON-schema-validated verdicts instead of parsing free text — see `workflow.md`.

4. **Completeness critic (adversarial only)** — After per-requirement verdicts, spawn one advisor-model critic over the full checklist and the DONE task list. It hunts for what a per-requirement sweep structurally cannot see: acceptance criteria that no test actually exercises, requirements with no corresponding implementation, anything claimed DONE without evidence. Fold each gap it returns into the results by downgrading the affected requirement to `PARTIAL` or `FAIL`. Skipped when `verify_rigor` is `single`.

5. **Present results** — Show pass/partial/fail counts and details.

6. **Sweep invariants** — Trigger per `sweep_mode` (see Mode 9), `invariants` mode only. Comments are not in scope here: verify says nothing about comment staleness, and a phase collapse already covers that.

   This is the step that turns a `PASS` verdict into evidence. Step 3 verifiers check that a test exists and is green for each requirement; the mutation sweep checks whether that test would go red if the guarantee were broken. A requirement whose test survives its own invariant being broken is a false `PASS` — downgrade it to `PARTIAL` and carry it into step 7 as a gap. Scope the sweep to the invariants behind requirements that passed, not the whole codebase.

7. **Handle gaps** — Offer the user:
   - **Create tasks for gaps** — Add fix tasks to `prds/TASKS.md` as a new phase, create PRDs in `prds/backlog/`, continue norman
   - **Accept as-is** — Log results, update TASKS.md notes
   - **Re-verify specific items** — Re-check individual requirements after manual fixes

Save verification report to `prds/verification.md` and commit.
