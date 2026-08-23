# Sweep - Comments Mode

Strip references to a development process that has ended, and compress comments that have
outgrown the code they explain.

The goal is not fewer comment lines. It is that every surviving line earns its place, and
that nothing which would stop a future reader from reintroducing an old bug gets deleted.

---

## Step 0: the hazard, before anything else

**Some comments are code.** Enumerate them first, and treat their line ranges as
untouchable — not to reflow, not to fix spacing, not to merge into the block above.

```bash
grep -rnoE '^\s*//\s*(go:[a-z]+|\+build|nolint|export)' --include='*.go' .
grep -rn 'cgo\|#include' --include='*.go' . | head
```

In Go: `//go:build`, `//go:generate`, `//go:embed`, `//nolint`, the legacy `// +build`,
`//export`, and the cgo preamble immediately above `import "C"`. Elsewhere: pragmas, type
hints in comments, formatter directives, annotation-driven codegen.

The specific disaster to avoid: dropping or corrupting a `//go:build integration` line
removes an entire suite from the build. Every local run stays green, CI stays green, and
the suite is simply gone. That failure mode has a long history of going unnoticed for
weeks.

Placement matters as much as content — `//go:build` must precede the package clause with a
blank line after it. Do not move it.

---

## Step 1: measure before you touch anything

Establish that there is a real problem and where it is concentrated. Repo-wide trimming
based on a feeling is how good comments get deleted.

```bash
# comment-to-code ratio and block-length distribution
python3 - <<'EOF'
import os, collections
runs, cmt, code = [], 0, 0
for root, dirs, files in os.walk('.'):
    dirs[:] = [d for d in dirs if d not in ('.git','bin','node_modules','vendor','dist')]
    for f in files:
        if not f.endswith('.go') or f.endswith('_templ.go') or f.endswith('.pb.go'):
            continue
        p = os.path.join(root, f)
        cur = start = 0
        for n, l in enumerate(open(p, encoding='utf-8', errors='replace'), 1):
            s = l.strip()
            if s.startswith('//'):
                cmt += 1
                if not cur: start = n
                cur += 1
            else:
                if s: code += 1
                if cur: runs.append((cur, p, start)); cur = 0
        if cur: runs.append((cur, p, start))
runs.sort(reverse=True)
print(f"comment {cmt}  code {code}  ratio {cmt/code:.2f}")
b = collections.Counter()
for c,_,_ in runs:
    b['1-3' if c<=3 else '4-6' if c<=6 else '7-10' if c<=10 else '11-20' if c<=20 else '21+'] += 1
print(dict(b))
print(f">10 lines: {sum(1 for c,_,_ in runs if c>10)} blocks, "
      f"{sum(c for c,_,_ in runs if c>10)} lines")
for c,p,s in runs[:15]: print(f"  {c:3d}  {p}:{s}")
EOF

# process scaffolding
grep -rnE '^\s*(//|/\*).*\b(Phase|Task|Sprint|Step|T-|US-|FR-)\s*-?[0-9]+(\.[0-9]+)*' \
  --include='*.go' . | grep -v '_templ.go\|\.pb\.go'
```

A ratio around 0.10-0.15 is healthy. Report it. If the aggregate is unremarkable, say so
and go after the specific long blocks — do not let a tidy-up become a repo-wide rewrite.

Also confirm the suite is green *now*, before any edit. Inheriting someone else's failure
and attributing it to your sweep wastes an hour.

---

## Step 2: the taxonomy

### Remove

**Process scaffolding.** Task, phase, sprint, story and requirement numbers, and pointers
to sprint docs that are now archived. Keep the fact, drop the citation:

```go
// before
// via Raft. It provides the data model for FR-8 (domain ownership + tenant model).
// after
// via Raft. It provides the data model for domain ownership and the tenant model.

// before
// dedupMinSize is the attachment-dedup threshold (Phase 9). > 0 stores sent
// after
// dedupMinSize is the attachment-dedup threshold. > 0 stores sent
```

Where the number is the entire content, the comment goes with it:

```go
// before
// FR-5: best-effort retrieval of the original message's header block
// after
// Best-effort retrieval of the original message's header block
```

**Restatement of the code.** `// increment i`, `// returns the user`, a doc comment that
is the function signature in prose.

**Changelog narration.** "We used to do X, then in phase 3 we switched to Y." If the
history *is* the rationale — Y was chosen because X had a specific failure — keep the
rationale and drop the chronology.

**Repetition.** The same claim made in the summary, the `Rationale:` paragraph, and again
in a bullet. Keep the clearest statement.

**`Decision:` / `Rationale:` headers** on a block that makes one point. They are structure
for a document, not for four lines.

### Never remove

- **Why, not what.** Rationale, trade-offs, alternatives rejected and the reason.
- **Hazards and contracts.** "Not safe to repeat", "must be called before X", lock
  ordering, anything about concurrency or reentrancy.
- **Bug-fix provenance.** "This exists because <failure mode>" is the single most
  expensive comment to lose. It is what stops the next person deleting the fix as
  redundant.
- **Spec citations.** RFC and standard numbers are external and permanent. This is the
  distinction that makes the whole mode safe:

  ```go
  // before
  // Part 2: machine-readable DSN. FR-6/RFC 2045 section 6.4 forbids ...
  // after
  // Part 2: machine-readable DSN. RFC 2045 section 6.4 forbids ...
  ```

- **Security reasoning**, including what an attacker could otherwise do.
- **Directive comments** (Step 0).
- **`TODO`/`FIXME` that name an owner or a condition.** A bare `// TODO` with no owner and
  no condition is noise and may go.
- **Test doc comments explaining what a test proves and why it would otherwise be
  vacuous.** These look verbose and are load-bearing — they are often the only record of
  why the assertion is shaped that way.

### Compress

Blocks over ~10 lines. Rewrite to one sentence of what it is, then the load-bearing "why"s
as tight prose. Every distinct claim survives; the repetition does not.

**If you cannot compress without losing a claim, leave it.** That comment earned its
length. Blocks left alone deliberately are worth reporting — more interesting than the
ones you cut.

---

## Worked example

54 comment lines guarding a 6-line function. Real, and a good stress test: most of it is
genuine rationale for a bug fix, wrapped in repetition and scaffolding.

```go
// BEFORE (54 lines)
// PrepareForRelease resets the quarantine state on an envelope so it is
// re-delivered without re-running the stage that quarantined it.
//
// Decision: release clears ONLY MsgFlagQuarantined. Scanning-related flags
// (MsgFlagSpamChecked, MsgFlagVirus, MsgFlagVirusChecked, MsgFlagSpam) and
// their StageResults are retained.
//
// Rationale: release means "the admin has reviewed this and overrides the
// verdict". It is not rescan (which means "check this again"). The runner's
// idempotency check (runner.go, processMessage) will skip stages whose
// checked flags are already set, so the released envelope will not re-run
// whichever of antispam/antivirus already ran and quarantined it. This is
// the correct behaviour: we trust the admin's judgment, not the scanner's
// original verdict.
//
// The rules stage is NOT skipped: when antispam or antivirus quarantines a
// message, the pipeline returns before the rules stage ever runs (see
// processMessage's quarantine branch, which returns immediately), so
// MsgFlagRulesChecked was never set. On release, rules therefore runs for
// the first and only time [...continues for 35 more lines...]

// AFTER (16 lines)
// PrepareForRelease clears quarantine so the message is re-delivered WITHOUT
// re-running the stage that caught it: release means the admin overrode the
// verdict, not "check this again". Scan flags stay set, so the runner's
// idempotency check skips those stages.
//
// Rules DOES run — quarantine returns before it ever ran, so its flag was
// never set. Release can therefore forward; callers should expect that.
//
// TargetMailbox "" or "Junk" is forced to INBOX. Both are consequences of
// the verdict just overridden ("" falls back to the retained spam score,
// which is always above the Junk line; "Junk" survives from the tag band
// when DMARC escalated without clearing it). Leaving either files
// admin-approved mail into Junk — a softer replay of the silent
// non-delivery bug this function exists to fix. Any other value is a real
// folder choice and is left alone.
//
// StageResults are kept as an audit record only; they do not block delivery.
```

Every claim in the original survives: which flags are cleared and why, the rules-stage
side effect, both `TargetMailbox` cases *and* their separate causes, the bug this fixes,
and the audit record. What went: the `Decision:`/`Rationale:` scaffolding, the file
cross-references a reader can follow anyway, and three restatements of "we trust the
admin".

---

## Step 3: procedure

Work file by file, most-offending first. Do not batch blind edits across the repo.

1. Read the whole file. A block often repeats something already said above it — you cannot
   see that from a grep hit.
2. Note directive comments in this file. Do not touch them.
3. Apply removals, then compressions.
4. `gofmt -w` the file (never on a directive line's placement — gofmt will not move it,
   but check).
5. Re-read the diff for that file before moving on. This is where a lost claim is cheap to
   recover.

Every 3 files, run `go build ./...`. A comment edit that breaks the build has almost
certainly hit a directive, and you want to know within three files, not thirty.

---

## Step 4: verify

```bash
gofmt -l .        # must print nothing
go build ./...
go vet ./...      # compiles test files too, catching directive damage in _test.go
go test ./...     # must be exactly as green as your Step 1 baseline
```

If the project has a build-tagged suite, run it too — that is precisely where a damaged
`//go:build` line hides:

```bash
go test -tags=integration ./test/integration/...
```

A behaviour change means you hit a directive. Find it; do not paper over it.

---

## Step 5: report

Apply in place, do not commit. The review is `git diff`.

State: files touched, comment lines removed, blocks compressed, and the before/after
ratio. Then the more useful half — which blocks you left alone and why, and which
scaffolding references you kept because the surrounding fact would have been lost with
them.

If the measurement in Step 1 showed the repo was basically fine, say that outright rather
than manufacturing a cleanup to justify the run.
