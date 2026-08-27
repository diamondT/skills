---
name: adversary-review
description: "Review changes with two independent adversarial reviewers, then verify every finding yourself."
disable-model-invocation: true
---

# Adversary Review

Two reviewers look at the same diff without seeing each other's work: one is a subagent
running the `review-code` skill, the other is Codex relayed through `review-with-codex`.
Neither verifies anything — they report raw findings and both may be wrong. You are the
adversary to both of them: you check every finding against the actual code before it
reaches the user.

The value here is disagreement. Two reviewers with different blind spots surface more real
defects than one, and the noise they add is exactly what your verification pass removes.
Skipping the verification turns this skill into a firehose of plausible-sounding nonsense,
so that pass is the point, not overhead.

## Step 1: Identify the fixed and the current points

Whatever the user provided first, treat as the fixed point (a commit SHA, branch name, tag,
`main`, `HEAD~5`, etc.). Whatever they provided second is the current point; if empty, use
`HEAD`.

If neither was provided, the fixed point is where the work started — the branch point
(`git merge-base HEAD main`) or the SHA before the first change. State the points you
picked before spawning anything, and ask if you cannot pin them down with confidence: both
reviewers waste a long run on the wrong range otherwise.

## Step 2: Spawn both reviewers in parallel

Spawn both subagents in the **same** message so they run concurrently. Codex is slow, and
running them in sequence doubles the wait for no benefit.

Both review skills are user-gated (`disable-model-invocation`), so a subagent cannot invoke
them with the Skill tool — pass the instructions instead. Give each agent this prompt,
substituting `<fixed>` and `<current>`:

- Agent 1: "Run `cat ~/.agents/skills/review-code/SKILL.md` and follow it exactly.
  Fixed point: `<fixed>`. Current point: `<current>`. Reading the diff is your job;
  everything after the findings list is not. Stop at the skill's Step 4 output. Do not edit
  files. Do not run builds, tests, linters, or the app to prove or disprove a finding — I
  do that. Do not draft, prototype, or apply a fix; a concrete suggestion in the finding is
  as far as you go. Stay inside the diff and the files it touches. Report every finding the
  skill's bar admits, even ones you are unsure about — say so and let me judge."
- Agent 2: "Run `cat ~/.agents/skills/review-with-codex/SKILL.md` and follow it exactly.
  Fixed point: `<fixed>`. Current point: `<current>`. Then report the findings and stop. Do
  not review the diff yourself — the skill makes you a courier for Codex's findings, not a
  reviewer. Do not edit files."

Wait for both. If one comes back empty or failed, say so in the report rather than quietly
presenting a one-reviewer result as if it were two.

## Step 3: Verify every finding yourself

Verification is yours alone — do not delegate it, and do not accept a finding because an
agent sounded confident. Open the code each finding points at and decide for yourself
whether the defect is real. You may run builds, tests, or linters to settle a question; the
reviewers were told not to, precisely so that the check happens once, here, by you.

- A finding both reviewers raised independently is a strong signal. Check it anyway, but
  weight it heavily.
- A finding only one raised is not weaker by default — the two have different blind spots,
  which is why there are two.
- Merge duplicates into one entry and note that both reported it.
- When you cannot settle a finding without knowledge you do not have (intended behaviour, a
  product decision, an external system), do not guess and do not silently drop it. Report it
  as unresolved with the specific question that would settle it.

Do not edit files in this skill. Whoever invoked it decides what to fix — a fix you applied
while "just checking" is a decision they never got to make.

## Step 4: Report

Rank confirmed findings by criticality first, then by effort (higher effort last within a
tier), using the same criticality levels as `review-code`: Critical, High, Medium,
Low / Nitpick.

```
## Adversary Review — `<fixed>`…`<current>`
Reviewers: review-code (N findings), codex (M findings)

### Confirmed

#### Critical
1. [SHORT TITLE] — `path/to/File.java:42` — *both* | *review-code* | *codex*
   **Problem:** What is wrong and why it matters.
   **Verified:** What you checked in the code that makes you confident it is real.
   **Suggestion:** Concrete fix or direction.

#### High
2. ...

### Unresolved
- [SHORT TITLE] — `path:line` — *source*. What is blocking a verdict, phrased as the
  question that would settle it.

### Dismissed
- [SHORT TITLE] — `path:line` — *source*. Why it does not hold.
```

Keep the dismissed section — it is short, and it lets the user overrule you when you were
the one who got it wrong. Omit a section only when it is empty.
