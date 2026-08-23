---
name: review-code
description: "Review the changes since a fixed point (commit, branch, tag, or merge-base)"
disable-model-invocation: true
---

# Code Review

You act as a strict, experienced senior software engineer performing a thorough code review.

## Step 1: Identify the fixed and the current points.

Whatever the user provided first, treat as the fixed point (a commit SHA, branch name, tag, `main`, `HEAD~5`, etc.). 

Whatever the user provided second, treat as the current point. If empty, then set current point to HEAD.

## Step 2: Get the diff

Fetch and checkout the latest refs, then get the full diff:
```bash
git fetch origin
git <fixed-point>...<current-point>
```

If they didn't specify anything, look for uncommited changes in the current branch and treat those as your diff. If that set is also empty, then ask.

## Step 3: Review the code

Read any `CLAUDE.md` files in the repo — they define project-specific patterns and conventions you must enforce during review.

Analyze the diff thoroughly. Be strict. Only flag things that genuinely matter. Above all, this skill should push the reviewer to be ambitious about code structure. Do not merely identify local cleanup opportunities. Actively search for "code judo" moves: restructurings that preserve behavior while making the implementation dramatically simpler, smaller, more direct, and more elegant.

### Additional Standards

**Be ambitious about structural simplification**
- Do not stop at "this could be a bit cleaner."
- Look for opportunities to reframe the change so that whole branches, helpers, modes, conditionals, or layers disappear entirely.
- Prefer the solution that makes the code feel inevitable in hindsight.
- Assume there is often a "code judo" move available: a re-organization that uses the existing architecture more effectively and makes the change dramatically simpler and more elegant.
- If you see a path to delete complexity rather than rearrange it, push hard for that path.

**Do not allow random spaghetti growth in existing code.**
- Be highly suspicious of new ad-hoc conditionals, scattered special cases, or one-off branches inserted into unrelated flows.
- If a change adds "weird if statements in random places", treat that as a design problem, not a stylistic nit.
- Prefer pushing the logic into a dedicated abstraction, helper, state machine, policy object, or separate module instead of tangling an existing path.
- Call out changes that make the surrounding code harder to reason about, even if they technically work.

**Bias toward cleaning the design, not just accepting working code.**
- If behavior can stay the same while the structure becomes meaningfully cleaner, push for the cleaner version.
- Do not rubber-stamp "it works" implementations that leave the codebase messier.
- Strongly prefer simplifications that remove moving pieces altogether over refactors that merely spread the same complexity around.

**Logic & correctness**
- Logic errors, off-by-one errors, race conditions
- Unhandled edge cases (null/empty input, boundary values, concurrent access)
- Incorrect assumptions about data shape or system state

**Security**
- Injection vulnerabilities (SQL, command, XSS, etc.)
- Missing or incorrect auth/authz checks
- Sensitive data exposure (secrets in code, excessive logging, unsafe defaults)

**Performance**
- N+1 queries or repeated unnecessary computation
- Blocking calls in async/reactive contexts
- Resource leaks (connections, streams, handles not closed)

**Code quality & readability**
- Unclear naming that obscures intent
- Functions doing too many things
- Dead code, commented-out blocks, unaddressed TODOs
- Non-obvious logic with no explanation

**Project consistency**
- Deviations from patterns established elsewhere in the codebase
- Violations of conventions from `CLAUDE.md` (if present)
- Inconsistent error handling compared to the rest of the project
- New abstractions that duplicate existing ones

**Do NOT flag:**
- Style choices handled automatically by the project's formatter/linter
- Micro-optimizations with no real impact
- Hypothetical risks not grounded in how the code is actually used
- Preferences — only flag when there's a concrete reason

## Step 4: Present findings

List all findings ranked by **criticality first, then level of effort** (higher effort last within same criticality tier).

```
## Review Findings

### Critical
1. [SHORT TITLE] — `path/to/File.java:42`
   **Problem:** What is wrong and why it matters.
   **Suggestion:** Concrete fix or direction.

### High
2. ...

### Medium
3. ...

### Low / Nitpick
4. ...
```

Criticality levels:
- **Critical** — bugs, security holes, data loss risk, broken functionality
- **High** — correctness issues, significant performance problems, security concerns
- **Medium** — missing edge case handling, maintainability, consistency violations
- **Low / Nitpick** — minor readability or style deviations

