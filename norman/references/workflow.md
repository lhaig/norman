# Norman Workflow Execution Reference

**Claude Code only.** Read by the orchestrator when running Mode 4 (Continue) Steps 3-6 through the Workflow tool. Not needed when falling back to plain subagent calls, and not applicable on harnesses without a Workflow tool (Codex) — those run the numbered steps in `continue.md` directly.

## Contract

The orchestrator prepares everything BEFORE launching the workflow, passes it via `args`, and does all `prds/` updates and commits AFTER it returns. The workflow never touches `prds/`, never commits, and never asks the user anything — blocked tasks come back as results.

**args shape:**

```json
{
  "subagentsGuidePath": "/abs/path/to/subagents.md",
  "advisorMode": "always",
  "advisorModel": "opus",
  "workerModel": "sonnet",
  "quickModel": "haiku",
  "isolate": false,
  "knownSubagents": ["golang-pro", "general-purpose", "..."],
  "projectRules": "extracted CLAUDE.md rules (Step 3.5)",
  "patterns": "relevant PATTERN lines from progress.md",
  "commands": { "build": "...", "test": "...", "lint": "..." },
  "tasks": [
    { "id": "3.1", "description": "...", "acceptanceCriteria": "from the PRD", "spike": false }
  ]
}
```

**Always normalise `args` at the top of the script.** Depending on the harness it arrives either as an object or as a JSON-encoded string; the scripts below open with `const A = typeof args === 'string' ? JSON.parse(args) : args` and then use `A` throughout. Skipping this is a hard failure at the first `pipeline()`/`parallel()` call — `A.tasks` is `undefined`, so the workflow dies before any agent runs.

Set `isolate: true` whenever `tasks.length > 1` — workers then run in git worktrees so parallel edits cannot collide. A batch of 1 runs directly in the working tree.

`knownSubagents` is the list of agent types actually available in this session (the orchestrator has it; the Agent tool description enumerates them). The script validates the classifier's choice against it and falls back to `general-purpose` on a miss. **Pass it.** Omitting it skips validation, which is how a nonexistent agent type reached `agentType` and killed a run. Classification runs on the smallest model and is the one stage that fails in practice — so its output is checked in code rather than trusted, and a failure there now costs a slightly less specialised worker instead of the whole task.

If the right specialist is obvious for the repo (in a single-language codebase it usually is, and the classifier will return the same one every time), consider skipping the stage entirely: pass the agent type in `args` and drop stage 1. That removes the failure mode rather than absorbing it, and saves an agent per task.

## Reference script

Adapt prompts as needed; the numbered steps in SKILL.md Mode 4 are the spec for what each stage must do.

```js
export const meta = {
  name: 'norman-continue',
  description: 'Norman task batch: classify, advise, implement, review',
  phases: [
    { title: 'Classify', detail: 'pick specialist agent per task' },
    { title: 'Advise', detail: 'advisor plan review' },
    { title: 'Implement', detail: 'worker per task, tests first' },
    { title: 'Review', detail: 'advisor code review + one fix round' },
  ],
}

// REQUIRED: `args` arrives as a JSON-encoded STRING on some harnesses, as an
// object on others. Normalise once, then use `A` everywhere instead of `args`.
// Without this, `args.tasks` is undefined and pipeline() throws
// "expects an array as the first argument" before a single agent runs.
const A = typeof args === 'string' ? JSON.parse(args) : args

const CLASSIFY = {
  type: 'object',
  required: ['subagent', 'files', 'context', 'complexity'],
  properties: {
    subagent: { type: 'string' },
    files: { type: 'array', items: { type: 'string' } },
    context: { type: 'string' },
    complexity: { enum: ['low', 'medium', 'high'] },
  },
}

const PLAN = {
  type: 'object',
  required: ['approach', 'risks', 'verdict'],
  properties: {
    approach: { type: 'string' },
    risks: { type: 'string' },
    verdict: { enum: ['PROCEED', 'REVISE'] },
    revision: { type: 'string' },
  },
}

const WORK = {
  type: 'object',
  required: ['status', 'filesChanged', 'summary', 'workdir'],
  properties: {
    status: { enum: ['DONE', 'FAILED', 'BLOCKED'] },
    filesChanged: { type: 'array', items: { type: 'string' } },
    summary: { type: 'string' },
    workdir: { type: 'string' },
    testFiles: { type: 'array', items: { type: 'string' } },
    testOutput: { type: 'string' },
    patterns: { type: 'array', items: { type: 'string' } },
    question: { type: 'string' },
  },
}

const REVIEW = {
  type: 'object',
  required: ['quality', 'issues'],
  properties: {
    quality: { enum: ['PASS', 'MINOR', 'REJECT'] },
    issues: {
      type: 'array',
      items: {
        type: 'object',
        required: ['file', 'description'],
        properties: { file: { type: 'string' }, description: { type: 'string' } },
      },
    },
    patterns: { type: 'array', items: { type: 'string' } },
  },
}

const needsAdvisor = (complexity) =>
  A.advisorMode === 'always' || (A.advisorMode === 'auto' && complexity !== 'low')

// Classification runs on the SMALLEST model (quick_model, default haiku) and is
// the cheapest decision in the pipeline -- but everything downstream used to hang
// on it unconditionally: which specialist runs, and whether the task runs at all.
// That is an inverted risk profile, and in practice this is the only stage that
// ever fails (a returned agent name that does not exist; a subagent that finishes
// without emitting the schema). Both are now absorbed here rather than ending the
// task.
//
// Step 3 of SKILL.md asks the classifier to verify its own choice against
// `ls ~/.claude/agents/`. That instruction stays, but it is no longer TRUSTED:
// asking the weakest model to self-certify and then using the answer unchecked is
// what let a nonexistent agent type through. Validate deterministically instead --
// it costs nothing and cannot fail.
const FALLBACK_SUBAGENT = 'general-purpose'

const safeClassification = (cls, task) => {
  if (!cls || !cls.subagent) {
    log(`task ${task.id}: no usable classification, falling back to ${FALLBACK_SUBAGENT}`)
    return { subagent: FALLBACK_SUBAGENT, files: [], context: '', complexity: 'high' }
  }
  if (!A.knownSubagents || A.knownSubagents.includes(cls.subagent)) return cls
  log(`task ${task.id}: classifier returned unknown agent "${cls.subagent}", falling back to ${FALLBACK_SUBAGENT}`)
  return { ...cls, subagent: FALLBACK_SUBAGENT }
}

const workerPrompt = (task, cls, plan, extra) => `
You are implementing one task for the norman orchestrator. Your final output is parsed as structured data, not shown to a human.

PROJECT RULES (non-negotiable):
${A.projectRules}

TASK ${task.id}: ${task.description}

ACCEPTANCE CRITERIA:
${task.acceptanceCriteria}

${plan ? `ADVISOR GUIDANCE (follow this approach):\n${plan.approach}\nRISKS: ${plan.risks}\n${plan.verdict === 'REVISE' ? 'REVISED TASK DEFINITION: ' + plan.revision : ''}` : ''}

RELEVANT FILES: ${cls.files.join(', ')}
CONTEXT: ${cls.context}

PATTERNS FROM EARLIER TASKS:
${A.patterns}

COMMANDS: build: ${A.commands.build} | test: ${A.commands.test} | lint: ${A.commands.lint}

${task.spike
  ? 'This is a (spike) task: prototype first, tests come in a follow-up task.'
  : 'TESTS FIRST: write a failing test encoding the acceptance criteria BEFORE implementation, then implement until green. A DONE report without testFiles and passing testOutput will be rejected.'}

Do NOT commit. Do NOT modify anything under prds/. Report workdir as the absolute path of the repo root you worked in (run pwd).
${extra || ''}`

const results = await pipeline(
  A.tasks,

  // Stage 1: classify (Step 3). NON-FATAL: a classification failure must not cost
  // the task its implement stage and -- more importantly -- its advisor review.
  // Dropping the item here is the worst outcome available, because a worker that
  // already did the work still leaves it on disk, unreviewed and looking finished.
  //
  // The acceptance criteria are deliberately NOT sent: picking an agent needs the
  // shape of the task, not its test plan, and a long implementer brief invites the
  // classifier to start implementing instead of classifying.
  async (task) => {
    let cls = null
    try {
      cls = await agent(
        `Read ${A.subagentsGuidePath} for the classification guide. Search the codebase for files relevant to this task (read at most 5), verify the chosen subagent exists per the guide, and return the classification.\n\nTASK ${task.id}: ${task.description}`,
        { model: A.quickModel, phase: 'Classify', label: `classify:${task.id}`, schema: CLASSIFY }
      )
    } catch (e) {
      log(`task ${task.id}: classify stage errored (${e && e.message ? e.message : e})`)
    }
    return safeClassification(cls, task)
  },

  // Stage 2: advisor plan review (Step 3.1)
  async (cls, task) => {
    if (!cls) return null
    let plan = null
    if (needsAdvisor(cls.complexity)) {
      plan = await agent(
        `You are the norman advisor reviewing a task plan before a worker implements it.\n\nTASK ${task.id}: ${task.description}\n\nACCEPTANCE CRITERIA:\n${task.acceptanceCriteria}\n\nCLASSIFIED FILES: ${cls.files.join(', ')}\nCONTEXT: ${cls.context}\n\nRead the relevant files. Return your recommended approach, risks the worker must watch (breaking changes, concurrency, security), and verdict PROCEED — or REVISE plus the revision the task definition needs.`,
        { model: A.advisorModel, phase: 'Advise', label: `advise:${task.id}`, schema: PLAN }
      )
    }
    return { cls, plan }
  },

  // Stage 3: implement + test-evidence gate (Steps 5, 6.1)
  async (prev, task) => {
    if (!prev) return null
    const { cls, plan } = prev
    const opts = { agentType: cls.subagent, model: A.workerModel, phase: 'Implement', label: `work:${task.id}`, schema: WORK }
    if (A.isolate) opts.isolation = 'worktree'
    let report = await agent(workerPrompt(task, cls, plan), opts)
    const noEvidence = (r) => r && r.status === 'DONE' && !task.spike && !(r.testFiles && r.testFiles.length)
    if (noEvidence(report)) {
      log(`task ${task.id}: DONE without test evidence — one retry with tests-first reminder`)
      report = await agent(workerPrompt(task, cls, plan,
        `A previous attempt${A.isolate ? ` (in ${report.workdir} — cd there and continue on that copy)` : ''} reported DONE without test evidence and was rejected. Tests are mandatory: add the missing tests for the acceptance criteria, make them pass, include testFiles and testOutput.`),
        { ...opts, isolation: undefined, label: `work-retry:${task.id}` })
      if (noEvidence(report)) {
        report = { ...report, status: 'FAILED', summary: 'Rejected twice: no test evidence. ' + report.summary }
      }
    }
    return { cls, plan, report }
  },

  // Stage 4: advisor code review + one fix round (Step 6.2)
  async (prev, task) => {
    if (!prev) return null
    let { cls, plan, report } = prev
    if (!report || report.status !== 'DONE') {
      return { task, cls, plan, report, review: null, final: report ? report.status : 'FAILED' }
    }
    if (!needsAdvisor(cls.complexity)) return { task, cls, plan, report, review: null, final: 'DONE' }

    const reviewPrompt = (rep) =>
      `You are the norman advisor reviewing completed work.\n\nTASK ${task.id}: ${task.description}\n\nACCEPTANCE CRITERIA:\n${task.acceptanceCriteria}\n\n${plan ? 'ORIGINAL APPROVED APPROACH:\n' + plan.approach + '\n\n' : ''}WORKER REPORT: ${rep.summary}\nFILES CHANGED: ${rep.filesChanged.join(', ')}\nWORKING DIRECTORY: ${rep.workdir}\n\nRead the changed files in that directory and judge the work: PASS, MINOR (log-worthy issues, not blockers), or REJECT (must be fixed before commit), with specific issues.`
    let review = await agent(reviewPrompt(report),
      { model: A.advisorModel, phase: 'Review', label: `review:${task.id}`, schema: REVIEW })

    if (review && review.quality === 'REJECT') {
      log(`task ${task.id}: review REJECT — running fix round`)
      report = await agent(workerPrompt(task, cls, plan,
        `A previous worker already implemented this task${A.isolate ? ` in ${report.workdir} — cd there and work on that copy` : ''}. Their summary: ${report.summary}\nThe advisor REJECTED the work with these issues — fix exactly these:\n${review.issues.map(i => `- ${i.file}: ${i.description}`).join('\n')}`),
        { agentType: cls.subagent, model: A.workerModel, phase: 'Review', label: `fix:${task.id}`, schema: WORK })
      review = report && report.status === 'DONE'
        ? await agent(reviewPrompt(report), { model: A.advisorModel, phase: 'Review', label: `re-review:${task.id}`, schema: REVIEW })
        : review
      if (!report || report.status !== 'DONE' || (review && review.quality === 'REJECT')) {
        return { task, cls, plan, report, review, final: 'REJECTED' }
      }
    }
    return { task, cls, plan, report, review, final: 'DONE' }
  }
)

return results
```

Note the fix-round and retry agents run WITHOUT worktree isolation and are instead told to cd into the original worker's worktree — a fresh isolated worktree would not contain the work they are fixing.

## After the workflow returns

Process results in task order, applying SKILL.md Mode 4 Step 6:

- **`final: DONE`** (quality PASS or MINOR) — run the Step 6.3 commit flow. Log MINOR issues in progress.md as improvement notes. Log `patterns` from worker and reviewer.
- **Isolated batches:** each DONE worker's changes live in its worktree (`report.workdir`), not the working tree. Bring them over before committing:

  ```bash
  git -C "$WORKDIR" add -A
  git -C "$WORKDIR" diff --cached --binary > /tmp/norman-task-N.patch
  git apply --index /tmp/norman-task-N.patch
  ```

  Apply patches one task at a time and run the project test command after each apply, before its commit. If a patch conflicts, commit the tasks that applied cleanly and re-run the conflicting task as a fresh batch of 1.
- **`final: REJECTED`** (failed review twice) — do NOT commit. Mark BLOCKED in TASKS.md, log both reviews, ask the user.
- **`final: FAILED`** — run the advisor-guided recovery from Mode 4 in the main loop (advisor diagnostician, then retry).
- **`final: BLOCKED`** — present `report.question` to the user, then re-run that task with the answer included (a fresh batch of 1, or a plain worker spawn).
- **`null` result** (user skipped the agent, or it died) — leave the task ACTIVE in TASKS.md and report it.

## Mode 5 (Verify) as a workflow

Same contract: the orchestrator extracts the requirement checklist first, passes it via `args`, and writes `prds/verification.md` from the returned array. Verify `args` add:

```json
{
  "advisorModel": "opus",
  "verifyRigor": "single",
  "doneTasks": "one-line summary per DONE task, for the completeness critic",
  "requirements": [
    { "id": "US-001", "text": "...", "criteria": "acceptance criteria from the PRD" }
  ]
}
```

Both rigor modes share the per-requirement verdict schema:

```js
const VERDICT = {
  type: 'object',
  required: ['requirement', 'verdict', 'evidence'],
  properties: {
    requirement: { type: 'string' },
    verdict: { enum: ['PASS', 'FAIL', 'PARTIAL'] },
    evidence: { type: 'string' },
  },
}

const verifyPrompt = (req, lens) => `You are a norman verifier. ${lens || 'Check whether this requirement is met: find the implementation, read it, confirm a test exercises the acceptance criteria, run it.'}

REQUIREMENT ${req.id}: ${req.text}
ACCEPTANCE CRITERIA:
${req.criteria}

Return PASS, FAIL, or PARTIAL with the specific evidence (files, test names, output) you found.`
```

**`single`** — one branch per requirement, one verifier each:

```js
const A = typeof args === 'string' ? JSON.parse(args) : args   // see note above

const results = await parallel(A.requirements.map((req) => () =>
  agent(verifyPrompt(req), { model: A.advisorModel, phase: 'Verify', label: `verify:${req.id}`, schema: VERDICT })
))
return { judged: results.filter(Boolean), critique: null }
```

**`adversarial`** — 2-3 lens verifiers per requirement, majority-combined, then a completeness critic over the whole set. This is a deliberate barrier (`parallel`, not `pipeline`): the critic must see every verdict at once.

```js
const A = typeof args === 'string' ? JSON.parse(args) : args   // see note above

const LENSES = [
  { key: 'exists',    ask: 'Does the implementation for this requirement actually exist in the codebase? Read the code — do not assume.' },
  { key: 'tested',    ask: 'Is there a test that actually exercises THIS requirement (not just adjacent code)? Read the test and confirm it asserts the criteria.' },
  { key: 'edgecases', ask: 'Do the stated edge cases and constraints hold? Try to find an input the implementation mishandles.' },
]

const CRITIQUE = {
  type: 'object',
  required: ['gaps'],
  properties: {
    gaps: {
      type: 'array',
      items: {
        type: 'object',
        required: ['requirement', 'downgradeTo', 'reason'],
        properties: {
          requirement: { type: 'string' },
          downgradeTo: { enum: ['PARTIAL', 'FAIL'] },
          reason: { type: 'string' },
        },
      },
    },
  },
}

const combine = (votes) => {
  const v = votes.filter(Boolean)
  const pass = v.filter((x) => x.verdict === 'PASS').length
  const fail = v.filter((x) => x.verdict === 'FAIL').length
  if (fail > pass) return 'FAIL'
  if (pass > v.length / 2) return 'PASS'
  return 'PARTIAL'
}

// Barrier: every requirement fully judged before the critic runs.
const judged = await parallel(A.requirements.map((req) => async () => {
  const votes = await parallel(LENSES.map((lens) => () =>
    agent(verifyPrompt(req, lens.ask),
      { model: A.advisorModel, phase: 'Verify', label: `verify:${req.id}:${lens.key}`, schema: VERDICT })))
  return {
    requirement: req.text,
    id: req.id,
    verdict: combine(votes),
    evidence: votes.filter(Boolean).map((x) => `[${x.verdict}] ${x.evidence}`).join('\n'),
  }
}))

const critique = await agent(
  `You are the norman completeness critic. Per-requirement verdicts so far:\n${JSON.stringify(judged, null, 2)}\n\nDONE TASKS:\n${A.doneTasks}\n\nFind what the per-requirement sweep structurally cannot: acceptance criteria that no test actually exercises, requirements with no implementation, anything claimed DONE without evidence. Return only genuine gaps, each as the requirement to downgrade to PARTIAL or FAIL with the reason.`,
  { model: A.advisorModel, phase: 'Verify', label: 'completeness-critic', schema: CRITIQUE })

return { judged, critique }
```

**After the workflow returns:** if `critique` is non-null, apply each gap by downgrading the matching `judged` entry's verdict (never upgrade). Then write `prds/verification.md` from the reconciled array and follow SKILL.md Mode 5 steps 5-6 (present, handle gaps). A `null` vote in a lens set (agent skipped or died) is simply dropped by `combine` — a requirement whose lenses all dropped is left `PARTIAL`.


## Mode 10 (Security) as a workflow

The orchestrator does steps 1-4 of `security.md` inline (context, PRD selection, area briefs, scope confirmation), then launches this script. The workflow never writes `prds/` or commits; the orchestrator writes the report and the fix phase from the returned object.

**args shape:**

```json
{
  "repo": "/abs/path/to/repo",
  "product": "one sentence: what the app is and what sensitive data it holds",
  "context": "- stack, deployment topology (proxy, client-IP handling), anything an auditor must know",
  "priorReport": "prds/verification.md",
  "routeFiles": "the files that hold the route tables",
  "states": "account and object states that change access, e.g. suspended, hidden, blocked, deleted, unverified",
  "maxPerPrd": 8,
  "prds": ["prds/done/prd-auth.md", "..."],
  "areas": [{ "key": "authz", "name": "Authorisation on owner-scoped routes", "brief": "tailored brief" }]
}
```

Both tracks run under one `parallel` so neither waits on the other. Inside each track every PRD and every area is a `pipeline`, so a PRD's mutation agent starts as soon as its own verdicts are in. The two critics are the only barriers, because each needs the whole track.

Agent count: about `prds x maxPerPrd x 3` verifiers, plus one extractor and one mutation agent per PRD, one auditor per area, three skeptics per finding, and two critics. 26 PRDs and 8 areas came to roughly 600-700 agents.

```js
export const meta = {
  name: 'norman-secure',
  description: 'Security check: norman verify (3 lenses + mutation + critic) over PRD security requirements, plus an 8-area threat review with adversarially verified findings',
  phases: [
    { title: 'Extract', detail: 'pull security/privacy requirements from each PRD', model: 'haiku' },
    { title: 'Verify', detail: '3 lens verifiers per requirement' },
    { title: 'Mutate', detail: 'break each PASS guarantee in a worktree; test must go red' },
    { title: 'Audit', detail: '8 threat-led area auditors' },
    { title: 'Confirm', detail: '3 skeptics per finding' },
    { title: 'Critic', detail: 'completeness critics over both tracks' },
  ],
}

const A = typeof args === 'string' ? JSON.parse(args) : args

const RULES = `Ground rules for this review (non-negotiable):
- Repository: ${A.repo}. Work READ-ONLY unless your instructions say otherwise. Never commit, never push, never edit anything under prds/.
- Never contact production, never use production credentials or operator tokens, never read secrets.
- Run tests narrowly (one package, one named test). Integration tests may start containers; avoid running whole suites.
- Cite evidence as file:line, test names and command output. Do not assume; read the code.
${A.context}
${A.priorReport ? `- An earlier security review is summarised in ${A.priorReport}. Do not re-report a fixed item unless you show it has regressed.` : ''}`

const REQS = {
  type: 'object', required: ['requirements', 'omitted'],
  properties: {
    requirements: { type: 'array', items: { type: 'object', required: ['id', 'text', 'criteria'],
      properties: { id: { type: 'string' }, text: { type: 'string' }, criteria: { type: 'string' } } } },
    omitted: { type: 'integer' },
  },
}
const VERDICT = {
  type: 'object', required: ['verdict', 'evidence'],
  properties: { verdict: { enum: ['PASS', 'FAIL', 'PARTIAL'] }, evidence: { type: 'string' },
    testNames: { type: 'array', items: { type: 'string' } } },
}
const MUT = {
  type: 'object', required: ['results'],
  properties: { results: { type: 'array', items: { type: 'object', required: ['id', 'killed', 'detail'],
    properties: { id: { type: 'string' }, killed: { type: 'boolean' }, detail: { type: 'string' } } } } },
}
const FINDINGS = {
  type: 'object', required: ['findings', 'coverage'],
  properties: {
    findings: { type: 'array', items: { type: 'object', required: ['title', 'severity', 'file', 'scenario', 'evidence'],
      properties: { title: { type: 'string' }, severity: { enum: ['HIGH', 'MEDIUM', 'LOW'] }, file: { type: 'string' },
        line: { type: 'integer' }, scenario: { type: 'string' }, evidence: { type: 'string' } } } },
    coverage: { type: 'string' },
  },
}
const CONFIRM = {
  type: 'object', required: ['confirmed', 'reason'],
  properties: { confirmed: { type: 'boolean' }, reason: { type: 'string' }, severity: { enum: ['HIGH', 'MEDIUM', 'LOW'] } },
}
const GAPS = {
  type: 'object', required: ['gaps'],
  properties: { gaps: { type: 'array', items: { type: 'object', required: ['target', 'kind', 'reason'],
    properties: { target: { type: 'string' }, kind: { enum: ['PARTIAL', 'FAIL', 'UNCOVERED'] }, reason: { type: 'string' } } } } },
}

const LENSES = [
  { key: 'exists', ask: 'Does the implementation for this requirement actually exist and hold on EVERY code path that reaches it (all routes, the API, background jobs, imports)? Read the code; do not assume.' },
  { key: 'tested', ask: 'Is there a test that exercises THIS requirement (not adjacent code) and asserts its criteria? Read the test, run it, and check whether it would still pass if the guarantee were broken (e.g. a negative test fed input that would be rejected anyway). Name the tests in testNames.' },
  { key: 'edgecases', ask: 'Act as an attacker. Try to find an input, ordering, concurrent request, alternate route or state (${A.states}) that breaks this requirement. PASS only if you looked hard and found nothing.' },
]

const combine = (votes) => {
  const v = votes.filter(Boolean)
  const pass = v.filter((x) => x.verdict === 'PASS').length
  const fail = v.filter((x) => x.verdict === 'FAIL').length
  if (!v.length) return 'PARTIAL'
  if (fail > pass) return 'FAIL'
  if (pass > v.length / 2) return 'PASS'
  return 'PARTIAL'
}

// ---------------- Track A: norman verify, adversarial ----------------
const trackA = async () => {
  const perPrd = await pipeline(A.prds,
    (prd) => agent(`${RULES}

Read ${prd} in full. Extract ONLY the requirements (user stories, functional and non-functional requirements, explicit constraints) that carry a SECURITY or PRIVACY guarantee: authentication, authorisation/ownership, visibility, blocks, rate limits, input validation, CSRF, encryption, secrets, data deletion/export/retention, consent, abuse prevention, what must never be published or exposed. Skip non-goals and pure UI/UX items.
Keep at most ${A.maxPerPrd}, choosing the ones whose failure would hurt users most; set omitted to how many qualifying ones you left out.
Ids: "${prd.replace(/^.*prd-/, '').replace(/\.md$/, '')}:<the PRD's own id, e.g. US-003 or FR-12>". criteria: the acceptance criteria verbatim or tightly paraphrased.`,
      { model: 'haiku', phase: 'Extract', label: `extract:${prd.replace(/^.*prd-/, '')}`, schema: REQS }),
    async (ex, prd) => {
      if (!ex) return { prd, judged: [], omitted: 0 }
      if (ex.omitted) log(`${prd}: ${ex.omitted} security requirements beyond the cap were not verified`)
      const judged = await parallel(ex.requirements.map((req) => async () => {
        const votes = await parallel(LENSES.map((lens) => () =>
          agent(`${RULES}

You are a norman verifier with one lens. ${lens.ask}

PRD: ${prd}
REQUIREMENT ${req.id}: ${req.text}
ACCEPTANCE CRITERIA:
${req.criteria}

Return PASS, FAIL or PARTIAL with specific evidence. Keep evidence under 1200 characters.`,
            { phase: 'Verify', label: `verify:${req.id}:${lens.key}`, schema: VERDICT })))
        const tests = [...new Set(votes.filter(Boolean).flatMap((v) => v.testNames || []))]
        return { id: req.id, text: req.text, verdict: combine(votes), tests,
          evidence: votes.map((x, i) => x ? `[${LENSES[i].key} ${x.verdict}] ${x.evidence}` : `[${LENSES[i].key} -] no vote`).join('\n') }
      }))
      return { prd, judged: judged.filter(Boolean), omitted: ex.omitted }
    },
    async (res) => {
      const passed = res.judged.filter((j) => j.verdict === 'PASS')
      if (!passed.length) return res
      const mut = await agent(`${RULES}
EXCEPTION to read-only: you are running in your own git worktree; you MAY edit Go source temporarily, but you MUST restore every file (git checkout -- <file>) before you finish, and leave git status clean.

Mutation sweep. For each requirement below, make the smallest edit to the implementation that breaks its guarantee (remove a check, widen a filter, skip an ownership test), run the named tests (or find the test that should guard it), record whether a test went red, then restore the file. One mutation at a time.

${passed.map((p) => `- ${p.id}: ${p.text}\n  tests: ${p.tests.join(', ') || '(find them)'}`).join('\n')}

killed=true means a test failed under the mutation. Put the mutation and the failing (or still-passing) test in detail, under 500 characters.`,
        { phase: 'Mutate', label: `mutate:${res.prd.replace(/^.*prd-/, '')}`, schema: MUT, isolation: 'worktree' })
      if (mut) for (const r of mut.results) {
        const j = res.judged.find((x) => x.id === r.id)
        if (!j) continue
        j.mutation = r.detail
        if (!r.killed) { j.verdict = 'PARTIAL'; j.evidence += `\n[mutation SURVIVED] ${r.detail}` }
      }
      return res
    })

  const all = perPrd.filter(Boolean).flatMap((p) => p.judged.map((j) => ({ prd: p.prd, ...j })))
  const critique = await agent(`${RULES}

You are the norman completeness critic. Per-requirement verdicts:
${JSON.stringify(all.map((j) => ({ id: j.id, verdict: j.verdict, text: j.text, tests: j.tests })), null, 1)}

Find what a per-requirement sweep structurally cannot: acceptance criteria no test exercises, requirements with no implementation, guarantees that hold on one route but whose sibling route (API vs HTML, htmx fragment vs full page, background job) was never checked. Spot-check the code for each gap you raise. Return only genuine gaps, kind PARTIAL or FAIL, target = the requirement id.`,
    { phase: 'Critic', label: 'critic:requirements', schema: GAPS })
  if (critique) for (const g of critique.gaps) {
    const j = all.find((x) => x.id === g.target)
    if (!j) continue
    const rank = { PASS: 0, PARTIAL: 1, FAIL: 2 }
    if (rank[g.kind] > rank[j.verdict]) j.verdict = g.kind
    j.evidence += `\n[critic ${g.kind}] ${g.reason}`
  }
  return { requirements: all, omitted: perPrd.filter(Boolean).map((p) => ({ prd: p.prd, omitted: p.omitted })), critique }
}

// ---------------- Track B: threat-led review ----------------
const SKEPTICS = [
  { key: 'reproduce', ask: 'Try to REPRODUCE it: trace the exact request path in the code (or write a throwaway test in a scratch _test.go you delete afterwards) and show whether the bad outcome actually happens.' },
  { key: 'reachable', ask: 'Check whether it is REACHABLE in the deployed setup: middleware order, auth gates, CSRF, rate limits, proxy/IP handling, body limits, feature flags. A finding that no real request can reach is not confirmed.' },
  { key: 'mitigated', ask: 'Look for an existing MITIGATION elsewhere (a filter in a shared query, a later check, a DB constraint, a template guard). Confirm only if nothing already prevents it.' },
]

const trackB = async () => {
  const perArea = await pipeline(A.areas,
    (area) => agent(`${RULES}

You are a security auditor for ${A.product}. Hunt for real, exploitable problems in this area:

AREA: ${area.name}
${area.brief}

Report each finding with file and line, a concrete attack scenario (who, which request, what they gain), and evidence from the code. Severity: HIGH = another member's private data exposed/altered or account takeover; MEDIUM = meaningful abuse, DoS or weaker privacy; LOW = defence in depth. Do not report style issues, theoretical issues with no path, or anything an earlier review fixed unless it has regressed. In coverage, list what you examined (routes, files) so a critic can see what you skipped.`,
      { agentType: 'security-auditor', phase: 'Audit', label: `audit:${area.key}`, schema: FINDINGS }),
    async (res, area) => {
      if (!res) return { area: area.key, findings: [], coverage: 'auditor failed' }
      const judged = await parallel(res.findings.map((f) => async () => {
        const votes = await parallel(SKEPTICS.map((s) => () =>
          agent(`${RULES}

You are a skeptic checking a claimed security finding. Default to confirmed=false if you cannot show it holds. ${s.ask}
If you write a scratch test, delete it before you finish.

FINDING (${f.severity}): ${f.title}
File: ${f.file}${f.line ? ':' + f.line : ''}
Scenario: ${f.scenario}
Evidence: ${f.evidence}

Return confirmed, a reason under 800 characters, and your own severity if confirmed.`,
            { phase: 'Confirm', label: `confirm:${area.key}:${s.key}`, schema: CONFIRM })))
        const v = votes.filter(Boolean)
        const yes = v.filter((x) => x.confirmed)
        return { ...f, confirmed: yes.length >= 2, votes: v.map((x, i) => `[${SKEPTICS[i] ? SKEPTICS[i].key : i} ${x.confirmed ? 'yes' : 'no'}] ${x.reason}`).join('\n'),
          severityAfter: yes.length ? yes.map((x) => x.severity || f.severity).sort()[0] : f.severity }
      }))
      return { area: area.key, coverage: res.coverage, findings: judged.filter(Boolean) }
    })

  const areas = perArea.filter(Boolean)
  const critique = await agent(`${RULES}

You are the completeness critic for a threat-led review. What each auditor covered:
${areas.map((a) => `## ${a.area}\n${a.coverage}\nconfirmed findings: ${a.findings.filter((f) => f.confirmed).map((f) => f.title).join('; ') || 'none'}`).join('\n\n')}

List the routes, handlers, background jobs or data flows that hold user data but NO auditor examined (check ${A.routeFiles} against the coverage). Spot-check the most sensitive uncovered ones yourself; for anything you find exploitable, kind=FAIL with file:line in reason. Otherwise kind=UNCOVERED.`,
    { phase: 'Critic', label: 'critic:threats', schema: GAPS })
  return { areas, critique }
}

const [a, b] = await parallel([trackA, trackB])
return { trackA: a, trackB: b }
```

**After the workflow returns:** `trackA.requirements` already has the critic's downgrades and surviving mutations folded in (never upgraded). `trackB.areas[].findings` carries `confirmed`, the skeptics' `votes` and `severityAfter`. Write `prds/verification.md` per `security.md` step 6, listing unconfirmed findings separately rather than dropping them, and continue with step 7.
