---
name: review-council
description: Orchestrate a council of reviewers
disable-model-invocation: true
---

# Review council

Orchestrate a group of reviewers on a set of changes, either local uncommitted changes or a PR.

The subagents should remain independent. Keep your briefs to the subagents neutral, do not impose your opinions or
reasoning about any of the changes.

## Order of operations

You have two groups of specialists under your command: reviewers and voters.

First, spawn two subagents in parallel, one Claude Opus and one Gemini 4 Neon (launch Neon, via pi ACP using `local-agent-pi` with a wrapper subagent) and `review-code` your changes. Ask the subagents for a score out of 10.

Once they report back with the findings, spawn one subagent and ask them to vote on the reviewers' findings. The voter should not re-review the code, just offer their opinion on the first group's findings. Voter should vote on each finding, either yes or no. The voter should *not* offer suggestions and/or try to identify additional findings, their work is to vote on existing findings only. Voter should not judge each finding solely based on the classification (critical/high/medium/etc) that the initial reviewer gave, but they should re-evaluate the criticality as well as the finding itself. Instruct the voter to downvote any findings that would result in scope creep.

While waiting for the voter, vote on the findings yourself following the same principles.

Once the voter votes, ignore findings that are unanimously dropped (both you and the voter said no), keep findings that are unanimously upvoted (both you and the voter said yes). For the rest of the findings that have split votes, you are the tie-breaker, you will decide to keep or drop the finding.

Report the final findings. Report them to the user as reported by the reviewer and add the confidence as reported by the voter. Use the following template

```
## Review Findings

## Overall Scores
|Reviewer   | Score     |
------------------------|
|Reviewer 1 | <SCORE 1> |
|Reviewer 2 | <SCORE 2> |

### Critical
1. [SHORT TITLE] — `path/to/File.java:42` (as reported by the reviewers)
   **Confidence:** (as reported by the voter) 
   **Problem:** What is wrong and why it matters. (as reported by the reviewers)
   **Suggestion:** Concrete fix or direction. (as reported by the reviewers)

### High
2. ...

### Medium
3. ...

### Low / Nitpick
4. ...
```

Do not let findings result in scope creep. Fight alongside the voters to keep scope limited.

