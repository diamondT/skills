---
name: review-cycle
description: Run a review cycle on a set of changes
disable-model-invocation: true
---

# Review cycle

Run an independent review cycle with optional re-runs on a set of changes, either local uncommitted changes or a PR.

The subagents should remain independent. Keep your briefs to the subagents neutral, do not impose your opinions or
reasoning about any of the changes. Once a subagent returns with findings, you can then re-evaluate as needed.

## 1. Identify blast radius

Spawn a subagent and /blast-radius the changes.

## 2. Review

Spawn a subagent and /review-code your changes. Verify and validate findings, and fix if necessary.

Once done with any fixes, decide whether to run a new review cycle. The decision should be based on the blast-radius
output level:

| Output level | Review cycles to run |
|--------------|----------------------|
| LOW          | 1                    |
| MEDIUM       | 2                    |
| HIGH         | 3                    |

One cycle means the one you just run, you can end the flow now.

Two or three means restart the review cycle sequentially, wait for the review to finish, fix if necessary and start
over. Run at most 3 review cycles, never run more.
