---
name: sweep
description: "Post-implementation cleanup. Two modes: prove tests actually guard the invariants they claim (mutation sweep), and strip stale task/phase scaffolding from comments while compressing over-long ones. Triggers on: sweep, /sweep, sweep invariants, sweep comments, test validation, validate tests, are my tests real, comment cleanup, tidy comments, strip task numbers, remove phase comments."
---

# Sweep - Post-Implementation Cleanup

Two cleanups that are worth doing after a phase or feature closes, when the code is
correct but the scaffolding around it has gone stale.

| Mode | Question it answers |
|------|--------------------|
| **Invariants** | Which of our stated guarantees would break silently, with every test still green? |
| **Comments** | Which comments describe a process that is over, or take 54 lines to say 16 lines of thing? |

They share a trigger (a phase just ended) but no machinery. Run either alone.

```
sweep invariants     # mutation sweep: break each guard, see if any test notices
sweep comments       # strip task/phase scaffolding, compress over-long blocks
sweep                # ask which
```

---

## When To Use

**Invariants** — after a run of features has landed, before trusting the suite as a
regression net, or when a review keeps turning up tests that pass with the feature
deleted. It is slow and token-heavy. It is not a per-commit check.

**Comments** — after a project that used numbered tasks (norman phases, sprint IDs,
FR-/US- requirement numbers). Those references are load-bearing while the work is in
flight and become noise the moment the sprint doc is archived.

Neither mode changes behaviour. If either produces a behaviour change, that is a bug in
the sweep, not a finding.

---

## Mode 1: Invariants

A test that passes when you delete the feature is not a test. This mode finds those by
mutation testing: break each guarantee the code claims to make, and see whether anything
goes red.

Read `invariants.md` (same directory as this file) for the full procedure, the reference
workflow script, and the agent prompts.

### The shape

```
Phase A  enumerate    what does this codebase PROMISE? -> falsifiable invariants
         (you filter) drop weak entries by hand; dedupe by (file, line)
Phase B  break        apply the smallest violating edit, run the tests
Phase C  verify       adversarially refute every "nothing failed" claim
```

Phase A reads the project's own stated guarantees — the guardrails section of CLAUDE.md,
completed PRDs, security-relevant doc comments — not just the code. An invariant nobody
ever wrote down is a guess about intent; an invariant in CLAUDE.md is a promise.

You filter between A and B. Keep the ones where a silent break costs data, leaks across
accounts, weakens auth, or misleads an operator. Drop the rest. Do not delegate this.

### Non-negotiables

These come from watching each one go wrong:

1. **Never modify a file in the working tree.** Go: `go test -overlay`. Anything else: a
   throwaway `git worktree`. After every run, confirm `git status --porcelain` is
   unchanged. An agent that edits in place and crashes leaves sabotaged source behind.

2. **The break must compile.** A build failure proves nothing and reads as a result.
   Replacing `if !hmac.Equal(sig, want) {` with `if false {` orphans `sig` — Go rejects it
   as "declared and not used". Write `if false && !hmac.Equal(sig, want) {`: it
   short-circuits to the insecure path and keeps every variable used. Generalise the trick.

3. **The break must point the right way.** It has to make the *forbidden* thing possible —
   accept the bad cookie, serve the other user's data, delete the referenced blob. A guard
   broken so it rejects *valid* input will also fail a test, and that failure means nothing.
   This is the most common way a mutation sweep fools itself into a clean bill of health.

4. **"The package tests passed" is not a finding yet.** Escalate: grep for tests elsewhere
   that touch the behaviour, including suites behind build tags that a plain
   `go test ./...` never compiles. Only when the search comes up empty is the absence
   itself the evidence.

5. **Never run the full suite from inside an agent.** Concurrent full suites starve each
   other and produce false failures that look like real findings. Run the target package;
   escalate narrowly with `-run`.

6. **Verify a "nothing failed" claim before believing it.** Every one goes to a second
   agent told to assume it is wrong. Most get refuted — usually because the break pointed
   the wrong way, or a suite behind a build tag does catch it.

7. **A stray test binary outlives the agent that started it.** Killing a wrapper does not
   kill its child. Check for leftover test processes before blaming a diff for a timeout.

### Output

Findings are gaps in *coverage*, not bugs. Report each as: the guarantee, the edit that
broke it undetected, what it would cost in production. Then ask which are worth a test —
that is a priority call, not yours to make.

---

## Mode 2: Comments

Strip references to a development process that has finished, and compress comments that
have grown longer than the thing they explain.

Read `comments.md` (same directory) for the full taxonomy, worked examples, and the
per-file procedure.

### What this is not

It is not a campaign against long comments. A comment that takes 20 lines to explain a
subtle bug fix is doing its job. Overall comment-to-code ratio is not a target — measure
it, and if it is unremarkable, say so and go after the specific offenders instead of
trimming everywhere.

### The hard rule, first

**Some comments are code.** In Go: `//go:build`, `//go:generate`, `//go:embed`,
`//nolint`, `// +build`, `//export`, and cgo preamble. Elsewhere: pragmas, `# type:`
hints, `<!-- prettier-ignore -->`, annotation-driven codegen.

Reformat one and the build changes silently. Dropping a `//go:build integration` line
removes a whole suite from CI while every local run stays green. **Never touch a directive
comment — not to reflow it, not to fix its spacing.** Enumerate them before starting.

### Remove

- Task, phase, sprint, story and requirement numbers: `Phase 9`, `T-4.1`, `FR-8`,
  `US-RECV-2`, `Step 2`, and pointers to archived sprint docs. Keep the *fact*, drop the
  citation: `the data model for FR-8 (domain ownership)` becomes `the data model for
  domain ownership`.
- Comments that restate the code.
- Changelog narration — "previously we did X, then in phase 3 we switched" — unless the
  history is the rationale, in which case keep the rationale and drop the chronology.
- The same point made three times in one block.
- `Decision:` / `Rationale:` headers on a block that makes a single point.

### Never remove

- **Why, not what.** Rationale, trade-offs, alternatives that were rejected and why.
- **Hazards and contracts.** "Not safe to repeat", "must run before X", locking and
  ordering rules, anything about concurrency.
- **Bug-fix provenance.** "This exists because <failure mode>" is the most expensive kind
  of comment to lose — it is the one that stops someone reverting the fix.
- **Spec citations.** RFC and standard numbers stay. They are external and permanent,
  unlike an internal FR- number. This distinction is the whole point: `FR-6/RFC 2045
  section 6.4 forbids ...` loses `FR-6` and keeps `RFC 2045 section 6.4`.
- **Security reasoning**, and any note about what an attacker could otherwise do.
- Directive comments (above), and `TODO`/`FIXME` that name an owner or condition.

### Compress

Target blocks over ~10 lines. Rewrite to: one sentence of what it is, then the
load-bearing "why"s as tight prose. Every distinct claim survives; the repetition does not.
If you cannot compress it without losing a claim, leave it — that comment has earned its
length.

Keep language doc conventions: a Go doc comment still starts with the identifier name.

### Verify, every time

Comments cannot change behaviour — except when they can (see the hard rule). So:

```
gofmt -l .        # must be empty
go build ./...
go vet ./...      # compiles test files too
go test ./...     # the suite must be as green as it was before you started
```

Confirm the suite was green *before* the sweep, or you will inherit someone else's failure
and think you caused it.

### Applying

Rewrite in place, do not commit. The review is `git diff`. Say plainly which files you
touched and roughly how many comment lines went. If a block was left alone because
compressing it would have cost a claim, say that too — it is the more interesting half of
the report.
