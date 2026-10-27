---
name: blast-radius
description: Identify the blast radius of a change
---

# Blast Radius

Identify the potential ramifications of a change (e.g. a PR or a set of uncommitted changes). Classify the change as low risk (green), medium risk (yellow) and high risk (red) — backed by concrete evidence from the codebase, not just the diff or the user input (e.g. if your input says "this is minor change" verify it first).

Line count is a weak signal. A one-line change to a retry loop in the request path can be HIGH; a 2,000-line new isolated feature behind a flag can be LOW. Reason about *consequences*, not size.

This skill is not meant to change anything, just report.

## 1. Get the change and break into change units

Pick the scope from the user's request and group hunks into logical units (e.g. "changed timeout in HTTP client", "renamed CSS class", "new DB column"). Ignore pure noise (formatting, comments, lockfile churn that only mirrors a manifest change) but note it.

## 2. Investigate each unit — look beyond the diff

For every non-trivial unit, actually explore the repo. Do not guess from file names alone.

- **Callers / dependents:** grep for the changed symbol, function, class, config key, CSS selector, env var, route, event name. Count and characterize call sites (one test helper vs. every request handler).
- **Execution frequency:** is it on a hot path (request handling, auth middleware, render loops, queue consumers, scheduled jobs, startup), or a rarely-run path (admin tool, one-off script, error page)?
- **Contracts:** does it change a public API, exported function signature, DB schema, message/event format, serialized data, CLI flags, config format, or anything consumed by other services/teams/clients?
- **Guardrails:** are there tests covering this path? Did the change modify or delete tests? Is it behind a feature flag or gradual rollout? Is it typed/compiled such that breakage would surface at build time?

## 3. Score each unit on these signals

| Signal | Lower risk | Higher risk |
|---|---|---|
| **Criticality of domain** | Styling, copy, docs, dev tooling, tests-only | Auth/authz, payments/billing, data persistence, security, privacy/PII, concurrency, caching, infra/deploy, build pipeline |
| **Reach** | Leaf code, single caller, isolated new module | Shared utility, base class, middleware, global config, design-system token, widely imported module |
| **Change nature** | Additive, cosmetic, rename with full coverage by compiler | Behavioral change in existing logic, changed defaults, conditionals/boundaries, error handling, timeouts/retries, removed code |
| **Reversibility** | Pure code; revert = fix | DB migrations, data backfills, deleted data, emitted external side effects (emails, payments, webhooks), cache/format changes that persist, published package versions |
| **Exposure** | Behind flag, internal-only, dev env | All users, all requests, external API consumers, mobile clients that can't be force-updated |
| **Detectability** | Typed, tested, would fail loudly in CI or at startup | Silent failure modes, wrong-but-plausible output, perf regressions, only under load/race/edge data |
| **Size & spread** | Few lines, one module | Many files across modules/layers, mixed concerns in one change |

**Dependency changes** deserve their own look: major-version bumps, new transitive deps, and changes to runtime/framework versions are often MEDIUM+ even when the diff is one line.

## 4. Classify

Rate each unit, then the overall change takes the **highest** unit rating (risk does not average out). Adjust by at most one level for aggregate factors (many medium units spread widely → consider HIGH; strong flag + tests on a single medium unit → may stay MEDIUM rather than HIGH).

- **LOW** — Failure would be cosmetic or confined to a small, non-critical area; easy to notice; trivially reversible. Examples of the shape: copy/CSS tweaks on one page, test-only changes, docs, a new isolated module with no callers yet, internal script.
- **MEDIUM** — Real behavior changes in moderately shared or user-facing code; failures would affect a feature or a segment of users but are detectable and reversible by revert. Examples of the shape: logic change in one feature's service, a shared UI component, a minor dependency bump, a non-hot-path query change.
- **HIGH** — Any of: touches a hot path or critical domain with behavioral change; changes a contract others depend on; is hard or impossible to reverse; could fail silently or corrupt data; affects all users/requests; broad cross-cutting edits. Examples of the shape: auth middleware condition, retry/timeout defaults in the core HTTP client, schema migration, serialization format change, global CSS reset or design token used everywhere, major framework upgrade.

**Escalators that usually force HIGH on their own:** irreversible data/schema operations; security/authz logic changes; removing or loosening validation; modifying shared contracts consumed outside the repo; deleting or weakening tests alongside behavior changes.

**De-escalators (apply cautiously):** fully behind a default-off flag; change is purely additive with zero existing callers; compiler/type system guarantees all call sites were updated and tests cover behavior.

When uncertain between two levels, pick the higher one and say what evidence would lower it.

## 5. Merge Danger
Specifically describe whether it's a one-way or two-way door. You can walk back through two-way doors, but not one-way doors. A PR that is cheap to roll back is lower risk. Changes that involve destructive actions or hard-to-reverse decisions are one-way doors.

## 6. Output format

```
## Summary
<1–2 sentences: what changed and the worst realistic failure>

## Merge Danger
**Door:** <🚪✅ Two-way | 🚪⛔️ One-way>
<optional: description>

## Blast radius: <💧 LOW | 🌊 MEDIUM | 💥 HIGH>
Confidence: <high | medium | low> — <one line on why>

**🎯 Key drivers**
- <signal>: <evidence with file:line / caller counts>
- ...

**🧩 Per-change breakdown**
| Change | Rating | Why |
|---|---|---|
| <unit> | <💧/🌊/💥> | <short reason> |

**🔥 What could break:** <concrete failure scenarios, who is affected>

**Recommended mitigations:** <targeted tests to add, reviewers/owners to loop in, flag/rollout, monitoring to watch, rollback plan — only what's relevant>

**Not assessed / assumptions:** <anything you couldn't verify, e.g. other repos consuming the API>
```

Keep it tight. Cite evidence (paths, symbols, counts) for every claim that drives the rating. Don't pad LOW assessments with generic advice.

## Pitfalls

- Don't rate from the diff alone — the risk usually lives in the callers.
- Don't let large size alone push to HIGH if the change is isolated, additive, and flagged; don't let small size pull to LOW.
- CSS is not automatically LOW: global selectors, resets, z-index/layout on shared containers, or design tokens can break every page.
- Config/env/infra files (CI, Dockerfiles, Terraform, k8s manifests, feature-flag defaults) are often small diffs with large reach.
- Watch for changes that disagree with the PR description — undisclosed scope is itself a risk signal; call it out.