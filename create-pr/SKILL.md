---
name: create-pr
description: >
  Interactive workflow to commit, branch, and push changes with JIRA ticket prefixes.
  Use when the user says "commit", "push my changes", "create pr", "/create-pr",
  or wants to create a commit tied to a JIRA ticket. Also use when the user asks to
  branch and commit work, prepare a commit message with a ticket number, or push
  changes to a Bitbucket/Git remote with a JIRA-prefixed branch and message.
---

# JIRA Commit Workflow

Interactive commit workflow: gather ticket info, summarize changes, branch if needed, commit, push, and return the remote URL.

## Workflow

### 1. Ask for JIRA ticket number

Use AskUserQuestion. Accept empty (no ticket). Example ticket: `P00268-824`.

### 2. Analyze uncommitted changes

Run `git status` (never `-uall`) and `git diff --staged` / `git diff` to understand what changed. Prepare a concise summary of the changes for later use in the commit message. Also run `git log --oneline -5` to match existing commit message style.

### 3. Branch check and creation

Check current branch with `git branch --show-current`.

**If on a protected branch** (`main`, `next`, or matching `release/\d+\.\d+\.\d+`):

- Ask which base branch to start from: main, next, or the current release branch (only offer branches that exist locally or on remote).
- Generate a branch name: `<TICKET>-<short-kebab-description>` (e.g. `P00268-824-sse-heartbeat`). If no ticket, just use `<short-kebab-description>`.
- Create and checkout: `git checkout -b <branch> <base>`.

**If already on a feature branch**: stay on it.

### 4. Stage files

Stage relevant changed files by name. Never use `git add -A` or `git add .`. Warn and skip files that may contain secrets (`.env`, credentials, keys).

### 5. Prepare commit message

Format:

```
<TICKET> - <short description>
```

If no ticket, omit the ticket prefix and dash.

For larger changes add a blank line then a brief body (1-3 lines). Keep it concise overall.

**Examples:**

```
P00268-824 - add heartbeat to SSE discount events stream
```

```
P00268-812 - fix coupon calculations for orders containing services

Correctly apply coupon discount proportionally across order items
that include both products and services.
```

Present the commit message to the user with AskUserQuestion and ask for confirmation. If the user provides a modified message, use that instead.

### 6. Commit and push

- Commit using a HEREDOC for the message.
- Push with `git push -u origin <branch>`.

### 7. Create pull request

After pushing, create the PR using the `bb` CLI:

```
bb pr create --title "<SHORT_PR_DESCRIPTION>" --source <SOURCE_BRANCH> --destination <TARGET_BRANCH>
```

- **Title**: Use the commit message subject (the `<TICKET> - <short description>` part).
- **Source**: The current feature branch.
- **Destination**: If obvious from context (e.g. the branch was created from `main` or `next`), use that. Otherwise, ask the user which target branch to use via AskUserQuestion.

Present the PR URL from the `bb` output to the user.

## Rules

- Never amend existing commits unless explicitly asked.
- Never force push.
- Never skip hooks (no `--no-verify`).
- If there are no changes to commit, inform the user and stop.
