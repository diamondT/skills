---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

Use /tdd where possible, at pre-agreed seams.

Once done, spawn two subagents to review the code: run skill /review-code in one of them and run skill /review-with-codex in the other. Gather the results from both and use your judgement to implement any fixes. If a defect is found by both, highly consider implementing it.

In the end, commit your work to the current branch.

