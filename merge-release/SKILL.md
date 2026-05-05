---
name: merge-release
description: >
  End-to-end automated merge of a `release/x.y.z` branch back into `next` (the rolling
  development branch). Identifies the release branch (asking the user if ambiguous),
  refreshes both `next` and the release branch, creates a `merge-release` integration
  branch, performs a `--no-ff` merge with the canonical commit message, runs the full
  build+tests, pushes, opens a Bitbucket PR, waits for CI, fast-forward-merges on green,
  and cleans up. Use this skill whenever the user says "merge release", "merge release
  into next", "release back-merge", "fold release into next", "/merge-release", or any
  phrasing about reintegrating a release branch back into the development line. Trigger
  even if the user does not name the skill — this is the canonical procedure for these
  projects and ad-hoc release back-merges are not allowed. NEVER force push at any step.
  When uncertain, pause and ask the user rather than improvise.
---

# Merge release back into next

Reintegrates a `release/x.y.z` branch into `next` via an integration branch and a Bitbucket PR. Each step has a guard — stop and ask the user when the guard fails rather than improvise. **Never force push anything**, at any step, for any reason.

## Step 1 — Identify the release branch

Fetch first so the local view of remotes is current:

```bash
git fetch --prune origin
```

Then list candidate release branches (both local and remote):

```bash
git branch -a --list '*release/*'
```

Filter to entries matching `release/x.y.z` (semantic version, three numeric parts). Strip the `remotes/origin/` prefix and de-duplicate against local copies.

- **Exactly one match** → that is `RELEASE_BRANCH` (e.g. `release/1.4.0`). Continue.
- **Zero matches** → stop and ask:

  > No `release/x.y.z` branch found locally or on origin. Which branch should I merge into `next`?

- **Multiple matches** → stop and ask, listing them:

  > Found multiple release branches: `release/1.3.0`, `release/1.4.0`. Which one should I merge into `next`?

Wait for the answer before continuing. Do not pick "the highest version" silently — the user may be back-merging an older maintenance release intentionally.

## Step 2 — Refresh `next`

```bash
git checkout next
git pull --ff-only
```

If `git pull --ff-only` fails (local `next` has diverged from origin), **stop**. Show the user the divergence and ask how to proceed — never `git reset --hard` or force-update without explicit instruction. A diverged `next` usually means someone has work in progress locally.

## Step 3 — Create the integration branch

```bash
git checkout -b merge-release
```

If `merge-release` already exists locally or on origin, **stop and ask** the user whether to delete the stale branch (`git branch -D merge-release` and/or `git push origin --delete merge-release`) before recreating. Don't silently overwrite — a stale branch may contain in-progress work from a previous attempt.

## Step 4 — Refresh the release branch, then merge

Make sure the release branch is at its origin tip before merging — otherwise we may merge a stale snapshot:

```bash
# checkout the release branch and bring it up to date
git checkout <RELEASE_BRANCH>
git pull --ff-only
git checkout merge-release
```

If `git pull --ff-only` on the release branch fails (local copy diverged from origin), **stop and ask**. The release branch is shared infrastructure — never reset it without explicit instruction.

Now perform the merge:

```bash
git merge --no-ff <RELEASE_BRANCH> -m "merge <RELEASE_BRANCH> into next"
```

Replace `<RELEASE_BRANCH>` literally in the commit message (e.g. `merge release/1.4.0 into next`). The `--no-ff` is intentional — it preserves the merge as a discrete commit so the back-merge is visible in history.

### Resolving merge conflicts

If the merge stops with conflicts, **do not just resolve text**. The whole point of a back-merge is to bring the release's bug fixes into `next` without losing `next`'s newer development. So for each conflict:

1. Read both sides (`<<<<<<< HEAD` is `next`, `=======` then `>>>>>>> <RELEASE_BRANCH>` is the release).
2. Use `git log --oneline <RELEASE_BRANCH> ^next -- <file>` to see what the release branch changed and why.
3. Use `git log --oneline next ^<RELEASE_BRANCH> -- <file>` to see what `next` changed and why.
4. Identify the **functionality** each side is trying to express — a hotfix on the release line, a refactor on `next`, an API change, a config edit, etc.
5. Resolve so that **both pieces of functionality are preserved**. A textual choice of one side often silently drops a fix; that's the failure mode this step exists to prevent.

If after reading the history you genuinely cannot tell what the right resolution is — for example, the two sides have semantically incompatible changes to the same function — **stop and ask the user**, showing both versions and your understanding of each. Do not guess.

After resolving:

```bash
git add <resolved files>
git commit  # picks up the prepared "merge <RELEASE_BRANCH> into next" message
```

Briefly summarize for the user which files conflicted and how each was resolved (functionally, not just "took both sides"). This summary is part of the deliverable — it goes into the PR description in step 6.

## Step 5 — Build and test

Detect the build system and the right command. In order:

1. **Project-specific overrides.** Check for build instructions in:
   - `CLAUDE.md` at repo root, and any nested `CLAUDE.md` files
   - `README.md` — look for "build", "test", or "developer setup" sections
   - `Makefile` / `justfile` — common targets are `make build` / `just build`, `make test` / `just test`

   If any of those define the canonical build+test command, use that instead of the defaults below.

2. **Maven default** — if `pom.xml` is at the repo root and no override was found:

   ```bash
   mvn clean package
   ```

   `package` runs the test phase by default unless `-DskipTests` is set, so this is build+test in one go.

3. **Next.js / Node default** — if `package.json` is at the repo root and no override was found:

   ```bash
   npm run build
   npm test
   ```

   Run them sequentially. If `npm test` is not defined in `package.json` `scripts`, note it and tell the user — do not silently skip tests.

4. **Other / unknown** — if the project is neither Maven nor Node, **stop and ask** the user how to build and test. Don't guess.

**Per-attempt timeout: 10 minutes (600000 ms).** Pass this to the Bash tool's `timeout` parameter for build commands. A back-merge build that hasn't finished in 10 min is almost always a hang (held lock, network stall) rather than slow compilation.

If the build fails:

- **Test failure caused by the merge** (e.g. behavior diverged, the resolution dropped something) → revisit step 4. Re-read the conflict resolution; the failing test is usually pointing at the dropped functionality.
- **Test failure that looks unrelated** → re-run once. If it still fails, treat as a real failure and stop.
- **Compile error** → almost always a merge resolution issue (import dropped, signature mismatch). Re-examine.

In all cases, **stop on red**. Never push a known-broken merge: the PR build will reject it anyway, and pushing wastes a CI cycle.

## Step 6 — Push and open the PR

```bash
git push -u origin merge-release
bb pr create --title 'merge <RELEASE_BRANCH> into next' --source merge-release --destination next
```

Substitute `<RELEASE_BRANCH>` in the title (e.g. `merge release/1.4.0 into next`).

Capture the PR id from the `bb pr create` output as `PR_ID`. If the output doesn't surface it cleanly, fall back to:

```bash
bb pr list -o json
```

and find the entry whose source branch is `merge-release` (most recently created if multiple).

## Step 7 — Wait for the PR build

```bash
bb pr builds --wait 900 <PR_ID>
```

The `--wait 900` flag blocks for up to 15 minutes (900 s) once a build is actually running.

**The build may not have started yet.** CI typically takes a few seconds to a minute to pick up a new PR push. If the command exits immediately reporting "no builds running" (or anything similar — empty list, "no pipelines found"), wait ~15 s and re-run the same command. Repeat until the command begins blocking — that's the signal CI has picked up the PR and is now actively running. Cap the probe loop at ~5 minutes (≈20 retries); if no build has started by then, stop and ask the user whether CI is misconfigured or simply slow today. Why a probe loop and not a longer single wait: `bb pr builds --wait` only counts down once a build exists, so until then we have nothing to attach to.

Once the command starts blocking, **do not probe further** — let it run to completion. It will return one of:

- **Successful** → continue to step 8.
- **Failed** → stop. Show the user the build output and ask how to proceed (typically: investigate which test failed, fix on `merge-release`, push again, re-wait). Do not merge a red PR.
- **Timed out** (still running after 15 min) → stop and ask the user whether to keep waiting (`bb pr builds --wait 900 <PR_ID>` again) or abandon for now.

## Step 8 — Merge the PR (only if green)

```bash
bb pr merge --strategy fast_forward --message 'merge <RELEASE_BRANCH> into next' <PR_ID>
```

Substitute `<RELEASE_BRANCH>` in the message. Fast-forward is the right strategy here: the integration branch already contains the merge commit (from step 4's `--no-ff`), and we want that exact commit to land on `next` unchanged. A squash or three-way merge would obscure or duplicate the back-merge structure.

Only run this when step 7 reported a successful build. Merging on red defeats the purpose of the gate.

If `bb pr merge` reports the PR can't be fast-forwarded (someone else moved `next` while the build ran), **stop and ask**. The fix is usually to re-merge `next` into `merge-release` and re-run from step 5 — but that's a judgment call the user should make.

## Step 9 — Local cleanup

After a successful merge, the remote `merge-release` branch has already been deleted by the PR merge. Get back to `next` with the merge applied, and remove the local integration branch:

```bash
git fetch origin
git checkout next
git pull --ff-only
git branch -d merge-release
```

Lowercase `-d` is correct: with `fast_forward` the merge commit on `next` is exactly the tip of `merge-release`, so the local branch is "merged" by git's reckoning and `-d` will succeed. If `-d` refuses, something unexpected happened — stop and investigate rather than escalating to `-D`.

Then briefly summarize for the user:
- Release branch merged
- Files that conflicted and how each was resolved (functionally)
- Build result
- PR id and merge status

## Edge cases

- **Project uses a non-Bitbucket remote** — the `bb` CLI will fail. If the remote is GitHub/GitLab, stop and ask the user whether to use the equivalent CLI (`gh` / `glab`) — do not silently translate commands.
- **No `next` branch exists** — stop and ask. Some projects use `develop` or `main` as the development line; the user must confirm the target.
- **`bb pr merge --strategy fast_forward` not supported by the bb CLI version** — surface the error to the user. Do not silently substitute another strategy; the choice of strategy is part of the contract here.
- **The release branch is already fully merged into `next`** — `git merge` will report "Already up to date." and produce no commit. In that case there is nothing to PR. Clean up: `git checkout next && git branch -D merge-release`, then tell the user nothing was merged because the release was already integrated.

## Reminders

- **Never force push.** Not on `merge-release`, not on `next`, not on the release branch — never. If a step seems to require force pushing, stop and ask first; there is almost always a non-destructive alternative.
- **When uncertain, pause and ask.** This workflow touches shared branches and ships code. A short clarifying question is always cheaper than an unintended merge.
