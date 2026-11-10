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

Spawn a subagent and /review-code your changes. Ask the subagent for a score out of 10. Count each full review pass as one round. Verify and validate findings, and fix if necessary. A fresh review after fixes starts a new round. 

If you agree with the recommendations, make the changes and request a fresh
review after. Continue this process until the review reaches a satisfactory score or if the max number of rounds is exhausted:

| Output level | Minimum review score | Maximum rounds to run |
|--------------|----------------------|-----------------------|
| LOW          | 7/10                 | 2                     |
| MEDIUM       | 8/10                 | 3                     |
| HIGH         | 9/10                 | 5                     |

Show the results at the end:

```markdown
## Review Cycle

Blast radius: MEDIUM

Rounds: 2

| Reviewer | Round 1 | Round 2 |
| --- | --- | --- |
| Claude Opus | 7/10 | 9/10 |
```

If the reviewer gives no score, write no score. Do not invent one.

Do not let repeated reviews result in scope creep. It is your job to fight to
keep scope limited.

