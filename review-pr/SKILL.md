---
name: review-pr
description: "Review the changes in a BitBucket pull request"
disable-model-invocation: true
---

# BitBucket PR Review

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

## Step 2: Review the code

Call the /review-code skill and pass the fixed point (origin/<target-branch>) and the current point (origin/<source-branch>).

## Step 3: Resolution

Present the output of Step 3. Ask the user if they want to comment on the PR or fix any of the findings.

### Step 3.1: Add PR comments

In case they select to comment, ask the user: _"Which of these would you like me to add as PR comments? (numbers, or 'all')"_

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

### Step 3.2: Fix

In case they select to fix, checkout the source branch and ask the user which findings they would like fixed (numbers, or 'all'). Proceed with the fixes.

