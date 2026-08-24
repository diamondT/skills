---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

Use /tdd where possible, at pre-agreed seams.

Once done, spawn two review subagents in parallel. Both review skills are user-gated
(`disable-model-invocation`), so a subagent cannot invoke them — pass the instructions
instead. Give each agent this prompt, substituting `<base>`:

- Agent 1: "Run `cat ~/.agents/skills/review-code/SKILL.md` and follow it exactly.
  Fixed point: `<base>`. Current point: HEAD. Report findings only; do not edit files."
- Agent 2: "Run `cat ~/.agents/skills/review-with-codex/SKILL.md` and follow it exactly.
  Fixed point: `<base>`. Current point: HEAD. Report findings only; do not edit files."

`<base>` is the commit the work started from — the branch point, or the SHA before your
first change.

Gather the results from both and use your judgement to implement any fixes. If a defect
is found by both, highly consider implementing it.

In the end, commit your work to the current branch.
