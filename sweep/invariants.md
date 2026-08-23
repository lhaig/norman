# Sweep - Invariants Mode

Mutation testing against stated guarantees. Break each promise the codebase makes and find
out whether any test notices.

The finding is always the same shape: *this guarantee can be violated and the suite stays
green*. That is a coverage gap, not a bug. The code is (presumably) still correct today —
what is missing is anything that would tell you when it stops being.

---

## Before starting

Confirm all three, in the repo, yourself:

1. **The suite is green.** Otherwise you cannot tell your break from a pre-existing failure.
2. **The working tree is clean.** Record `git status --porcelain` and `git rev-parse HEAD`.
   Every agent will be told the expected clean-state output verbatim.
3. **You can break something and see it fail.** Do one by hand end to end before spawning
   anything. If the harness cannot detect a deliberate, obvious break, it will report the
   whole codebase as unguarded and every finding will be noise.

Step 3 is not optional. It is a ten-minute check that has caught a broken harness more
than once.

---

## Phase A — enumerate invariants

Fan out one agent per domain. Domains are areas of the system where a silent failure has a
distinct cost — for a mail server: auth and session, tenancy and ownership, relay and
trust, durability. Pick 3-5. Do not use one agent for the whole codebase; it will return
generic advice.

**Sources, in priority order:**

1. The project's own guardrails — a "do not do X" section in CLAUDE.md is a promise
   someone wrote down after being burned. Highest value.
2. Completed PRDs and their acceptance criteria.
3. Doc comments that assert a security or durability property ("a captured signature
   cannot be replayed", "committed in one batch").
4. The code itself — last, because a guard with no stated purpose might be incidental.

**Each invariant must come back with:**

| Field | Requirement |
|-------|-------------|
| `id` | stable kebab-case slug |
| `guarantee` | falsifiable, one sentence, in the form "X cannot happen" or "Y always holds" |
| `file`, `line` | where it is enforced |
| `breakEdit` | the *smallest* edit that violates it |
| `consequence` | what it costs in production, concretely |
| `likelyTest` | the test that should catch it, or `unknown` |
| `source` | which of the four sources above, cited |

A `likelyTest: unknown` is a strong early signal but proves nothing on its own — and a
*named* test proves nothing either. Vacuous tests with confident names are the reason this
mode exists. Break all of them.

### Then you filter

Dedupe by `(file, line)` — independent agents rediscover the same guard, which is mild
evidence it matters.

Keep what would cost data, leak across accounts, weaken auth, or mislead an operator. Drop
the rest. Do this yourself: it is a judgement about what the project cares about, and it
is the step that keeps Phase B from spending an hour on trivia.

Group survivors by package, ~5 per batch. One agent per batch, not per invariant — a batch
of 5 amortises the agent's orientation cost across five breaks in code it has already read.

---

## Phase B — break them

Per invariant: apply the break, run the tests, record whether anything failed.

### Isolation

**Never edit the working tree.**

Go — `-overlay` redirects the compiler without touching disk:

```bash
mkdir -p "$SCRATCH/<id>"
cp internal/pkg/target.go "$SCRATCH/<id>/target.go"
# apply the break to the COPY
printf '{"Replace":{"%s/internal/pkg/target.go":"%s/<id>/target.go"}}' "$REPO" "$SCRATCH" \
  > "$SCRATCH/<id>/ov.json"
go test -overlay="$SCRATCH/<id>/ov.json" -count=1 ./internal/pkg/
```

Other languages — `git worktree add` a throwaway checkout, break it there, run there,
remove it. Slower, equally safe.

Either way: after every run, `git status --porcelain` must match the clean state recorded
up front.

### Writing a break that means something

**It must compile.** A build failure is not a test failure, and an agent skimming output
will score it as one. The classic:

```go
// original
if !hmac.Equal(sig, sign(secret, payload)) { return nil, http.ErrNoCookie }

// WRONG - "declared and not used: sig", build fails, result is garbage
if false { return nil, http.ErrNoCookie }

// RIGHT - short-circuits to the insecure path, every variable still used
if false && !hmac.Equal(sig, sign(secret, payload)) { return nil, http.ErrNoCookie }
```

**It must point the right way.** The break has to make the forbidden thing *possible*.
Inverting a guard so it rejects valid input will fail a test loudly and tell you nothing
about whether the guarantee is protected. Re-read the guarantee, then confirm the edit
enables the violation rather than merely breaking the code.

**Line numbers drift.** Read the code around the cited line. If the guard is elsewhere in
the file, find it. If it does not exist at all, that is `STALE_LOCATION` — the enumerator
described code that is not there, which is worth knowing on its own.

**Do not fake a result.** If no compiling break violates the guarantee, say
`COULD_NOT_BREAK` and explain. That is a legitimate outcome and sometimes means the
guarantee is structural rather than guarded by a conditional.

### Verdicts

```
run the owning package's tests
  |
  +-- something failed ................ GUARDED. Record the test names. Stop.
  |
  +-- everything passed ............... not a finding yet. Escalate:
        1. grep the repo for tests touching this function/route/behaviour
        2. include suites behind build tags - a plain `go test ./...` never
           compiles them, so they are invisible to a naive search
        3. run any plausible candidate under the same break, targeted with -run
        4. nothing plausible exists anywhere -> that absence IS the evidence;
           say so rather than running a broad suite to prove a negative
        |
        +-- still nothing ............. UNGUARDED (claim only, pending Phase C)
```

Record every command verbatim. A reviewer re-runs them.

**Never run the full suite from an agent.** Concurrent full suites starve each other under
`-race` and produce timeouts that look exactly like real findings.

---

## Phase C — refute the findings

Every `UNGUARDED` goes to a fresh agent whose instruction is: *assume this is wrong.*

Refute it by finding any of:

1. The edit did not violate the stated guarantee — no-op on the real path, or it broke the
   harmless direction.
2. The build failed and the failure was misread as a pass.
3. A test elsewhere does catch it. Re-derive the search independently, then re-run that
   test under the same break and watch it fail.
4. The guarantee was over-claimed and the code never promised it.

Only what survives gets reported. Expect most claims to die here — that is the pass working,
not a waste. Rank survivors by production cost: data loss, cross-account exposure, auth
bypass and open relay are the top tier.

---

## Reference workflow script

Pipelined so each batch's verification starts as soon as that batch lands, rather than
waiting on a barrier. Substitute your own paths, batch names and repo constants.

```javascript
export const meta = {
  name: 'invariant-break-sweep',
  description: 'Break each stated invariant and record whether any test notices',
  phases: [{ title: 'Break' }, { title: 'Verify' }],
}

const BREAK_SCHEMA = {
  type: 'object',
  required: ['batch', 'results'],
  properties: {
    batch: { type: 'string' },
    results: {
      type: 'array',
      items: {
        type: 'object',
        required: ['id', 'file', 'line', 'guarantee', 'verdict', 'appliedEdit',
                   'commandsRun', 'notes'],
        properties: {
          id: { type: 'string' }, file: { type: 'string' }, line: { type: 'integer' },
          guarantee: { type: 'string' },
          verdict: { type: 'string',
                     enum: ['GUARDED', 'UNGUARDED', 'COULD_NOT_BREAK', 'STALE_LOCATION'] },
          appliedEdit: { type: 'string' },
          commandsRun: { type: 'array', items: { type: 'string' } },
          failingTests: { type: 'array', items: { type: 'string' } },
          consequence: { type: 'string' }, notes: { type: 'string' },
        },
      },
    },
  },
}

const VERIFY_SCHEMA = {
  type: 'object',
  required: ['id', 'verdict', 'reason'],
  properties: {
    id: { type: 'string' },
    verdict: { type: 'string', enum: ['CONFIRMED_UNGUARDED', 'REFUTED'] },
    reason: { type: 'string' },
    missedTest: { type: 'string' },
    severity: { type: 'string', enum: ['high', 'medium', 'low'] },
  },
}

phase('Break')
const results = await pipeline(
  BATCH_NAMES,
  (batch) => agent(breakPrompt(batch),
                   { label: `break:${batch}`, phase: 'Break', schema: BREAK_SCHEMA }),
  (res, batch) => {
    if (!res || !res.results) return { batch, results: [] }
    const suspects = res.results.filter((r) => r.verdict === 'UNGUARDED')
    if (suspects.length === 0) return res
    log(`${batch}: ${suspects.length} claimed unguarded, verifying`)
    return parallel(suspects.map((r) => () =>
      agent(verifyPrompt(r), { label: `verify:${r.id}`, phase: 'Verify',
                               schema: VERIFY_SCHEMA })
        .then((v) => ({ ...r, verification: v }))
    )).then((verified) => ({
      ...res,
      results: res.results.map((r) =>
        verified.filter(Boolean).find((x) => x.id === r.id) || r),
    }))
  }
)

const all = results.filter(Boolean)
  .flatMap((r) => (r.results || []).map((x) => ({ ...x, batch: r.batch })))
return {
  confirmed: all.filter((r) => r.verification?.verdict === 'CONFIRMED_UNGUARDED'),
  refuted:   all.filter((r) => r.verification?.verdict === 'REFUTED'),
  problems:  all.filter((r) => ['COULD_NOT_BREAK', 'STALE_LOCATION'].includes(r.verdict)),
  guarded:   all.filter((r) => r.verdict === 'GUARDED')
                .map((r) => ({ id: r.id, file: r.file, failingTests: r.failingTests })),
}
```

### Prompt checklist

Every break agent's prompt must carry, explicitly:

- The exact clean `git status --porcelain` output to expect, and an instruction to check it
  after every command.
- The overlay/worktree mechanics, with a concrete worked example.
- The compile trap and the `if false && ...` fix.
- The direction trap: make the forbidden thing possible.
- The escalation ladder, including build-tagged suites.
- The ban on full-suite runs, and why.
- "A `GUARDED` result is the good outcome and most should come back `GUARDED`. Do not
  manufacture findings."

That last line matters. An agent that infers you are hunting for gaps will find them.

---

## Reporting

```
swept N: <g> guarded, <c> confirmed unguarded, <r> refuted, <p> could-not-break/stale
```

Per confirmed gap: the guarantee, the edit that went undetected, the production cost, and
where a test would go. Then stop and ask which are worth writing. Filling every gap is
rarely correct — some guarantees are cheap to state and expensive to test, and that
trade-off is the user's to make.

Mention the refuted count. It is the evidence that the confirmed ones survived something.
