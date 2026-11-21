---
name: local-agent-pi
description: >
  Run a task with the pi coding agent over ACP (Agent Client Protocol) for an explicit model and
  thinking level, using the bundled Bun ACP client. Use when a prompt should be executed by pi.
---

# Run a task with pi over ACP

`scripts/acp-run.ts` is a small ACP client. It starts the pi ACP adapter (`pi-acp`, which drives `pi --mode rpc`), opens or resumes a session, sets the model and thinking level through ACP, sends one prompt, and returns pi's answer. Every exchange with pi goes over ACP JSON-RPC on stdio; pi's CLI flags are never used.

The caller decides what to ask pi: the prompt, the working directory, and how to judge the answer. This skill does not shape the task.

## Requirements

- `bun` on PATH.
- The adapter command is `bunx pi-acp` by default. Set `PI_ACP_CMD` to change it (for example `PI_ACP_CMD="bunx pi-acp@0.0.34"` to pin a version, or a path to a local build). The value is split on whitespace into argv.
- pi itself installed and logged in to its providers.

## Choose model and thinking level

Always pass `--model` and `--thinking` explicitly; never rely on pi's configured defaults. If the caller did not name them, list what pi offers and ask:

```bash
bun <skill-dir>/scripts/acp-run.ts --list --cwd <project>
```

This prints `{ agent, models: [...], thinking: [...] }`. Model ids are `provider/id` as pi-acp reports them; thinking levels are pi's (`off`, `minimal`, `low`, `medium`, `high`, `xhigh`, `max`, as far as the model supports).

## Run

Put anything longer than one line in a file. pi shares no context with this conversation, so the prompt must be self-contained.

```bash
bun <skill-dir>/scripts/acp-run.ts \
  --model <provider/id> \
  --thinking <level> \
  --cwd <absolute project path> \
  --prompt-file <scratchpad>/pi-prompt.md \
  --log <scratchpad>/pi-<name>.ndjson
```

| Flag | Meaning |
|---|---|
| `--model` | model id, required, validated against the session's model list |
| `--thinking` | thinking level (ACP session mode), required, validated |
| `--cwd` | session working directory (default: current) |
| `--prompt-file` / `--prompt` | the prompt text |
| `--session <id>` | resume an existing session (`session/load`) and send a follow-up |
| `--log <file>` | NDJSON transcript of every ACP message (tool calls, diffs, updates) |
| `--timeout <s>` | send `session/cancel` after s seconds |
| `--approve-permissions` | approve ACP permission requests (default: reject) |

Agent turns are long. Run the command in the background and let its completion notify you rather than polling or blocking on it.

## Read the result

stdout ends with one JSON line:

```json
{"sessionId":"…","model":"…","thinking":"…","stopReason":"end_turn","text":"<pi's final answer>","log":"…"}
```

| Exit | Meaning |
|---|---|
| 0 | turn finished (`end_turn`) |
| 1 | turn ended otherwise (`cancelled`, `max_tokens`, `refusal`, …); `stopReason` says which |
| 2 | setup failure: unknown model or thinking level (stderr lists valid values), adapter failed to start, auth required, protocol error |

`text` is pi's reply only. To see what pi actually did (files edited, commands run), read the `--log` NDJSON: `session/update` entries with `tool_call` and `tool_call_update`.

## Follow-ups

Pass the returned `sessionId` back with `--session <id>` (with `--model` and `--thinking` again) to continue the same conversation. The session is a normal pi session, so it can also be resumed in the pi TUI.

## Safety

pi-acp does not route file or terminal access through ACP: pi reads, writes and runs commands locally with its own tools, in `--cwd`. Permission requests that pi-acp does send are rejected unless `--approve-permissions` is given. The prompt is therefore the main boundary on what pi does: state there what it must not touch (commits, pushes, files outside scope).
