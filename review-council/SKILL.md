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

First, spawn two subagents in parallel and `review-code` your changes. 

Once they report back with the findings, spawn two subagents in parallel and ask them to vote on the reviewers' findings. The voters should not re-review the code, just offer their opinion on the first group's findings. Each voter should vote on each finding, either yes or no. The voter should *not* offer suggestions and/or try to identify additional findings, their work is to vote on existing findings only. The voters should not judge each finding solely based on the classification (critical/high/medium/etc) that the initial reviewer gave, but they should re-evaluate the criticality as well as the finding itself.

Once all the voters vote, ignore findings that are unanimously dropped (both voters said no), keep findings that are unanimously upvoted (both voters said yes). For the rest of the findings that have split votes (one voter said yes but the other said no), evaluate the finding yourself and offer the tie-breaking vote that will decide to keep or drop the finding.

Report the final findings. Gather all votes and pick the findings that have a majority vote (at least 2 out of 3, including yourself as the tie-breaker where needed). Report them to the user in the original format as reported by the reviewer and add the confidence as reported by the voters.
