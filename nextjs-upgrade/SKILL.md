---
name: nextjs-upgrade
description: Upgrade Next.js and React dependencies in a project. Use when user asks to upgrade Next.js, update Next.js version, or check for Next.js updates. Triggers on requests like "upgrade nextjs", "update next version", "check next updates", "bump nextjs". Also upgrades react, react-dom, @types/react, @types/react-dom.
---

# Next.js Upgrade

Automated workflow for upgrading Next.js and React dependencies with verification.

## Workflow

### 1. Verify Next.js Project

Check working directory contains a Next.js project:

```bash
test -f package.json && grep -q '"next"' package.json
```

If not found, inform user this is not a Next.js project and stop.

### 2. Check Current & Available Versions

Check versions for all packages: `next`, `react`, `react-dom`, `@types/react`, `@types/react-dom`

Get current version (repeat for each package):

```bash
grep '"next":' package.json | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
grep '"react":' package.json | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
grep '"@types/react":' package.json | grep -oE '[0-9]+\.[0-9]+\.[0-9]+'
```

Get available versions from npm (repeat for each package):

```bash
# Latest patch in current minor (e.g., for 14.2.1, get latest 14.2.x)
npm view next versions --json | jq -r '.[]' | grep "^MAJOR\.MINOR\." | tail -1

# Latest overall version
npm view next version
```

Replace `MAJOR.MINOR` with current version's major.minor (e.g., `14.2`).

Parse versions to determine available upgrades for Next.js:
- **Patch available**: latest patch in current minor > current patch (e.g., 14.2.1 -> 14.2.3)
- **Minor/Major available**: latest overall > current minor/major (e.g., 14.2.x -> 14.3.x or 15.x)

If Next.js current == latest overall AND current == latest patch, inform user already on latest and stop.

### 3. User Confirmation

Use AskUserQuestion based on available upgrades:

- **Only patch available**: Proceed automatically without asking
- **Only minor/major available**: Ask user to confirm before proceeding
- **Both patch AND minor/major available**: Ask user which upgrade to perform:
  - Option 1: Patch only (e.g., 14.2.1 → 14.2.5) - safer, stays on current minor
  - Option 2: Minor/Major (e.g., 14.2.1 → 15.1.0) - latest features, may have breaking changes
  - Option 3: Both sequentially - patch first, then minor/major

### 4. Upgrade Process

Execute these steps in order:

#### 4.1 Create Branch

```bash
git checkout -b version-upgrades
```

If branch exists, checkout existing branch.

#### 4.2 Upgrade Dependencies

Based on user's upgrade choice (patch vs minor/major), determine target versions for each package:

- **Patch upgrade**: use latest patch version within current minor for each package
- **Minor/Major upgrade**: use latest overall version for each package

Install all packages together with `--save-exact` to avoid caret prefixes:

```bash
npm install --save-exact next@<NEXT_VER> react@<REACT_VER> react-dom@<REACT_VER>
npm install --save-exact -D @types/react@<TYPES_REACT_VER> @types/react-dom@<TYPES_REACT_DOM_VER>
```

Replace version placeholders with target versions. The `--save-exact` flag ensures versions are saved as `"16.0.11"` not `"^16.0.11"`.

#### 4.3 Verify Build

```bash
npm run build
```

Build must succeed. If fails, report error and stop.

#### 4.4 Verify Tests

```bash
npm test
```

All tests must pass. If fails, report error and stop.

#### 4.5 Commit Changes

```bash
git add package.json package-lock.json
git commit -m "$(cat <<'EOF'
⬆️ upgrade nextjs to <NEXT_VER>, react to <REACT_VER>

Co-Authored-By: Claude 🤖
EOF
)"
```

Replace version placeholders with actual versions.

#### 4.6 Push & Report

```bash
git push -u origin version-upgrades 2>&1
```

Read push output, extract "Create a pull request" URL from remote response, and report to user.

## Error Handling

- If build fails: Report build errors, suggest fixes if obvious
- If tests fail: Report failing tests, do not commit
- If push fails: Check if branch exists remotely, suggest `git pull` or force push confirmation
