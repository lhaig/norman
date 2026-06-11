# Norman Workflow Execution Reference

Read by the orchestrator when running Mode 4 (Continue) Steps 3-6 through the Workflow tool. Not needed when falling back to plain Agent calls.

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
  "projectRules": "extracted CLAUDE.md rules (Step 3.5)",
  "patterns": "relevant PATTERN lines from progress.md",
  "commands": { "build": "...", "test": "...", "lint": "..." },
  "tasks": [
    { "id": "3.1", "description": "...", "acceptanceCriteria": "from the PRD", "spike": false }
  ]
}
```

Set `isolate: true` whenever `tasks.length > 1` — workers then run in git worktrees so parallel edits cannot collide. A batch of 1 runs directly in the working tree.

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
  args.advisorMode === 'always' || (args.advisorMode === 'auto' && complexity !== 'low')

const workerPrompt = (task, cls, plan, extra) => `
You are implementing one task for the norman orchestrator. Your final output is parsed as structured data, not shown to a human.

PROJECT RULES (non-negotiable):
${args.projectRules}

TASK ${task.id}: ${task.description}

ACCEPTANCE CRITERIA:
${task.acceptanceCriteria}

${plan ? `ADVISOR GUIDANCE (follow this approach):\n${plan.approach}\nRISKS: ${plan.risks}\n${plan.verdict === 'REVISE' ? 'REVISED TASK DEFINITION: ' + plan.revision : ''}` : ''}

RELEVANT FILES: ${cls.files.join(', ')}
CONTEXT: ${cls.context}

PATTERNS FROM EARLIER TASKS:
${args.patterns}

COMMANDS: build: ${args.commands.build} | test: ${args.commands.test} | lint: ${args.commands.lint}

${task.spike
  ? 'This is a (spike) task: prototype first, tests come in a follow-up task.'
  : 'TESTS FIRST: write a failing test encoding the acceptance criteria BEFORE implementation, then implement until green. A DONE report without testFiles and passing testOutput will be rejected.'}

Do NOT commit. Do NOT modify anything under prds/. Report workdir as the absolute path of the repo root you worked in (run pwd).
${extra || ''}`

const results = await pipeline(
  args.tasks,

  // Stage 1: classify (Step 3)
  (task) => agent(
    `Read ${args.subagentsGuidePath} for the classification guide. Search the codebase for files relevant to this task (read at most 5), verify the chosen subagent exists per the guide, and return the classification.\n\nTASK ${task.id}: ${task.description}\n\nACCEPTANCE CRITERIA:\n${task.acceptanceCriteria}`,
    { model: args.quickModel, phase: 'Classify', label: `classify:${task.id}`, schema: CLASSIFY }
  ),

  // Stage 2: advisor plan review (Step 3.1)
  async (cls, task) => {
    if (!cls) return null
    let plan = null
    if (needsAdvisor(cls.complexity)) {
      plan = await agent(
        `You are the norman advisor reviewing a task plan before a worker implements it.\n\nTASK ${task.id}: ${task.description}\n\nACCEPTANCE CRITERIA:\n${task.acceptanceCriteria}\n\nCLASSIFIED FILES: ${cls.files.join(', ')}\nCONTEXT: ${cls.context}\n\nRead the relevant files. Return your recommended approach, risks the worker must watch (breaking changes, concurrency, security), and verdict PROCEED — or REVISE plus the revision the task definition needs.`,
        { model: args.advisorModel, phase: 'Advise', label: `advise:${task.id}`, schema: PLAN }
      )
    }
    return { cls, plan }
  },

  // Stage 3: implement + test-evidence gate (Steps 5, 6.1)
  async (prev, task) => {
    if (!prev) return null
    const { cls, plan } = prev
    const opts = { agentType: cls.subagent, model: args.workerModel, phase: 'Implement', label: `work:${task.id}`, schema: WORK }
    if (args.isolate) opts.isolation = 'worktree'
    let report = await agent(workerPrompt(task, cls, plan), opts)
    const noEvidence = (r) => r && r.status === 'DONE' && !task.spike && !(r.testFiles && r.testFiles.length)
    if (noEvidence(report)) {
      log(`task ${task.id}: DONE without test evidence — one retry with tests-first reminder`)
      report = await agent(workerPrompt(task, cls, plan,
        `A previous attempt${args.isolate ? ` (in ${report.workdir} — cd there and continue on that copy)` : ''} reported DONE without test evidence and was rejected. Tests are mandatory: add the missing tests for the acceptance criteria, make them pass, include testFiles and testOutput.`),
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
      { model: args.advisorModel, phase: 'Review', label: `review:${task.id}`, schema: REVIEW })

    if (review && review.quality === 'REJECT') {
      log(`task ${task.id}: review REJECT — running fix round`)
      report = await agent(workerPrompt(task, cls, plan,
        `A previous worker already implemented this task${args.isolate ? ` in ${report.workdir} — cd there and work on that copy` : ''}. Their summary: ${report.summary}\nThe advisor REJECTED the work with these issues — fix exactly these:\n${review.issues.map(i => `- ${i.file}: ${i.description}`).join('\n')}`),
        { agentType: cls.subagent, model: args.workerModel, phase: 'Review', label: `fix:${task.id}`, schema: WORK })
      review = report && report.status === 'DONE'
        ? await agent(reviewPrompt(report), { model: args.advisorModel, phase: 'Review', label: `re-review:${task.id}`, schema: REVIEW })
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

Same contract: orchestrator extracts the requirement checklist first, then one pipeline — each requirement goes to a verifier agent on `advisorModel` with schema `{ requirement, verdict: PASS|FAIL|PARTIAL, evidence }`. The orchestrator writes `prds/verification.md` from the returned array.
