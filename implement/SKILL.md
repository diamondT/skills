---
name: implement
description: "Implement a piece of work based on a spec or set of tickets."
disable-model-invocation: true
---

Implement the work described by the user in the spec or tickets.

Use /tdd where possible, at pre-agreed seams.

Once done, review the work: run `cat ~/.agents/skills/adversary-review/SKILL.md` and follow
it exactly, with fixed point `<base>` and current point HEAD. That skill is user-gated
(`disable-model-invocation`), so invoke it this way rather than with the Skill tool.

`<base>` is the commit the work started from — the branch point, or the SHA before your
first change.

The review comes back as findings you verified yourself, not as applied changes. Implement
the fixes you judge to be real, and resolve anything the review left unresolved before you
decide on it.

In the end, commit your work to the current branch.
