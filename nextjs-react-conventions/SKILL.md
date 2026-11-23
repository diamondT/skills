---
name: nextjs-react-conventions
description: >
  Generic, composable TypeScript / Next.js / React coding and testing conventions (style,
  data-fetching, branch coverage). Use whenever you write, edit, refactor, review, or test
  `.ts` / `.tsx` files in a project whose `package.json` lists `next`, `react`, or
  `react-dom` at the repo root or an ancestor directory. Triggers on any request to write or review
  TypeScript / Next.js / React code where context-specific skills or instructions do not already
  cover style.
---

# TypeScript / Next.js / React conventions

Apply these rules every time you write or modify TypeScript or TSX in a Next.js or React project (a `package.json`
declaring `next`, `react`, or `react-dom` exists at the repo root or an ancestor directory). They encode organisational
style and testing standards. The goal is consistency that survives code review without back-and-forth.

If existing code in the file violates a rule, fix it opportunistically only when it is in or directly adjacent to the
code you are touching — do not start drive-by reformatting unrelated sections.

## Coding conventions

- never use `any` — define an interface or type
- always prefer `??` over `||` for default values. `||` is still correct in genuinely boolean contexts (`if (a || b)`).
  The rule applies to default-value substitution.
- always brace blocks, even single statements

## Data fetching strategy

Next.js gives you server components by default. Use them. Client components are an opt-in (`'use client'`) for
interactivity, not for data plumbing.

- fetch data in server components by default
- in client components, use `use` or `useSWR` — never `useEffect` for fetching. If you find yourself reaching for
  `useEffect(() => { fetch(...) }, [])`, stop and ask: should this live in a server component? If yes, move it. If
  genuinely client-side, use SWR. `useEffect` remains the right tool for non-fetching side effects: subscriptions, event
  listeners, imperative DOM work, third-party widget setup/teardown.

## Testing conventions

- write tests for new code; keep existing tests green
- cover every condition (branch coverage)
- always `userEvent` over `fireEvent` for simulating interactions. Call `userEvent.setup()` once per test (or in a
  shared fixture). Avoid the older `userEvent.click(...)` static API.
- always use `resetAllMocks` over `clearAllMocks`. In `beforeEach` / `afterEach` (and `beforeAll` / `afterAll` where
  appropriate), use `vi.resetAllMocks()` instead of `vi.clearAllMocks()`.
- don't use `jest-dom` matchers — use plain Jest + DOM
- asserting absence — use `.toBeNull()` with `queryBy*`

## Comments

- default to no comments
- only comment when the *why* is non-obvious: hidden constraint, subtle invariant, workaround for a specific bug,
  behavior that would surprise a reader
- do not explain *what* the code does — well-named identifiers do that
- either describe the *why* or omit the comment entirely
