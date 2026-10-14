---
name: merge-pr
description: >
  Merge an open Bitbucket PR. Use this skill whenever the user says "merge pr", "merge PR 73",
  "/merge-pr".
---

# Merge a Bitbucket PR on green

This skill takes a pull request that already exists, waits for its CI build, merges it once the build is green, and cleans up the local branch. It is the merge half of `create-pr-and-merge`, extracted so it can also be run on its own against any open PR. Each step has a guard: stop and ask the user when a guard fails rather than improvise. **Never force push.**

## Inputs

The skill needs four values. When a caller delegates to this skill (e.g. `create-pr-and-merge` right after `create-pr`), it passes them in — use those verbatim, don't re-derive. When invoked standalone, discover them from the PR itself; don't ask the user for what `bb` can tell you.

- **`PR_ID`** — the PR number. If the user named one ("merge PR 73"), use it. If a caller passed it, use that. Otherwise run `bb pr list -o json` and pick the entry whose source branch is the current local branch (most recently created if several); if that's ambiguous, show the list and ask.
- **`COMMIT_MESSAGE`** — the message the merge commit should carry: subject, optional body. If a caller passed the exact message its commit used, reuse it verbatim — that keeps the merge commit faithful to the work. Standalone, reconstruct it from the PR's source-branch HEAD commit (`git log -1 <PR_BRANCH>` once fetched, or the PR's commit list via `bb`), preserving the original subject, body.
- **`TARGET_BRANCH`** — the PR destination (e.g. `main` or `next`). A caller passes the `--destination` it used; standalone, read it from `bb pr view <PR_ID> -o json` (the destination branch). Needed for cleanup.
- **`PR_BRANCH`** — the PR source (feature) branch. A caller passes the `--source`; standalone, read it from `bb pr view <PR_ID> -o json`. Needed for cleanup.
- **`WORKSPACE`** / **`REPO_SLUG`** — only in a worktree (see below). Use the caller's values if passed; standalone, derive them as described in "bb in a worktree".

If there is no open PR to act on, there is nothing to merge — stop and report that.

## bb in a worktree

`bb` reads the Bitbucket workspace and repo from `./.git/config`. In a git worktree `.git` is a file, so `bb` fails with `missing required field: workspace`. Check:

```bash
git rev-parse --path-format=absolute --git-dir --git-common-dir
```

If the two lines differ, you're in a worktree. Derive `WORKSPACE` / `REPO_SLUG` from `git remote get-url origin`: drop a trailing `.git`, split on `/` and `:` — the last two segments are `<WORKSPACE>` and `<REPO_SLUG>` (e.g. `git@bitbucket.org:acme/shop.git` or `https://user@bitbucket.org/acme/shop` → `acme`, `shop`). Then add `-w <WORKSPACE> -r <REPO_SLUG>` after the subcommand on **every** `bb` call (`bb pr create -w acme -r shop …`) — they're subcommand options, not global ones. Write the literal values; shell variables don't persist between calls.

Here that means `bb pr list`, `bb pr view`, `bb pr builds` and `bb pr merge`.

## Step 1 — Wait for the PR build

```bash
bb pr builds --wait 900 <PR_ID>
```

The `--wait 900` flag blocks for up to 15 minutes (900 s) **once a build is actually running**, then returns the result. You do not need to poll the result yourself — the command does the waiting.

**The build may not have started yet.** CI takes a few seconds to a minute to pick up a freshly pushed PR, and may be busy with other jobs. If the command exits immediately reporting no build (empty list, "no builds running", "no pipelines found", or similar), wait ~15 s and re-run the *same* command. Repeat until the command begins blocking — that blocking is the signal CI has picked up the PR and is now actively running it. Cap the probe loop at ~5 minutes (≈20 retries); if no build has started by then, stop and ask the user whether CI is misconfigured or just slow today. Why a probe loop instead of one long wait: `bb pr builds --wait` only counts down once a build exists, so until then there is nothing to attach to.

Once the command starts blocking, **stop probing** — let it run to completion. It returns one of:

- **Successful** → continue to step 2.
- **Failed** → **stop.** Show the user the build output and ask how they want to proceed (typically: investigate the failing test, fix on `<PR_BRANCH>`, push again, then re-run this step). Do **not** merge a red PR.
- **Timed out** (still running after 15 min) → stop and ask whether to keep waiting (re-run `bb pr builds --wait 900 <PR_ID>`) or pause for now.

## Step 2 — Merge the PR (only on green)

Merge using the commit message from the inputs:

```bash
bb pr merge --message "<COMMIT_MESSAGE>" <PR_ID>
```

Only run this once step 1 reported a **successful** build — merging on red defeats the whole point of the gate.

Because the message possible carries a body, it is **almost always multi-line**. Escape each newline as `\n` and use ANSI-C `$'...'` quoting so the shell expands them back into real newlines in the merge commit:

```bash
# subject
bb pr merge --message $'P00268-824 - add heartbeat to SSE discount events stream' <PR_ID>

# subject + body
bb pr merge --message $'P00268-812 - fix coupon calc\n\nApply discount proportionally across products and services.' <PR_ID>
```

Why escape: keeping the message on one logical line avoids it being split across shell arguments or tripping on a raw multi-line paste, while `$'...'` turns the `\n` escapes back into genuine newlines so the body and trailer (if any) stay properly formatted. Use the message **verbatim** — same subject, same body, same trailer (if any). (A genuinely single-line message with no body and no trailer can use plain `"..."` quotes, but with the trailer that case won't occur.)

If `bb pr merge` reports the PR can't be merged (e.g. the target moved, or new review changes are required), **stop and ask** — that's a judgment call for the user, not something to force through.

## Step 3 — Local cleanup

After a successful merge, return to the target branch, bring it up to date (it now contains the merged work), and remove the local feature branch:

```bash
git checkout <TARGET_BRANCH>
git fetch --prune origin
git pull --ff-only
git branch -d <PR_BRANCH>
```

`git fetch --prune` also drops the stale remote-tracking ref if Bitbucket deleted the remote branch on merge. `git branch -d` refuses to delete a branch git doesn't consider merged — and with a squash or merge-commit strategy git won't recognise `<PR_BRANCH>` as merged even though Bitbucket just merged it. In that case the PR merge we confirmed in step 2 is the source of truth, so `git branch -D <PR_BRANCH>` is safe. If `git pull --ff-only` fails because local `<TARGET_BRANCH>` diverged, **stop** and show the user — never `reset --hard` a shared branch without instruction.

**In a worktree** (see "bb in a worktree"), `git checkout <TARGET_BRANCH>` usually fails — the main repo has it checked out. Remove the worktree and clean up from the main repo instead:

```bash
git rev-parse --path-format=absolute --git-common-dir   # <MAIN> = parent dir of this
git rev-parse --show-toplevel                           # <WORKTREE>
cd <MAIN>                      # first — the session cwd is inside the worktree being removed
git worktree remove <WORKTREE>
git fetch --prune origin
git pull --ff-only             # if <TARGET_BRANCH> is checked out in <MAIN>
git fetch origin <TARGET_BRANCH>:<TARGET_BRANCH>   # otherwise (fast-forward only)
git branch -d <PR_BRANCH>
```

Never `git worktree remove --force`: if it refuses (modified or untracked files), stop and ask. If the `<TARGET_BRANCH>` sync is refused (diverged, or checked out in yet another worktree), report it and leave it — don't force. The `-d`/`-D` rule above applies unchanged.

Cleanup only makes sense when `<PR_BRANCH>` exists locally (it always does when delegated mid-session right after `create-pr`). If you merged a PR that was never checked out locally, there's no local branch to prune — skip what doesn't apply and just sync `<TARGET_BRANCH>`.

Then briefly summarize: PR id, build result, merge status, and that the local branch was cleaned up.

## Reminders

- **Never force push** — not on the feature branch, not on the target. If a step seems to need it, stop and ask.
- **Stop on red, stop when uncertain.** This skill ships code to a shared branch. A short clarifying question is always cheaper than an unwanted merge.
- **This skill does not create PRs.** It acts on a PR that already exists. If the user actually wants to commit/push/open *and* merge, that's `create-pr-and-merge` (which delegates here for the merge half).
- **Non-Bitbucket remote** → the `bb` CLI will fail. If the remote is GitHub/GitLab, stop and ask whether to use `gh`/`glab` rather than silently translating commands.
