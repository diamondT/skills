---
name: local-agent-codex
description: >
  Plan a task thoroughly, then delegate its execution to an external agent harness
  (OpenAI Codex CLI) running locally, instead of a regular built-in sub-agent.
  Writes a detailed self-contained prompt from the plan, runs `codex exec` with a
  specific model, waits for the result, and marks the task done only when the
  external agent reports success. Use this skill whenever the user says "local
  agent codex", "/local-agent-codex", "delegate to codex", "use codex", "have
  codex do it", "offload this to codex", or otherwise wants the actual
  implementation work performed by the Codex CLI while you do the planning and
  verification. Trigger even if the user does not name the skill. Do NOT use for
  ordinary sub-agent work (use the Agent tool), for opencode delegation (use
  `local-agent-opencode`), or when the user wants you to implement the change
  yourself.
---

# Delegate execution to a local external agent (Codex CLI)

You are the planner and reviewer; Codex is the executor. The value of this split is that the external agent gets a crisp, self-contained work order and you stay free to judge the result instead of being knee-deep in the edits. The quality of the outcome is decided almost entirely by the quality of the prompt you hand over — a vague prompt produces a vague result from *any* model, so the planning step is not optional ceremony.

## Step 1 — Plan the task

Before anything touches codex, understand the task the way you would if you were going to implement it yourself:

- Explore the codebase: which files change, which conventions apply, what the surrounding code looks like.
- Decide the approach: the concrete edits, new files, commands to run.
- Define "done": how success is verified (build passes, tests green, specific behaviour observable).

If the session supports plan mode or a task list, use it (create a task via TaskCreate / todo so there is something to mark done in Step 6). If anything about scope is ambiguous, ask the user *now* — the external agent cannot ask them later.

## Step 2 — Pick the model

Default: **`gpt-5.6-terra` at high reasoning effort** — i.e. `-m gpt-5.6-terra -c model_reasoning_effort="high"`. Use a different model or effort only when the user names one. This skill uses Codex-provided (hosted) models only.

**Guard: never invoke `codex` without an explicit `-m <model>`.** Omitting it silently falls back to whatever `~/.codex/config.toml` defaults to at that moment — which may be an expensive model or the wrong one entirely. Every `codex exec` in this skill, including retries and session resumes, must carry the explicit model selection chosen here.

Reasoning effort can be tuned per run with `-c model_reasoning_effort="high"` (or `low`/`medium`).

## Step 3 — Write the work-order prompt

The external agent shares **no context** with this conversation: it has not seen the user's request, your exploration, or any earlier discussion. Everything it needs must be in the prompt. Write the prompt to a file (use the scratchpad directory, e.g. `<scratchpad>/local-agent-prompt.md`) so it can be long, reviewed, and reused on retry.

Include, concretely:

1. **Context** — what the project is, the relevant directory, branch, and any conventions that apply (naming, style, test framework). Quote real snippets or file paths from your exploration rather than describing them abstractly.
2. **The task** — the plan from Step 1, translated into instructions: which files to create/modify and what the change should accomplish. Give intent plus constraints, not keystroke-level micromanagement — the executor is an agent, not a macro.
3. **Verification** — the exact commands that must pass (e.g. `mvn clean package`, `npm test`) and any behaviour to check.
4. **Boundaries** — what NOT to touch (no commits, no pushes, no dependency changes, no files outside the listed areas — adjust to the task). By default the external agent must not commit; you review first.
5. **Report format** — end the prompt with this requirement verbatim, because Step 5 parses for it:

```
When you are finished, end your reply with exactly one of:
RESULT: SUCCESS
RESULT: FAILURE - <one-line reason>
preceded by a short summary of every file you changed and the verification commands you ran with their outcomes.
```

## Step 4 — Run codex

```bash
codex exec - \
  -m <model> -c model_reasoning_effort="<effort>" \
  -s workspace-write \
  -C <absolute path to the project> \
  -o <scratchpad>/local-agent-last-message.txt \
  < <scratchpad>/local-agent-prompt.md \
  > <scratchpad>/local-agent-output.log 2>&1
```

- `codex exec` is Codex's non-interactive mode; `-` reads the prompt from stdin, which handles long prompt files cleanly.
- `-s workspace-write` lets the agent edit files and run commands inside the workspace while the sandbox blocks writes elsewhere. This is the guardrail that makes unattended execution acceptable — do **not** reach for `--dangerously-bypass-approvals-and-sandbox` unless the user explicitly asks for it and understands it removes all sandboxing.
- `-C` scopes the run to the project root the task concerns. Codex refuses to run outside a git repository unless you add `--skip-git-repo-check` — for project work you should be in one anyway, so treat that refusal as a signal, not an obstacle.
- `-o` writes the agent's *final message* to a file — this is what Step 5 parses for the `RESULT:` line, so always pass it.
- Redirect the full transcript to a log file: runs can be long and the transcript is what you review on failure.
- Agentic runs routinely exceed foreground command timeouts — run the command in the background and let its completion re-invoke you, rather than blocking or polling.

## Step 5 — Judge the result

When the run finishes, check three things in order:

1. **Exit code** — nonzero means the harness itself failed (bad model, auth/provider error, crash). Read the log tail, fix the invocation, retry. This is not a task failure.
2. **The `RESULT:` line** — read the last-message file from `-o`. `RESULT: SUCCESS` with a plausible change summary means the agent believes it is done. `RESULT: FAILURE - ...` or a missing marker means it is not.
3. **Plausibility** — skim the reported file list and verification outcomes against your plan. If the agent claims success but the summary contradicts the plan (wrong files, skipped verification), treat it as a failure.

**On success:** mark the task done (TaskUpdate / todo), then report to the user: what was delegated, which model ran it, what changed, and how it was verified.

**On failure:** diagnose from the log. If the prompt was the problem, improve it and resume the *same* session so the agent keeps its context:

```bash
codex exec resume --last "<corrective instruction>" \
  -m <model> -s workspace-write -C <project> \
  -o <scratchpad>/local-agent-last-message.txt >> <log> 2>&1
```

(`resume --last` continues the most recent session; `codex exec resume <SESSION_ID> "..."` targets a specific one.) Give it at most two retries; after that, stop and report the failure and the log location to the user rather than looping.

## Reference — codex exec flags

| Flag | Purpose |
|---|---|
| `-m <model>` | model selection (required for this skill; default `gpt-5.6-terra`) |
| `-s <mode>` | sandbox: `read-only`, `workspace-write` (use this), `danger-full-access` |
| `-C <dir>` | working root for the agent |
| `--add-dir <dir>` | extra writable directories besides the workspace |
| `-o <file>` | write the agent's final message to a file (parse `RESULT:` from here) |
| `resume --last` / `resume <id>` | continue the most recent / a specific session |
| `--json` | JSONL events on stdout instead of formatted text |
| `-c key=value` | config override, e.g. `-c model_reasoning_effort="high"` |
| `--skip-git-repo-check` | allow running outside a git repository |
| `--ephemeral` | don't persist session files (forgoes resume) |

Exit code is `0` on a completed run, nonzero on harness errors.
