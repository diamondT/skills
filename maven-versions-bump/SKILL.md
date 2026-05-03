---
name: maven-versions-bump
description: >
  End-to-end automated dependency upgrade for a Spring Boot Maven project: branch off `next`
  or `release/x.y.z`, bump Spring Boot (patch automatically, minor or major asks first), run
  `mvn versions:update-properties`, revert any pre-release bumps that did not start as pre-
  release, build with `mvn clean package` (auto-fixing pedantic-pom-enforcer failures where
  possible), commit with `⬆️ version upgrades`, push, open a Bitbucket PR via `bb pr create`,
  wait up to 15 minutes for the PR build, and squash-merge on green. Use this skill whenever
  the user says "upgrade versions", "upgrade dependencies", "bump deps", "upgrade spring
  boot", "version bump", "do the weekly upgrades", or anything resembling a routine
  dependency-bump workflow on a Spring Boot Maven repo. Trigger even if the user does not
  name the skill — this is the canonical upgrade procedure for these projects and ad-hoc
  upgrades are not allowed.
---

# Maven versions bump

Automated dependency-bump workflow for Spring Boot Maven projects. Each step has a guard — stop and ask the user when the guard fails rather than improvise.

## Step 1 — Verify starting branch

The upgrade must branch off either:

- `next` (the rolling development branch), OR
- `release/x.y.z` (a maintenance branch for a released version).

Run:

```bash
git rev-parse --abbrev-ref HEAD
```

- If the result is `next` or matches `release/*`, remember it as `STARTING_BRANCH` and continue.
- Otherwise, **stop and ask** the user:

  > Current branch is `<X>`. The upgrade must start from `next` or a release branch — which one? (e.g. `next` or `release/1.4.0`)

  Wait for the answer, then `git checkout <answer>` and `git pull --ff-only` before continuing. If the user names a branch that does not exist, surface the error rather than guessing.

## Step 2 — Create the upgrade branch

```bash
git checkout -b versions-upgrade
```

If `versions-upgrade` already exists locally or remotely, ask the user whether to delete the stale branch (`git branch -D versions-upgrade` and/or `git push origin --delete versions-upgrade`) before recreating. Don't silently overwrite — a stale branch may contain in-progress work.

## Step 3 — Decide on the Spring Boot upgrade

Read the current Spring Boot parent version from the root `pom.xml` (`<parent><version>...</version>`). Look up the latest stable Spring Boot release:

```bash
curl -s 'https://search.maven.org/solrsearch/select?q=g:org.springframework.boot+AND+a:spring-boot-starter-parent&rows=20&core=gav&wt=json'
```

Skip pre-releases (anything matching `-M*`, `-RC*`, `-SNAPSHOT`, `-alpha*`, `-beta*`, `-CR*`, `-EA`).

Classify the jump from `current` (e.g. `3.4.1`) → candidate target. The upgrade behaviour is:

- **Patch within the current minor** (e.g. `3.4.1` → `3.4.5`, latest stable `3.4.x`): **proceed automatically**. Update the `<version>` in the `<parent>` block.
- **Minor bump** (e.g. `3.4.x` → `3.5.x`): **stop and ask** the user:

  > Spring Boot is at `<current>`. Latest patch in `<current-major.minor>` is `<latest-patch>`. Latest minor is `<latest-minor>`. Apply the patch only, or upgrade to the latest minor? Note that minor upgrades occasionally have behavioural changes — expect to read release notes.

- **Major bump** (e.g. `3.x` → `4.x`): **stop and ask** the user:

  > Spring Boot is at `<current>`. Latest patch in `<current-major.minor>` is `<latest-patch>`. Latest major is `<latest-major>`. Major upgrades typically have breaking changes and migration notes — apply only the patch, or attempt the major upgrade?

For both minor and major, honour the user's answer and apply the version they chose. If they decline the bigger jump, fall back to the latest patch within the current minor (or current major's latest minor, if they chose that). Do not silently apply the largest available bump.

## Step 4 — Bump dependency properties, then revert unsafe pre-releases

Run:

```bash
mvn versions:update-properties -DgenerateBackupPoms=false
```

This rewrites version values inside `<properties>` for every property that is referenced from a `<dependency>` or `<plugin>` and has a newer release on Maven Central.

Then handle pre-release bumps. The rule: revert a property if the **new** value is a pre-release (alpha / beta / M / RC / SNAPSHOT / CR / EA) AND the **old** value was a stable release. Reason: pre-releases are unstable and we don't want them appearing automatically; but if the project was already on a pre-release, the user is intentionally tracking that line and we must not regress them.

Use the bundled script — it handles the diff parsing, the pre-release regex, and the in-place rewrite:

```bash
# Always start with a dry run to see what would change
<skill-dir>/scripts/revert_pre_release_bumps.sh

# When the report looks right, apply it
<skill-dir>/scripts/revert_pre_release_bumps.sh --apply
```

Replace `<skill-dir>` with the absolute path of this skill (the harness will tell you). The script must run from the project root (where `pom.xml` lives) so its `git diff` calls see the working tree.

If the script reports zero reverts, you can skip straight to step 5.

If a `dependencyManagement` entry references a property that was not bumped (Maven could not find a newer release), the property simply stays as-is. Note any such properties to mention to the user at the end — do not invent versions.

### No-op short-circuit

If at this point `git diff` produces no output (Spring Boot was already at the chosen target in step 3, AND `mvn versions:update-properties` found nothing to bump, OR every bump was reverted as a pre-release), the upgrade is a no-op. Don't proceed — there's nothing to build, push, or merge. Clean up and stop:

```bash
git checkout <STARTING_BRANCH>
git branch -D versions-upgrade
```

Then tell the user: everything is already at the latest stable, no PR was opened. (Capital `-D` is fine here even though no commits were made — the branch never diverged.)

## Step 5 — Verify the build

Default:

```bash
mvn clean package
```

Before running this, check the project for build instructions that override the default. In order:

1. `CLAUDE.md` at repo root and any nested `CLAUDE.md` files.
2. `README.md` — look for a "build" or "developer setup" section.
3. `Makefile` / `justfile` — if present, the canonical build target is usually `make build` or `just build`.

If any of those define a different build command (e.g. `mvn -P ci verify`, `make build`, profile activation, env vars), use that instead. Why: some projects gate full verification behind a profile, and `mvn clean package` alone misses the real CI build.

**Per-attempt timeout: 5 minutes (300000 ms).** Pass this to the Bash tool's `timeout` parameter on every build invocation in this step (the default `mvn` retry below `mvn validate` for enforcer fixes counts too). If a build attempt times out, treat it the same as a failure — show the user the partial output and stop. A build that hasn't finished in 5 min on this workflow almost always means a hang (held lock, network stall on a fresh artifact download), not slow compilation; pushing past the timeout rarely helps.

### Handling pedantic-pom-enforcer failures

If the build fails inside `maven-enforcer-plugin` (look for `Rule X failed with message:` or `[ERROR] Failed to execute goal org.apache.maven.plugins:maven-enforcer-plugin`), **try to fix it before stopping**. The common failure modes have deterministic fixes:

- **`dependencyConvergence` / `requireUpperBoundDeps`** — two transitive paths bring in different versions of the same artifact. The fix is to pin the higher of the two in `<dependencyManagement>` (and add a `<version>` property if missing). Use `mvn dependency:tree -Dverbose` to find the conflicting paths; pick the highest version mentioned and add a `dependencyManagement` entry referencing a new `${...}` property.
- **`banDuplicatePomDependencyVersions`** — a property is declared twice or a `<dependency>` has both an inline `<version>` and a `dependencyManagement` entry. Remove the duplicate.
- **`requireSameVersions` (project.groupId)** — sibling modules drifted. Bring them back in line with the parent's version.
- **CompoundPedanticEnforcer / `manageDependencyVersions`** — an inline `<version>` slipped into a `<dependency>` block. Move it into `<dependencyManagement>` and use a property.

After each fix, re-run the build (or just `mvn validate` to retry the enforcer phase). Iterate up to **3 fix attempts**. If after 3 attempts the enforcer is still failing, **stop** and show the user the remaining failure with the diagnosis you've reached so far — at that point the resolution likely needs a human judgment call (e.g. choose between two incompatible upgrades).

### Other build failures

If the build fails for non-enforcer reasons (compile error, test failure, missing class), **stop**. Show the user the error and ask how to proceed. Do not commit a broken upgrade. Common causes worth flagging:

- A bumped dependency introduced an incompatible API change → suggest reverting just that property and trying again.
- A test failure that looks unrelated → re-run once. If it still fails, treat as a real failure.

## Step 6 — Commit, push, open PR

```bash
git add pom.xml
# multi-module projects:
git ls-files '**/pom.xml' | xargs git add
git commit -m "⬆️ version upgrades"
git push -u origin versions-upgrade
bb pr create --title '⬆️ version upgrades' --source versions-upgrade --destination <STARTING_BRANCH>
```

Use the `STARTING_BRANCH` you remembered in step 1 as `--destination`. Do not target `main`/`master` unless that genuinely was the starting branch (it should not be — step 1 only allows `next` or `release/*`).

## Step 7 — Find the PR id

```bash
bb pr list -o json
```

Locate the entry whose source branch is `versions-upgrade`. Capture its id as `PR_ID`. If multiple match, prefer the most recently created.

## Step 8 — Wait for the PR build

```bash
bb pr builds --wait 900 <PR_ID>
```

The `--wait 900` flag blocks for up to 15 minutes (900 s) once a build is actually running.

**The build may not have started yet.** CI typically takes a few seconds to a minute to pick up a new PR push. If the command exits immediately reporting "no builds running" (or anything similar — empty list, "no pipelines found", etc.), wait ~15 s and re-run the same command. Repeat until the command begins blocking — that's the signal CI has picked up the PR and is now actively running. Cap the probe loop at ~5 minutes (≈20 retries); if no build has started by then, stop and ask the user whether CI is misconfigured or simply slow today. Why a probe loop and not a longer single wait: `bb pr builds --wait` only counts down once a build exists, so until then we have nothing to attach to.

Once the command starts blocking, **do not probe further** — let it run to completion. It will return one of:

- **Successful** → continue to step 9.
- **Failed** → stop. Show the user the build output and ask how to proceed (typically: revert specific properties, or skip a known-bad bump).
- **Timed out** (still running after 15 min) → stop and ask the user whether to keep waiting (`bb pr builds --wait 900 <PR_ID>` again) or abandon for now.

## Step 9 — Merge (only if green)

```bash
bb pr merge --message '⬆️ version upgrades' --strategy squash <PR_ID>
```

Only run this when step 8 reported a successful build. Merging on red defeats the purpose of the gate.

## Step 10 — Local cleanup

After a successful merge, the remote `versions-upgrade` branch has already been deleted by the PR merge. Get back to the starting branch with the merge applied, and remove the now-obsolete local branch:

```bash
git fetch origin
git checkout <STARTING_BRANCH>
git pull --ff-only
git branch -D versions-upgrade
```

`-D` (capital) is intentional: the local branch's tip won't appear merged into `<STARTING_BRANCH>` because the PR was squashed, so plain `-d` would refuse. The squash commit on `<STARTING_BRANCH>` already contains the work — discarding the local branch is safe.

Then briefly summarize for the user:
- Starting branch
- Spring Boot version delta (or "unchanged")
- Properties bumped (and properties reverted as pre-release)
- Enforcer fixes applied (if any)
- PR id and merge status

## Edge cases

- **Project uses a non-Bitbucket remote**: the `bb` CLI will fail. If the remote is GitHub/GitLab, stop and ask the user whether to use the equivalent CLI (`gh` / `glab`) — do not silently translate commands.
- **Multi-module projects**: `mvn versions:update-properties` walks the reactor. Diff may touch multiple `pom.xml` files — the bundled `revert_pre_release_bumps.sh` already iterates all `pom.xml` paths in the diff.
