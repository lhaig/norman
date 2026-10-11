# Mode 10: Security review

Start with: "norman secure"

An in-depth security check of a whole project, in two tracks that run side by side:

- **Track A, requirement verification.** Mode 5 at `adversarial` rigor, scoped to the security and privacy requirements of the done PRDs, with a mutation sweep per PRD. It checks what the PRDs promised.
- **Track B, threat-led review.** Area auditors hunt for exploitable problems no PRD mentions, and every finding is checked by three skeptics before it is reported. It checks what the PRDs left out.

Track A alone misses whatever nobody wrote down. Track B alone gives findings with no record of which guarantees were checked and held. Run both.

This mode is expensive: several hundred agents on the advisor model, and several hours. Confirm the scope with the user before launching (step 4), and say how many agents it will use.

### Process

1. **Read context (orchestrator, inline).** Read the project instructions file, `prds/config.md`, and any earlier security report (usually `prds/verification.md`). Note what an earlier review already fixed, so auditors check for regressions rather than re-report it. Count the route tables or entry points to size the attack surface.

2. **Select PRDs.** List `prds/done/`. Keep the PRDs that carry security or privacy weight: authentication, sessions, authorisation, visibility, blocking, uploads, imports, outbound fetches, APIs, billing, data export and deletion, consent, email, admin, multi-tenant (company or organisation) roles, anything that publishes to a third party. A keyword count over each PRD (auth, token, visib, private, block, rate limit, delete, export, upload, admin, consent, session, password) is a quick first cut; read the borderline ones. Drop PRDs that are pure UI.

3. **Write the area list for Track B.** Eight areas is a good default. Tailor each brief to the project: name the real route files, models, flows and deployment files. The default set:
   - **Authorisation**: every owner-scoped route checks ownership or role on the object it loads, including fragment and partial routes. IDOR through ids in forms and redirects.
   - **Data exposure**: search, feeds, public pages, API reads, exports, notifications, emails, meta tags. Private, draft, hidden, suspended, deleted and blocked data never leaks, including through counts and 404-versus-403 differences.
   - **Untrusted input**: file imports, archive extraction, image decoding, rendered HTML or markdown, every outbound fetch (SSRF to internal ranges, metadata IPs, tailnets, redirects).
   - **Authentication and sessions**: login, lockout, reset, verification, OAuth callbacks, re-authentication, API tokens and scopes, cookie flags, fixation, CSRF on every mutating route, admin actions.
   - **Abuse paths**: invites, requests, messages, reports, any feature that makes the app send email, write endpoints. Rate limits per account and per IP in the deployed proxy topology, and amplification.
   - **Data lifecycle**: account deletion cascades through every model and external store, retention sweeps, export completeness, consent records, against what the privacy policy promises.
   - **Configuration and deployment**: middleware order, headers and CSP, body limits, timeouts, proxy trust, error pages, debug routes, logging of personal data, secrets, database TLS, storage ACLs, CI supply chain.
   - **Recent code**: commits since the last review (`git log --since=<date>`). These usually had a single reviewer.

4. **Confirm scope with the user.** Offer: both tracks full (recommended); both tracks trimmed (Track A only on PRDs changed since the last review plus auth, API and visibility); Track A only; Track B only. Give the rough agent count for each.

5. **Run the workflow.** On Claude Code, run the Mode 10 script in `workflow.md`. On a harness without a Workflow tool, run the same stages directly with subagents, in batches. In both cases:
   - **Extract** (support tier): per PRD, at most `security_max_reqs_per_prd` requirements (default 8), the ones whose failure would hurt users most. Log how many were left out; never drop them silently.
   - **Verify** (advisor tier): three lenses per requirement (exists on every path, tested by a test that would go red, an attacker's edge case). Majority verdict, as in Mode 5.
   - **Mutate** (advisor tier, one agent per PRD in its own worktree): break each PASS guarantee minimally, run its test, restore. A surviving mutation downgrades the requirement to PARTIAL.
   - **Audit** (advisor tier, `security-auditor` agent type where available): one auditor per area, reporting file, line, scenario, evidence and coverage.
   - **Confirm** (advisor tier): three skeptics per finding (reproduce it, show it is reachable in the deployed setup, look for an existing mitigation). A finding survives only if at least two confirm. Skeptics default to not confirmed.
   - **Critics** (advisor tier): one over the Track A verdicts (Mode 5 step 4), one over Track B coverage that lists data-holding routes no auditor examined, spot-checking the most sensitive.

   Every agent prompt carries the same ground rules: read-only except the mutation agents, never commit, never edit `prds/`, never contact production or use production credentials, run tests narrowly, cite file and line.

   **After the workflow returns, before anything else:** run `git status` in the main working tree and `git worktree list`. Mutation agents are told to restore their edits and to work only in their own worktree, but on the first run one left a weakened check in the main tree (`canRequestManage = true`). Revert any such change with `git checkout -- <file>` after reading the diff, and never commit until the tree matches the reviewed commit.

   Expect the skeptics to be too agreeable. On the first run all 49 findings were confirmed. The confirmation stage does not prove a finding is real; the failing test written in step 7 does.

6. **Write the report.** Save to `prds/verification.md` (replace the previous report, which stays in git history) with:
   - a confirmed-findings table ranked by severity: area, severity, finding, file and line, scenario;
   - findings the skeptics rejected, one line each with the reason, so a later review does not rediscover them;
   - the Track A table: requirement, verdict, notes, with survived mutations called out;
   - critic gaps and uncovered routes;
   - what was out of scope or capped.

   Commit it.

7. **Handle gaps.** Same choices as Mode 5 step 7. Fix tasks go into `prds/TASKS.md` as a new phase, most severe first. Each HIGH task gets its reproduction from the confirming skeptic as the acceptance criterion, so the worker's failing test reproduces the finding before the fix.

8. **Record patterns.** Append to `progress.md` the classes of problem found (not the individual findings), so the next feature in that class is built right.

### After the fixes

Fixes from this mode go through Mode 4 as usual, with the advisor review. For each HIGH fix, a separate reviewer runs its own mutations against the fix. In practice that second reviewer finds what the fixer's own tests missed.
