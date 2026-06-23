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

This skill opens a Bitbucket PR and then merges it once CI passes. It is a thin orchestrator over two skills that each own a half: creation is delegated wholesale to the `create-pr` skill, and the gate-on-CI/merge/cleanup half is delegated wholesale to the `merge-pr` skill. This skill's only real job is to run them in order and hand the values from the first across to the second. Each step has a guard: stop and ask the user when a guard fails rather than improvise. **Never force push.**

## Step 1 — Create the PR (delegate to `create-pr`)

Run the **`create-pr`** skill to commit, branch, push, and open the Bitbucket PR. Follow it exactly as written — do **not** reimplement any of the commit/branch/push/`bb pr create` logic here; that skill owns it.

When `create-pr` finishes, capture four values you'll need downstream. Don't ask the user for these — they're all visible in what `create-pr` just did:

- **`PR_ID`** — the PR number from the `bb pr create` output. If the output doesn't surface it cleanly, fall back to `bb pr list -o json` and take the entry whose source branch is your feature branch (most recently created if several).
- **`COMMIT_MESSAGE`** — the exact commit message `create-pr` produced and the user confirmed: subject, body if any, **and** the `Co-Authored-By:` trailer `create-pr` appends (whatever co-author string it used — don't hardcode one). This whole thing — trailer included — is handed to `merge-pr` in step 2 to become the merge commit message, so keep it verbatim.
- **`TARGET_BRANCH`** — the PR destination (the `--destination` passed to `bb pr create`, e.g. `main` or `next`). Needed for cleanup.
- **`PR_BRANCH`** — the source feature branch (the `--source`). Needed for cleanup.

If `create-pr` stopped without opening a PR (e.g. no changes to commit), there is nothing to merge — stop here and report why.

## Step 2 — Merge on green (delegate to `merge-pr`)

Run the **`merge-pr`** skill to wait for the PR build, merge once it's green, and clean up the local branch. Follow it exactly as written — do **not** reimplement any of the `bb pr builds`/`bb pr merge`/cleanup logic here; that skill owns it.

`merge-pr` works standalone by discovering the PR's details, but you already captured everything it needs in step 1, so hand those four values straight across instead of making it re-derive them:

- **`PR_ID`** → the PR to merge.
- **`COMMIT_MESSAGE`** → the merge commit message, **verbatim** — same subject, same body, same `Co-Authored-By:` trailer `create-pr` produced. This is the important hand-off: passing it through keeps the merge commit faithful to the commit, trailer and all, rather than letting it be reconstructed from the PR.
- **`TARGET_BRANCH`** → the merge destination, for cleanup.
- **`PR_BRANCH`** → the source feature branch, for cleanup.

`merge-pr` stops on a red or stuck build and asks rather than improvising; honour that — do **not** merge a PR whose build isn't green. When it finishes, it will have merged the PR and pruned the local branch, and reported the PR id, build result, and merge status.

## Reminders

- **Never force push** — not on the feature branch, not on the target. If a step seems to need it, stop and ask.
- **Stop on red, stop when uncertain.** This skill ships code to a shared branch. A short clarifying question is always cheaper than an unwanted merge.
- **Don't duplicate the skills you delegate to.** All commit/branch/push/PR-open behaviour lives in `create-pr`; all wait/merge/cleanup behaviour lives in `merge-pr`. This skill only sequences the two and carries the step-1 values across to step 2.
- **Non-Bitbucket remote** → the `bb` CLI will fail. If the remote is GitHub/GitLab, stop and ask whether to use `gh`/`glab` rather than silently translating commands.
