---
name: upgrade-deps
description: Upgrade all dependencies in package.json to their latest stable versions. Use when user asks to upgrade dependencies, update packages, bump versions, or check for outdated packages. Triggers on requests like "upgrade deps", "update dependencies", "bump packages", "upgrade all", "check outdated". Skips alpha, beta, rc, snapshot, canary, and other pre-release versions.
---

# Upgrade All Dependencies

Automated workflow for upgrading all dependencies in package.json to latest stable versions with verification.

## Workflow

### 1. Verify Project

Check working directory contains a Node.js project:

```bash
test -f package.json
```

If not found, inform user this is not a Node.js project and stop.

### 2. Gather Current Versions

Read package.json and extract ALL packages from both `dependencies` and `devDependencies`. For each package, parse the current version number (strip `^`, `~`, etc.).

```bash
node -e "
const pkg = require('./package.json');
const deps = { ...pkg.dependencies, ...pkg.devDependencies };
Object.entries(deps).forEach(([name, ver]) => {
  const clean = ver.replace(/[\^~>=<\s]/g, '');
  console.log(name + '@' + clean);
});
"
```

### 3. Check Available Versions

For EACH package, query npm for available versions.

**Get latest stable version** (exclude alpha, beta, rc, snapshot, canary, next, dev, pre, experimental tags):

```bash
npm view <PACKAGE> versions --json 2>/dev/null | jq -r '.[]' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | tail -1
```

The `grep -E '^[0-9]+\.[0-9]+\.[0-9]+$'` filter ensures ONLY stable semver versions (no pre-release suffixes).

**Get latest patch in current minor** (for patch-only upgrades):

```bash
npm view <PACKAGE> versions --json 2>/dev/null | jq -r '.[]' | grep -E '^MAJOR\.MINOR\.[0-9]+$' | tail -1
```

Replace `MAJOR.MINOR` with the package's current major.minor.

**Important**: Run these checks in parallel batches (5-10 at a time) using background processes to avoid waiting for each one sequentially.

```bash
for pkg in pkg1 pkg2 pkg3; do
  (echo "$pkg:$(npm view "$pkg" versions --json 2>/dev/null | jq -r '.[]' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' | tail -1)") &
done
wait
```

### 4. Classify Upgrades

For each package, determine:
- **Up to date**: current == latest stable → skip
- **Patch available**: latest patch in current minor > current patch
- **Minor/Major available**: latest stable > current, different minor or major

Build a summary table showing: package name, current version, latest patch, latest stable, upgrade type.

### 5. Next.js Special Handling

If `next` is among the packages, handle it with the same dialog as the nextjs-upgrade skill:

- **Only patch available**: Proceed automatically
- **Only minor/major available**: Ask user to confirm
- **Both available**: Ask user which upgrade (patch only / full / both sequentially)

This determines the Next.js target version. React, react-dom, @types/react, @types/react-dom follow Next.js's chosen upgrade path (they are part of the Next.js ecosystem).

### 6. User Confirmation for Remaining Dependencies

For ALL other dependencies (excluding next, react, react-dom, @types/react, @types/react-dom which follow step 5), ask the user ONE question using AskUserQuestion:

- **Option 1: Patch only** — upgrade each package to latest patch within its current minor (safest)
- **Option 2: Full upgrade** — upgrade each package to latest stable version (may include minor/major bumps)
- **Option 3: Skip** — only upgrade Next.js ecosystem (from step 5), leave others unchanged

Display the summary table so the user can see what will change before choosing.

If there are no other dependencies to upgrade (all up to date), skip this question.

### 7. Upgrade Process

#### 7.1 Create Branch

```bash
git checkout -b version-upgrades
```

If branch exists, checkout existing branch.

#### 7.2 Upgrade Dependencies

Based on user choices from steps 5 and 6, build the install commands.

Separate into `dependencies` and `devDependencies` based on where each package originally lived in package.json.

Install production deps:

```bash
npm install --save-exact <pkg1>@<VER1> <pkg2>@<VER2> ...
```

Install dev deps:

```bash
npm install --save-exact -D <pkg3>@<VER3> <pkg4>@<VER4> ...
```

Use `--save-exact` to avoid caret prefixes. Install in batches if the command line gets too long.

#### 7.3 Verify Build

```bash
npm run build
```

Build must succeed. If fails, report error and stop.

#### 7.4 Verify Tests

```bash
npm test
```

All tests must pass. If fails, report error and stop.

#### 7.5 Commit Changes

```bash
git add package.json package-lock.json
git commit -m "$(cat <<'EOF'
⬆️ upgrade project dependencies

Co-Authored-By: Claude 🤖
EOF
)"
```

#### 7.6 Push & Report

```bash
git push -u origin version-upgrades 2>&1
```

Read push output, extract PR URL from remote response, and report to user.

Present a final summary table: package, old version → new version.

## Error Handling

- If build fails: Report build errors, suggest fixes if obvious
- If tests fail: Report failing tests, do not commit
- If push fails: Check if branch exists remotely, suggest `git pull` or force push confirmation
- If npm view fails for a package (private/scoped): Skip that package and note it in the report
- If a package has no stable versions matching the filter: Skip and note it
