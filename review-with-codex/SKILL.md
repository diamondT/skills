---
name: review-with-codex
description: "Execute the review code skill with codex."
disable-model-invocation: true
---

# Step 1: Identify the fixed and the current points.

Whatever the user provided first, treat as the fixed point (a commit SHA, branch name, tag, `main`, `HEAD~5`, etc.). 

Whatever the user provided second, treat as the current point. If empty, then set current point to HEAD.

# Step 2: Prepare the prompt

"$review-code <fixed-point> <current-point>"

If no points where provided, then the prompt would be just "$review-code".

# Step 3 — Run codex

```bash
codex exec \
  -m gpt-5.6-sol -c model_reasoning_effort="high" \
  -s workspace-read \
  -C <absolute path to the project> \
  -o <scratchpad>/codex-review-last-message.txt \
  <prompt> \
  > /dev/null 2>&1
```

# Step 4 - Findings

Read the last message from the <scratchpad> directory and present the findings.

