#!/usr/bin/env bun
// Minimal, dependency-free ACP (Agent Client Protocol) client for pi via pi-acp.
// Speaks newline-delimited JSON-RPC 2.0 over the adapter's stdio.
import { parseArgs } from "node:util";
import { appendFileSync, readFileSync } from "node:fs";
import { resolve } from "node:path";

const { values: args } = parseArgs({
  options: {
    model: { type: "string" },
    thinking: { type: "string" },
    cwd: { type: "string" },
    prompt: { type: "string" },
    "prompt-file": { type: "string" },
    session: { type: "string" },
    log: { type: "string" },
    list: { type: "boolean", default: false },
    timeout: { type: "string" },
    "approve-permissions": { type: "boolean", default: false },
    help: { type: "boolean", short: "h", default: false },
  },
  strict: true,
});

const USAGE = "usage: bun acp-run.ts --model <provider/id> --thinking <level> --cwd <dir> (--prompt <text> | --prompt-file <file>) [--session <id>] [--log <file.ndjson>] [--timeout <seconds>] [--approve-permissions]\n       bun acp-run.ts --list [--cwd <dir>]";

function fail(msg: string, extra?: unknown): never {
  process.stderr.write("acp-run: " + msg + "\n");
  if (extra !== undefined) process.stderr.write(JSON.stringify(extra, null, 2) + "\n");
  cleanup();
  process.exit(2);
}

if (args.help) { console.log(USAGE); process.exit(0); }

const cwd = resolve(args.cwd ?? process.cwd());
const logPath = args.log ? resolve(args.log) : undefined;
const log = (obj: unknown) => { if (logPath) appendFileSync(logPath, JSON.stringify(obj) + "\n"); };

let promptText: string | undefined;
if (!args.list) {
  if (!args.model || !args.thinking) fail("--model and --thinking are required\n" + USAGE);
  if (args["prompt-file"]) promptText = readFileSync(resolve(args["prompt-file"]), "utf8");
  else if (args.prompt !== undefined) promptText = args.prompt;
  if (!promptText?.trim()) fail("a non-empty --prompt or --prompt-file is required\n" + USAGE);
}

// ---- transport -------------------------------------------------------------
const cmd = (process.env.PI_ACP_CMD?.trim() || "bunx pi-acp").split(/\s+/);
const child = Bun.spawn(cmd, { cwd, stdin: "pipe", stdout: "pipe", stderr: "pipe" });
let childStderr = "";
(async () => { const d = new TextDecoder(); for await (const c of child.stderr as any) childStderr += d.decode(c); })();

function cleanup() { try { child.kill(); } catch {} }

let nextId = 1;
const pending = new Map<number, { resolve: (v: any) => void; reject: (e: any) => void; method: string }>();
const send = (msg: object) => { child.stdin.write(JSON.stringify({ jsonrpc: "2.0", ...msg }) + "\n"); child.stdin.flush(); };
function request(method: string, params: object): Promise<any> {
  const id = nextId++;
  return new Promise((res, rej) => { pending.set(id, { resolve: res, reject: rej, method }); send({ id, method, params }); });
}
const notify = (method: string, params: object) => send({ method, params });

let collecting = false;
let answer = "";
function onNotification(method: string, params: any) {
  log({ dir: "in", method, params });
  if (method === "session/update" && collecting) {
    const u = params?.update;
    if (u?.sessionUpdate === "agent_message_chunk" && u.content?.type === "text") answer += u.content.text;
  }
}

function onAgentRequest(id: number | string, method: string, params: any) {
  log({ dir: "in", id, method, params });
  if (method === "session/request_permission") {
    // Default: reject. Approving agent permission requests is an explicit opt-in by the caller.
    const want = args["approve-permissions"] ? "allow" : "reject";
    const opt = (params?.options ?? []).find((o: any) => String(o.kind).startsWith(want));
    process.stderr.write("acp-run: permission request " + (opt ? want + "ed" : "cancelled") + ": " + (params?.toolCall?.title ?? "?") + "\n");
    const result = opt ? { outcome: { outcome: "selected", optionId: opt.optionId } } : { outcome: { outcome: "cancelled" } };
    send({ id, result });
    log({ dir: "out", id, result });
    return;
  }
  send({ id, error: { code: -32601, message: "Method not supported by acp-run: " + method } });
}

(async () => {
  let buf = "";
  const dec = new TextDecoder();
  for await (const chunk of child.stdout as any) {
    buf += dec.decode(chunk, { stream: true });
    let nl;
    while ((nl = buf.indexOf("\n")) >= 0) {
      const line = buf.slice(0, nl).trim();
      buf = buf.slice(nl + 1);
      if (!line) continue;
      let msg: any;
      try { msg = JSON.parse(line); } catch { log({ dir: "in", nonJson: line }); continue; }
      if (msg.method !== undefined && msg.id !== undefined) onAgentRequest(msg.id, msg.method, msg.params);
      else if (msg.method !== undefined) onNotification(msg.method, msg.params);
      else if (msg.id !== undefined && pending.has(msg.id)) {
        const p = pending.get(msg.id)!;
        pending.delete(msg.id);
        log({ dir: "in", id: msg.id, method: p.method, result: msg.result, error: msg.error });
        msg.error ? p.reject(msg.error) : p.resolve(msg.result);
      }
    }
  }
})();

child.exited.then((code) => {
  for (const [, p] of pending) p.reject({ message: "pi-acp exited (code " + code + ")" + (childStderr ? ": " + childStderr.trim().slice(-2000) : "") });
  pending.clear();
});

const call = async (method: string, params: object) => {
  log({ dir: "out", method, params });
  try { return await request(method, params); }
  catch (e: any) { fail(method + " failed: " + (e?.message ?? JSON.stringify(e)), e?.data); }
};

// ---- session config helpers ------------------------------------------------
type Opt = { value: string; name?: string };
const flatOptions = (opts: any[] = []): Opt[] =>
  opts.flatMap((o: any) => (Array.isArray(o?.options) ? flatOptions(o.options) : o?.value !== undefined ? [{ value: String(o.value), name: o.name }] : []));

function modelOption(session: any) {
  return (session?.configOptions ?? []).find((o: any) => o.category === "model" || o.id === "model");
}
function modelIds(session: any): string[] {
  const opt = modelOption(session);
  if (opt) return flatOptions(opt.options).map((o) => o.value);
  return (session?.models?.availableModels ?? []).map((m: any) => m.modelId);
}
function thinkingIds(session: any): string[] {
  return (session?.modes?.availableModes ?? []).map((m: any) => m.id);
}

// ---- main -------------------------------------------------------------------
let sessionId: string | undefined = args.session;
let stopping = false;
function stop(reason: string) {
  if (stopping) return;
  stopping = true;
  process.stderr.write("acp-run: " + reason + ", cancelling\n");
  if (sessionId) { try { notify("session/cancel", { sessionId }); log({ dir: "out", method: "session/cancel", params: { sessionId } }); } catch {} }
  setTimeout(() => { cleanup(); process.exit(1); }, 5000);
}
process.on("SIGINT", () => stop("SIGINT"));
process.on("SIGTERM", () => stop("SIGTERM"));
if (args.timeout) setTimeout(() => stop("timeout after " + args.timeout + "s"), Number(args.timeout) * 1000);

const init = await call("initialize", {
  protocolVersion: 1,
  clientCapabilities: { fs: { readTextFile: false, writeTextFile: false }, terminal: false },
  clientInfo: { name: "acp-run", version: "0.1.0" },
});

const session = sessionId
  ? await call("session/load", { sessionId, cwd, mcpServers: [] })
  : await call("session/new", { cwd, mcpServers: [] });
sessionId = sessionId ?? session.sessionId;

if (args.list) {
  console.log(JSON.stringify({ agent: init?.agentInfo, models: modelIds(session), thinking: thinkingIds(session) }, null, 2));
  cleanup();
  process.exit(0);
}

const models = modelIds(session);
if (models.length && !models.includes(args.model!)) fail("unknown model '" + args.model + "'. Available:", models);
const mOpt = modelOption(session);
if (mOpt) await call("session/set_config_option", { sessionId, configId: mOpt.id, value: args.model });
else await call("session/set_model", { sessionId, modelId: args.model });

const levels = thinkingIds(session);
if (!levels.includes(args.thinking!)) fail("thinking level '" + args.thinking + "' not offered for this session. Available:", levels);
await call("session/set_mode", { sessionId, modeId: args.thinking });

collecting = true;
const res = await call("session/prompt", { sessionId, prompt: [{ type: "text", text: promptText }] });
collecting = false;

const stopReason = res?.stopReason ?? "unknown";
console.log(JSON.stringify({ sessionId, model: args.model, thinking: args.thinking, stopReason, text: answer, log: logPath ?? null }));
cleanup();
process.exit(stopReason === "end_turn" ? 0 : 1);
