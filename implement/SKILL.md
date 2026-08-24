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
  Fixed point: `<base>`. Current point: HEAD. Reading the diff is your job; everything
  after the findings list is not. Stop at the skill's Step 4 output. Do not edit files.
  Do not run builds, tests, linters, or the app to prove or disprove a finding — I do
  that. Do not draft, prototype, or apply a fix; a concrete suggestion in the finding is
  as far as you go. Stay inside the diff and the files it touches. Report every finding
  the skill's bar admits, even ones you are unsure about — say so and let me judge."
- Agent 2: "Run `cat ~/.agents/skills/review-with-codex/SKILL.md` and follow it exactly.
  Fixed point: `<base>`. Current point: HEAD. Then report the findings and stop. Do not
  review the diff yourself — the skill makes you a courier for Codex's findings, not a
  reviewer. Do not edit files."

`<base>` is the commit the work started from — the branch point, or the SHA before your
first change.

Neither agent verifies anything: they report raw findings, and both may be wrong.
Verification is yours alone — do not delegate it and do not accept a finding because an
agent sounded confident. Gather both reports, check each finding against the actual code
yourself, and implement the fixes you judge to be real. If a defect is found by both,
highly consider implementing it.

In the end, commit your work to the current branch.
