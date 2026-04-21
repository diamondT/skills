---
name: review-pr
description: >
  Comprehensive code review of BitBucket Pull Requests, acting as a strict senior software engineer.
  Use this skill whenever the user wants to review a PR, perform a code review, examine changes
  in a pull request, inspect code before merging, or get feedback on a BitBucket PR.
  Triggers on "review pr", "review pull request", "code review PR", "review my PR", "check my PR",
  "look at my PR", "review the diff", or any phrasing around reviewing, inspecting, or providing
  feedback on a BitBucket pull request. Always use this skill — don't attempt ad-hoc PR reviews
  without it.
---

# BitBucket PR Review

You act as a strict, experienced senior software engineer performing a thorough code review.

## Step 1: Identify the PR

**If the user provided a PR ID:**
```bash
bb pr view <ID> -o json
```
Parse the JSON. Source branch is at `source.branch.name`, target branch at `destination.branch.name`. Note the title and description.

**If no PR ID was provided:**
```bash
bb pr list -o json
```
Present a concise table: `ID | Title | Author | Source Branch`. Ask which PR to review, then run `bb pr view <ID> -o json` for the selected one. Wait for their selection before continuing.

## Step 2: Get the diff

Fetch and checkout the latest refs, then get the full diff:
```bash
git fetch origin
git diff origin/<target-branch>...origin/<source-branch>
```

Also read any `CLAUDE.md` files in the repo — they define project-specific patterns and conventions you must enforce during review.

## Step 3: Review the code

Analyze the diff thoroughly. Be strict. Only flag things that genuinely matter.

**Logic & correctness**
- Logic errors, off-by-one errors, race conditions
- Unhandled edge cases (null/empty input, boundary values, concurrent access)
- Incorrect assumptions about data shape or system state

**Security**
- Injection vulnerabilities (SQL, command, XSS, etc.)
- Missing or incorrect auth/authz checks
- Sensitive data exposure (secrets in code, excessive logging, unsafe defaults)

**Performance**
- N+1 queries or repeated unnecessary computation
- Blocking calls in async/reactive contexts
- Resource leaks (connections, streams, handles not closed)

**Code quality & readability**
- Unclear naming that obscures intent
- Functions doing too many things
- Dead code, commented-out blocks, unaddressed TODOs
- Non-obvious logic with no explanation

**Project consistency**
- Deviations from patterns established elsewhere in the codebase
- Violations of conventions from `CLAUDE.md` (if present)
- Inconsistent error handling compared to the rest of the project
- New abstractions that duplicate existing ones

**Do NOT flag:**
- Style choices handled automatically by the project's formatter/linter
- Micro-optimizations with no real impact
- Hypothetical risks not grounded in how the code is actually used
- Preferences — only flag when there's a concrete reason

## Step 4: Present findings

List all findings ranked by **criticality first, then level of effort** (higher effort last within same criticality tier).

```
## Review Findings

### Critical
1. [SHORT TITLE] — `path/to/File.java:42`
   **Problem:** What is wrong and why it matters.
   **Suggestion:** Concrete fix or direction.

### High
2. ...

### Medium
3. ...

### Low / Nitpick
4. ...
```

Criticality levels:
- **Critical** — bugs, security holes, data loss risk, broken functionality
- **High** — correctness issues, significant performance problems, security concerns
- **Medium** — missing edge case handling, maintainability, consistency violations
- **Low / Nitpick** — minor readability or style deviations

End with a brief 2–3 sentence overall assessment of the PR.

## Step 5: Add PR comments

Ask the user: _"Which of these would you like me to add as PR comments? (numbers, 'all', or 'none')"_

Wait for their response.

For each selected finding, compose a comment that clearly explains the problem and proposes a concrete solution. Keep it professional and direct — 2–5 sentences is usually right.

Then post each comment using the appropriate form:

**Specific line in a file:**
```bash
bb pr comment --body "<COMMENT>" --path "<FILE_PATH>" --line <LINE> --line-side new <ID>
```

**File-level issue (not tied to a specific line):**
```bash
bb pr comment --body "<COMMENT>" --path "<FILE_PATH>" <ID>
```

**General comment (not tied to any file):**
```bash
bb pr comment --body "<COMMENT>" <ID>
```

- `FILE_PATH` must be relative to the repository root, exactly as it appears in the diff output.
- Use the line number of the most relevant line for the issue — the last line of a problematic block is usually best.
- After posting all comments, confirm how many were added and on which files.
