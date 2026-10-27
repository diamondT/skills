---
name: independent-review
description: "Review your own changes in a fresh subagent"
disable-model-invocation: true
---

# Delegated review / Independent review

Your own review of code you just wrote is biased by what you meant it to do. A fresh subagent sees only the code, so it catches what you can't. But it can be confidently wrong, and it doesn't know about decisions the user already made. So the work splits in two: **the subagent finds problems, you judge them.** You fix only what you've confirmed yourself.

## 1. Scope the review

Work out these before you spawn anything:

- **Target repo**: the absolute path of the repo with the changes. It may be a sibling repo, not the current working directory.
- **Fixed point**: what the user gave you. Otherwise the branch the work came from.
- **What's in the diff**: run `git status --short` and `git diff --stat <fixed-point>`. Uncommitted and untracked files count. `review-code` only falls back to uncommitted changes when it gets no fixed point, so list the files explicitly.
- **Intent and settled decisions**: what the change is for, and choices the user made in this session (e.g. "ATG mode is out of scope", "marketplace offers deliberately skipped"). Without these the reviewer flags settled choices as defects.

## 2. Spawn the reviewer

Spawn one `general-purpose` subagent. Its prompt is the only context it gets, so make it complete, and leave out your opinion of the code. Telling it what you think is fine tends to get that confirmed. Template:

```
Use the Skill tool to invoke the `review-code` skill and follow its instructions to review changes
in the repo at <ABS_REPO_PATH> (<stack, e.g. Java 25 / Spring WebFlux / Maven>).
Fixed point: `<FIXED_POINT>` (current branch `<BRANCH>`). <If uncommitted:> The changes are
UNCOMMITTED — review the working tree vs `<FIXED_POINT>`, including untracked files:
- <status> <path>
- ...

Intent: <one paragraph: what the change does and why>.
Deliberate decisions (do not flag as defects): <list>.
Org conventions: the `<conventions-skill>` skill (<2-3 key rules>).

Do NOT edit any files and do NOT commit — read-only review. You may run targeted tests
(<e.g. `mvn -B -q test -Dtest=...` / `bun run test -- <file>`>) if useful.
Return a concise list of findings, each with: severity (High/Med/Low), file:line, what's wrong,
concrete failure scenario, and suggested fix. Say explicitly if you find nothing significant.
```

Tell the user in one line that the review is running, then wait for the notification. Don't review the same files in parallel yourself: it wastes tokens, and you'd anchor on your own reading before seeing the independent one.

## 3. Verify every finding

Treat the report as claims to check. Neither accept nor dismiss a finding without reading the code it points at. For each one, open the cited lines, follow the code path or grep for the evidence, and put it in one of these buckets:

- **Confirmed**: the problem is real and the scenario can happen. Fix it.
- **Valid trade-off**: a fair point, but it depends on a product or design decision you can't make (cost vs coverage, a scope the user set). Don't fix it. Explain why and leave it for the user.
- **Refuted**: the code already handles it, the scenario can't happen, or the finding misreads the code. Say what disproves it.

Check facts, not plausibility. "No timeout on the client" is checked by reading the HTTP client config. "This mock isn't strict" is checked by how and where the mock is created. If a finding conflicts with a decision the user made, that decision wins. Note the finding as a trade-off.

## 4. Fix confirmed findings

- Change only what the finding needs, with no drive-by cleanup.
- Add or adjust a test for every fix (timeout → virtual-time test, error branch → error test, etc.).
- When a fix makes the tooling stricter (strict mocks, stronger types), let it fail first and fix what it reports. Those failures are often real mismatches the loose version was hiding.

## 5. Re-run the full checks

Run the target repo's complete checks, not only the touched tests.

If something fails, fix it and run the checks again. Report anything left failing, with its output.

## 6. Report

Keep it short. Use this structure:

```
Review back: <one line — e.g. "no Critical/High">. Verified each against code:

| # | Finding | Check | Action |
|---|---|---|---|
| 1 | <short title> | Confirmed — <evidence> | Fixed: <what + test> |
| 2 | <short title> | Valid trade-off — <why> | Not changed: <reason> |
| 3 | <short title> | Refuted — <evidence> | None |

<check results: e.g. "`mvn verify` green, 596 tests; JaCoCo 0 missed branches on changed classes">.
Uncommitted on `<branch>`.

Unresolved:
- <very short question per open trade-off>
```
