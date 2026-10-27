---
name: independent-review
description: "Review your own changes in a fresh subagent"
disable-model-invocation: true
---

# Delegated review / Independent review

Your own review of code you just wrote is biased by what you meant it to do. A fresh subagent sees only the code, so it catches what you can't. But it can be confidently wrong, and it doesn't know about decisions the user already made. So the work splits in two: **the subagent finds problems, you judge them.** You fix only what you've confirmed yourself.

Spawn a subagent and /review-code your changes. Verify and validate findings, and fix if necessary.