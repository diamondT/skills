---
name: local-agent-opencode
description: >
  Plan a task thoroughly, then delegate its execution to an external agent harness
  (opencode) running locally, instead of a regular built-in sub-agent. Writes a
  detailed self-contained prompt from the plan, runs `opencode run` with a specific
  model, waits for the result, and marks the task done only when the external agent
  reports success. Use this skill whenever the user says "local agent",
  "/local-agent", "delegate to opencode", "use opencode", "have the local model do
  it", "offload this to an external agent", "run this through another harness", or
  otherwise wants the actual implementation work performed by an external/local
  agent while you do the planning and verification. Also triggers on
  "/local-agent-opencode". Trigger even if the user does
  not name the skill. Do NOT use for ordinary sub-agent work (use the Agent tool),
  for Codex CLI delegation (use `local-agent-codex`), or when the user wants you
  to implement the change yourself.
---

# Delegate execution to a local external agent (opencode)

You are the planner and reviewer; opencode is the executor. The value of this split is that the external agent gets a crisp, self-contained work order and you stay free to judge the result instead of being knee-deep in the edits. The quality of the outcome is decided almost entirely by the quality of the prompt you hand over — a vague prompt produces a vague result from *any* model, so the planning step is not optional ceremony.

## Step 1 — Plan the task

Before anything touches opencode, understand the task the way you would if you were going to implement it yourself:

- Explore the codebase: which files change, which conventions apply, what the surrounding code looks like.
- Decide the approach: the concrete edits, new files, commands to run.
- Define "done": how success is verified (build passes, tests green, specific behaviour observable).

If the session supports plan mode or a task list, use it (create a task via TaskCreate / todo so there is something to mark done in Step 6). If anything about scope is ambiguous, ask the user *now* — the external agent cannot ask them later.

## Step 2 — Pick the model

Default: **`local/whatever`**. Use a different model only when the user names one.

To see what is available: `opencode models` (format is `provider/model`, e.g. `openai/gpt-5.5`, `zai/glm-4.6`, `lmstudio/qwen/qwen3-coder-30b`). If the user asks for a model that is not in the list, show them the list and ask.

**Guard: never invoke `opencode` without an explicit `-m provider/model`.** Omitting it silently falls back to whatever opencode's own config defaults to — which may be an expensive hosted model or the wrong one entirely. Every `opencode run` in this skill, including retries and session continuations, must carry the `-m` flag with the model chosen here.

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

## Step 4 — Run opencode

```bash
opencode run "$(cat <scratchpad>/local-agent-prompt.md)" \
  -m <provider/model> \
  --auto \
  --dir <absolute path to the project> \
  --title "local-agent: <short task name>" \
  > <scratchpad>/local-agent-output.log 2>&1
```

- `--auto` auto-approves the agent's file edits and commands; without it a non-interactive run stalls or fails on permission prompts. This is why the Boundaries section of the prompt matters — `--auto` means the prompt is the only guardrail.
- `--dir` scopes the run to the project; run it against the repo root the task concerns.
- Redirect output to a log file: runs can be long and the full transcript is what you review on failure.
- Agentic runs routinely exceed foreground command timeouts — run the command in the background and let its completion re-invoke you, rather than blocking or polling.

## Step 5 — Judge the result

When the run finishes, check three things in order:

1. **Exit code** — nonzero means the harness itself failed (bad model, provider error, crash). Read the log tail, fix the invocation, retry. This is not a task failure.
2. **The `RESULT:` line** — read the end of the log. `RESULT: SUCCESS` with a plausible change summary means the agent believes it is done. `RESULT: FAILURE - ...` or a missing marker means it is not.
3. **Plausibility** — skim the reported file list and verification outcomes against your plan. If the agent claims success but the summary contradicts the plan (wrong files, skipped verification), treat it as a failure.

**On success:** mark the task done (TaskUpdate / todo), then report to the user: what was delegated, which model ran it, what changed, and how it was verified.

**On failure:** diagnose from the log. If the prompt was the problem, improve it and continue the *same* session so the agent keeps its context:

```bash
opencode run -c "<corrective instruction>" -m <provider/model> --auto --dir <project> >> <log> 2>&1
```

(`-c` continues the most recent session in that directory; `-s <sessionID>` targets a specific one — `opencode session list` shows IDs.) Give it at most two retries; after that, stop and report the failure and the log location to the user rather than looping.

## Reference — opencode run flags

| Flag | Purpose |
|---|---|
| `-m provider/model` | model selection (required for this skill) |
| `--auto` | auto-approve permissions (required for non-interactive edits) |
| `--dir <path>` | directory to run in |
| `-c` / `-s <id>` | continue last / specific session |
| `--title <t>` | session title, aids `opencode session list` |
| `--format json` | raw JSON events instead of formatted text |
| `-f <file>` | attach file(s) to the message |
| `--variant <v>` | provider-specific reasoning effort (e.g. `high`) |

Exit code is `0` on a completed run, nonzero on harness errors.
