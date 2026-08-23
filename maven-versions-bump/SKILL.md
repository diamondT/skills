---
name: maven-versions-bump
description: Upgrade Spring Boot and Maven dependency versions on a branch, build, open a Bitbucket PR, merge on green.
disable-model-invocation: true
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
mvn -B versions:display-parent-updates
```

Look for the new version in the command output. The output will look like this if there is an upgrade available:
```
...
[INFO] The parent project has a newer version:
[INFO]   org.springframework.boot:spring-boot-starter-parent  4.0.7 -> 4.1.0
...
```
If there is no update available, the output will say so, e.g.:
```
...
[INFO] The parent project is the latest version:
[INFO]   org.springframework.boot:spring-boot-starter-parent ......... 4.1.0
...
```

### Pre-releases are skipped — but don't stop there

Skip pre-releases (anything matching `-M*`, `-RC*`, `-SNAPSHOT`, `-alpha*`, `-beta*`, `-CR*`, `-EA`) — they aren't production-ready.

The trap: `display-parent-updates` reports only the single highest version, so one pre-release hides every stable release underneath it. On `4.1.0` the plugin may report `4.2.0-M1`; you correctly skip the milestone, but `4.1.1` may exist and would go unnoticed. So whenever the reported candidate is a pre-release, ask Maven again with the search range narrowed:

```bash
# latest patch within the current minor (e.g. 4.1.x)
mvn -B versions:display-parent-updates -DallowMinorUpdates=false

# latest minor within the current major (e.g. 4.x)
mvn -B versions:display-parent-updates -DallowMajorUpdates=false
```

(`allowMinorUpdates=false` implies `allowMajorUpdates=false`, so the first command really is patch-only.)

Walk down the ladder until a stable version turns up:

1. Narrowed **patch** run reports a stable version → that's the target; patch rules apply (proceed automatically).
2. Otherwise the narrowed **minor** run reports a stable version → that's the target; minor rules apply (ask first).
3. Every run reports only pre-releases, or no update at all → the parent stays put. Say what you skipped and why, e.g. "Spring Boot stays at `4.1.0` — the only newer release is `4.2.0-M1`, a milestone."

Both narrowed runs are cheap, so also use them to fill in `<latest-patch>` / `<latest-minor>` for the questions below.

### Classifying the jump

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

### A reverted property may still have a stable update underneath

Same trap as the parent in step 3: `update-properties` moves each property to the single highest version it can find, so one pre-release masks every stable release below it. A property that went `1.9.3` → `2.0.0-M1` and got reverted looks "already up to date", while `1.9.4` or `1.10.0` may be sitting right there.

So when the script reverted anything, run two narrowed passes — widest first, reverting after each:

```bash
# pass 1 — minor + patch, no major (e.g. 1.9.3 → 1.10.0)
mvn versions:update-properties -DgenerateBackupPoms=false -DallowMajorUpdates=false
<skill-dir>/scripts/revert_pre_release_bumps.sh          # dry run, then --apply

# pass 2 — patch only (e.g. 1.9.3 → 1.9.4)
mvn versions:update-properties -DgenerateBackupPoms=false -DallowMinorUpdates=false
<skill-dir>/scripts/revert_pre_release_bumps.sh          # dry run, then --apply
```

Pass 2 only earns its keep when pass 1's candidate is *also* a pre-release (e.g. `1.10.0-RC1` hiding `1.9.4`). As in step 3, `allowMinorUpdates=false` implies `allowMajorUpdates=false`, so pass 2 really is patch-only.

Two things make this safe to run across the whole reactor instead of property-by-property:

- Each pass recomputes from the value currently in the pom, and a narrower range can never land *lower* than what a wider pass already applied. Properties that reached a stable version in the first run stay put; only the reverted ones move.
- The revert script always diffs against the committed (HEAD) value, so "was this property stable before the upgrade?" stays correctly anchored however many passes you run.

Stop as soon as a pass leaves a property on a stable version. A property still reverted after pass 2 genuinely has no stable release newer than its current value — leave it and mention it in the final summary (e.g. "`foo.version` stays at `1.9.3`; only `2.0.0-M1` is newer"). Don't invent versions.

If a narrowed pass changes nothing and the working tree is otherwise clean, the script exits 2 with "No pom.xml changes detected" — here that means "nothing left to find", not an error.

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

**Per-attempt timeout: 5 minutes (300000 ms).** Pass this to the Bash tool's `timeout` parameter on every build invocation in this step (including any re-run after a fix the user approved — `mvn validate` alone is enough to retry the enforcer phase). If a build attempt times out, treat it the same as a failure — show the user the partial output and stop. A build that hasn't finished in 5 min on this workflow almost always means a hang (held lock, network stall on a fresh artifact download), not slow compilation; pushing past the timeout rarely helps.

### Handling pedantic-pom-enforcer failures

If the build fails inside `maven-enforcer-plugin` (look for `Rule X failed with message:` or `[ERROR] Failed to execute goal org.apache.maven.plugins:maven-enforcer-plugin`), **diagnose it and stop** — do not fix and re-run on your own.

An enforcer failure straight after a version bump is information, not an obstacle: it's the build telling you the new version set is internally inconsistent. Silencing the rule usually buries a real incompatibility that resurfaces at runtime, where it costs far more to find.

Two fixes are off limits, however neatly they'd turn the build green:

- **Never override a version the parent manages.** Not by redefining a parent property (`spring-framework.version`, `jackson-bom.version`, and every other property the Spring Boot parent declares — the list is long and this applies to all of it), and not by any other route. The parent BOM is a set of versions released and tested *together*; pulling one member out of that set desyncs it, and Maven will happily build the result while the mismatch waits to blow up at runtime.
- **Never shadow a parent-managed dependency with a local `<dependencyManagement>` entry.** Same damage, different syntax.

If the tidy-looking fix needs either of those, that's the signal to stop — not the signal to get clever.

Investigate first:

```bash
# who drags in which version, along which path
mvn dependency:tree -Dverbose -Dincludes=<groupId>:<artifactId>

# is this version coming from the parent? (empty/null = not parent-managed)
mvn help:evaluate -Dexpression=<some.version> -q -DforceStdout

# what the parent actually manages
mvn help:effective-pom
```

The question to answer is **which change in this upgrade caused it**. Usually one of:

- `dependencyConvergence` / `requireUpperBoundDeps` — a bumped third-party dependency now wants a newer transitive than the parent manages (or a Spring Boot bump moved a managed version out from under a dependency this project pins). The honest fixes are to bump Spring Boot to a release that manages the newer version, or to hold the offending dependency back at its old value. Both are the user's call, not yours.
- `banDuplicatePomDependencyVersions`, `requireSameVersions`, CompoundPedanticEnforcer's `manageDependencyVersions` — these are local to this project's own pom (a property declared twice, an inline `<version>` that belongs in `<dependencyManagement>`, sibling modules drifted off the parent's version). Nothing parent-managed is involved, so the fix is safe in principle — but still show it before applying; it's a one-line diff and cheap to confirm.

Then stop and report, in this shape:

> `<build command>` failed on `<rule>`: `<message>`. Root cause: `<what conflicts with what, and which bump introduced it>`. Options: (1) `<proposal>`, (2) `<alternative — e.g. revert `foo.version` to `1.9.3`>`. How do you want to proceed?

Wait for the answer, then apply what the user chose. If they pick something that does override a parent-managed version, that's their decision — apply it, and note once what it desyncs.

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

## Step 7 — Merge on green (delegate to `merge-pr`)

The PR already exists (step 6 opened it) — don't reimplement the wait/merge/cleanup logic here. Run the **`merge-pr`** skill (the same skill `create-pr-and-merge` delegates to for its merge half) and hand it what you already have:

- **`PR_ID`** — from the `bb pr create` output in step 6. If it didn't surface cleanly, fall back to `bb pr list -o json` and take the entry whose source branch is `versions-upgrade` (most recently created if several).
- **`COMMIT_MESSAGE`** — `⬆️ version upgrades`, verbatim, for the merge commit message.
- **`TARGET_BRANCH`** — `STARTING_BRANCH` from step 1.
- **`PR_BRANCH`** — `versions-upgrade`.

`merge-pr` waits for the PR build (stopping to ask on red or a stuck build — honour that, don't merge on red), merges once green using `bb`'s default merge strategy, and prunes the local `versions-upgrade` branch back to `STARTING_BRANCH`. Let it own all of that; do not hand-roll `bb pr builds`/`bb pr merge`/cleanup here.

Then briefly summarize for the user:
- Starting branch
- Spring Boot version delta (or "unchanged")
- Properties bumped (and properties reverted as pre-release)
- Enforcer failures hit, and what the user decided (if any)
- PR id and merge status

## Edge cases

- **Project uses a non-Bitbucket remote**: the `bb` CLI will fail. If the remote is GitHub/GitLab, stop and ask the user whether to use the equivalent CLI (`gh` / `glab`) — do not silently translate commands.
- **Multi-module projects**: `mvn versions:update-properties` walks the reactor. Diff may touch multiple `pom.xml` files — the bundled `revert_pre_release_bumps.sh` already iterates all `pom.xml` paths in the diff.
