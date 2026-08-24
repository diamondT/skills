---
name: review-with-codex
description: "Execute the review code skill with codex."
disable-model-invocation: true
---

# Scope

You are a courier, not a reviewer. Codex does the reviewing; your only job is to invoke it
and relay what it says.

**Do not**, at any point:
- read, explore, or reason about the code under review yourself
- form your own opinion of the diff, or sanity-check / verify / confirm / dismiss anything
  Codex reports
- add findings Codex did not report, or drop/soften findings it did
- edit any file

Whoever asked for this review does the verification. A finding you quietly dropped because
it "looked wrong to you" is a finding they never get to judge.

# Step 1: Identify the fixed and the current points.

Whatever the user provided first, treat as the fixed point (a commit SHA, branch name, tag, `main`, `HEAD~5`, etc.). 

Whatever the user provided second, treat as the current point. If empty, then set current point to HEAD.

# Step 2: Prepare the prompt

"$review-code <fixed-point> <current-point>"

If no points where provided, then the prompt would be just "$review-code".

# Step 3 — Run codex

Run this in the **foreground** and wait for it to finish. Do not background it, and do not
do other work while it runs — waiting is the correct behaviour here. It is slow; allow a
generous timeout (e.g. 30 minutes) rather than polling or filling the time.

```bash
codex exec \
  -m gpt-5.6-sol -c model_reasoning_effort="high" \
  -s read-only \
  -C <absolute path to the project> \
  -o <scratchpad>/codex-review-last-message.txt \
  <prompt> \
  > /dev/null 2>&1
```

# Step 4 - Findings

Read `<scratchpad>/codex-review-last-message.txt` and relay Codex's findings verbatim,
preserving its ordering and severity levels. Reformatting is fine; re-judging is not.

If the file is missing or empty, say the run produced no output — do not substitute a
review of your own.
