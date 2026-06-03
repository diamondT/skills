---
name: create-pr-and-merge
description: >
  End-to-end "open a Bitbucket PR and then merge it once CI is green" workflow.
  Delegates PR creation to the `create-pr` skill, then waits for the PR build,
  merges on success, and cleans up the local branch. Use this skill whenever the
  user says "create pr and merge", "open a pr and merge it", "create and merge",
  "push and merge my changes", "commit and merge", "ship this", "/create-pr-and-merge",
  or otherwise wants changes committed, pushed, opened as a PR, AND merged after the
  build passes — not just opened. Trigger even if the user does not name the skill.
  This is the canonical create-then-merge procedure for these projects; do not run
  ad-hoc merges. When CI fails or anything is ambiguous, stop and ask rather than improvise.
---

# Create a PR and merge it on green

This skill opens a Bitbucket PR and then merges it once CI passes. Creation is delegated wholesale to the `create-pr` skill — this skill only adds the gate-on-CI, merge, and cleanup steps on top. Each step has a guard: stop and ask the user when a guard fails rather than improvise. **Never force push.**

## Step 1 — Create the PR (delegate to `create-pr`)

Run the **`create-pr`** skill to commit, branch, push, and open the Bitbucket PR. Follow it exactly as written — do **not** reimplement any of the commit/branch/push/`bb pr create` logic here; that skill owns it.

When `create-pr` finishes, capture four values you'll need downstream. Don't ask the user for these — they're all visible in what `create-pr` just did:

- **`PR_ID`** — the PR number from the `bb pr create` output. If the output doesn't surface it cleanly, fall back to `bb pr list -o json` and take the entry whose source branch is your feature branch (most recently created if several).
- **`COMMIT_MESSAGE`** — the exact commit message `create-pr` produced and the user confirmed: subject, body if any, **and** the `Co-Authored-By:` trailer `create-pr` appends (whatever co-author string it used — don't hardcode one). This whole thing — trailer included — becomes the merge commit message in step 3, so keep it verbatim.
- **`TARGET_BRANCH`** — the PR destination (the `--destination` passed to `bb pr create`, e.g. `main` or `next`). Needed for cleanup.
- **`PR_BRANCH`** — the source feature branch (the `--source`). Needed for cleanup.

If `create-pr` stopped without opening a PR (e.g. no changes to commit), there is nothing to merge — stop here and report why.

## Step 2 — Wait for the PR build

```bash
bb pr builds --wait 900 <PR_ID>
```

The `--wait 900` flag blocks for up to 15 minutes (900 s) **once a build is actually running**, then returns the result. You do not need to poll the result yourself — the command does the waiting.

**The build may not have started yet.** CI takes a few seconds to a minute to pick up a freshly pushed PR, and may be busy with other jobs. If the command exits immediately reporting no build (empty list, "no builds running", "no pipelines found", or similar), wait ~15 s and re-run the *same* command. Repeat until the command begins blocking — that blocking is the signal CI has picked up the PR and is now actively running it. Cap the probe loop at ~5 minutes (≈20 retries); if no build has started by then, stop and ask the user whether CI is misconfigured or just slow today. Why a probe loop instead of one long wait: `bb pr builds --wait` only counts down once a build exists, so until then there is nothing to attach to.

Once the command starts blocking, **stop probing** — let it run to completion. It returns one of:

- **Successful** → continue to step 3.
- **Failed** → **stop.** Show the user the build output and ask how they want to proceed (typically: investigate the failing test, fix on `<PR_BRANCH>`, push again, then re-run this step). Do **not** merge a red PR.
- **Timed out** (still running after 15 min) → stop and ask whether to keep waiting (re-run `bb pr builds --wait 900 <PR_ID>`) or pause for now.

## Step 3 — Merge the PR (only on green)

Merge using the commit message from step 1:

```bash
bb pr merge --message "<COMMIT_MESSAGE>" <PR_ID>
```

Only run this once step 2 reported a **successful** build — merging on red defeats the whole point of the gate.

Because the message carries the `Co-Authored-By:` trailer (and possibly a body), it is **almost always multi-line**. Escape each newline as `\n` and use ANSI-C `$'...'` quoting so the shell expands them back into real newlines in the merge commit:

```bash
# subject + trailer
bb pr merge --message $'P00268-824 - add heartbeat to SSE discount events stream\n\n<CO_AUTHORED_BY_TRAILER>' <PR_ID>

# subject + body + trailer
bb pr merge --message $'P00268-812 - fix coupon calc\n\nApply discount proportionally across products and services.\n\n<CO_AUTHORED_BY_TRAILER>' <PR_ID>
```

`<CO_AUTHORED_BY_TRAILER>` is the literal `Co-Authored-By: …` line `create-pr` put in the commit — copy it verbatim, whatever co-author it names (e.g. `Co-Authored-By: 🤖 Claude Code (claude-opus-4-8)` — note the robot emoji and no email). Don't reconstruct or hardcode it; reuse exactly what step 1 produced.

Why escape: keeping the message on one logical line avoids it being split across shell arguments or tripping on a raw multi-line paste, while `$'...'` turns the `\n` escapes back into genuine newlines so the body and trailer stay properly formatted. Use the message **verbatim** from step 1 — same subject, same body, same trailer. (A genuinely single-line message with no body and no trailer can use plain `"..."` quotes, but with the trailer that case won't occur.)

If `bb pr merge` reports the PR can't be merged (e.g. the target moved, or new review changes are required), **stop and ask** — that's a judgment call for the user, not something to force through.

## Step 4 — Local cleanup

After a successful merge, return to the target branch, bring it up to date (it now contains the merged work), and remove the local feature branch:

```bash
git checkout <TARGET_BRANCH>
git fetch --prune origin
git pull --ff-only
git branch -d <PR_BRANCH>
```

`git fetch --prune` also drops the stale remote-tracking ref if Bitbucket deleted the remote branch on merge. `git branch -d` refuses to delete a branch git doesn't consider merged — and with a squash or merge-commit strategy git won't recognise `<PR_BRANCH>` as merged even though Bitbucket just merged it. In that case the PR merge we confirmed in step 3 is the source of truth, so `git branch -D <PR_BRANCH>` is safe. If `git pull --ff-only` fails because local `<TARGET_BRANCH>` diverged, **stop** and show the user — never `reset --hard` a shared branch without instruction.

Then briefly summarize: PR id, build result, merge status, and that the local branch was cleaned up.

## Reminders

- **Never force push** — not on the feature branch, not on the target. If a step seems to need it, stop and ask.
- **Stop on red, stop when uncertain.** This skill ships code to a shared branch. A short clarifying question is always cheaper than an unwanted merge.
- **Don't duplicate `create-pr`.** All commit/branch/push/PR-open behavior lives in that skill; this one only gates, merges, and cleans up.
- **Non-Bitbucket remote** → the `bb` CLI will fail. If the remote is GitHub/GitLab, stop and ask whether to use `gh`/`glab` rather than silently translating commands.
