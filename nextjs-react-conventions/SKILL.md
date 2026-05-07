---
name: nextjs-react-conventions
description: >
  Enforce organisational TypeScript / Next.js / React coding and testing conventions in any
  TS+React project (detected by a `package.json` listing `next`, `react`, or `react-dom` at
  the repo root or an ancestor directory). Covers idiomatic style (no `any` — define
  interfaces, `??` over `||`, always-braced blocks), data-fetching strategy (fetch in
  server components by default; in client components use `use` or `useSWR`, never
  `useEffect`), and testing rules (no `jest-dom` matchers, `userEvent` over `fireEvent`,
  `resetAllMocks` over `clearAllMocks`, branch coverage on every new conditional). Use this
  skill whenever you write, edit, refactor, or review `.ts` / `.tsx` files in such a
  project, add a component or page, write a hook, fetch data, write a test, or are asked
  anything resembling "add this feature", "fix this bug", "refactor X", "write a test for
  Y", or "improve coverage". Trigger even when the user does not name the skill — these
  conventions are mandatory and ad-hoc edits in these projects are not allowed.
---

# TypeScript / Next.js / React conventions

Apply these rules every time you write or modify TypeScript or TSX in a Next.js or React project (a `package.json` declaring `next`, `react`, or `react-dom` exists at the repo root or an ancestor directory). They encode organisational style and testing standards. The goal is consistency that survives code review without back-and-forth.

If existing code in the file violates a rule, fix it opportunistically only when it is in or directly adjacent to the code you are touching — do not start drive-by reformatting unrelated sections.

## Coding conventions

### 1. Never use `any` — define an interface or type

`any` opts out of the type system and silently propagates. Whenever you reach for it, define a proper `interface` (or `type` alias) instead. For genuinely unknown shapes coming from outside the system, use `unknown` and narrow it. Why: types are documentation enforced by the compiler; once one `any` enters a call chain it tends to spread.

```ts
// good
interface OrderResponse {
  id: string;
  total: number;
  status: 'pending' | 'paid' | 'shipped';
}

async function fetchOrder(id: string): Promise<OrderResponse> { ... }

// bad
async function fetchOrder(id: string): Promise<any> { ... }
```

For external/untrusted data (e.g. parsed JSON, message bus payloads), prefer a runtime validator (zod, valibot, io-ts) and let the validator's inferred type stand in — still no `any`.

### 2. Always prefer `??` over `||` for default values

Use the nullish-coalescing operator `??` when you want to provide a fallback only for `null` / `undefined`. `||` also fires for `0`, `""`, and `false`, which is almost never what you mean for a default. Why: spec-correctness — a count of `0`, an empty string in a search box, or a boolean `false` are all valid values, and `||` silently replaces them.

```ts
// good
const pageSize = props.pageSize ?? 20;
const label = user.displayName ?? 'anonymous';

// bad — when pageSize is 0, you get 20 instead of 0
const pageSize = props.pageSize || 20;
```

`||` is still correct in genuinely boolean contexts (`if (a || b)`). The rule applies to default-value substitution.

### 3. Always brace blocks, even single statements

Every `if`, `else`, `for`, `while`, and `do` body gets `{}`. No "one-liner" `if (x) doThing();`. Why: prevents the dangling-statement bug when someone adds a second line, makes diffs cleaner, and matches Prettier's default. Single-expression arrow functions (`x => x + 1`) are fine — that's an expression body, not a block.

```tsx
// good
if (isLoading) {
  return <Spinner />;
}

// bad
if (isLoading) return <Spinner />;
```

## Data fetching strategy

Next.js gives you server components by default. Use them. Client components are an opt-in (`'use client'`) for interactivity, not for data plumbing.

### 1. Fetch data in server components by default

When a route, page, or layout needs data, fetch it in a server component (`async` component, no `'use client'`). Pass the resolved data down as props. Why: zero client-side waterfall, no loading flicker for the initial render, no exposure of API tokens, free caching from `fetch` / Next's data layer, and the bundle stays smaller.

```tsx
// app/orders/page.tsx — server component, no 'use client'
export default async function OrdersPage() {
  const orders = await getOrders();
  return <OrderList orders={orders} />;
}
```

### 2. In client components, use `use` or `useSWR` — never `useEffect` for fetching

If a component genuinely needs to fetch from the client (interactive filters, polling, user-driven refetches), reach for one of:

- **`use(promise)`** — when a parent (often a server component) hands you a promise. Lets you read its value while letting Suspense handle loading.
- **`useSWR(key, fetcher)`** — when the client owns the request lifecycle: caching, revalidation, mutation, polling. Pair with a `<SWRConfig>` ancestor for shared defaults.

Why not `useEffect`: `useEffect` for fetching reintroduces the very problems server components and SWR were designed to fix — manual loading/error/aborted state, race conditions on rapid prop changes, no caching, no dedup, double-fire in StrictMode. The hook exists, but data fetching is not what it is good at.

```tsx
'use client';
import useSWR from 'swr';

export function OrderRefreshPanel({ orderId }: { orderId: string }) {
  const { data, error, isLoading } = useSWR(`/api/orders/${orderId}`, fetcher);
  if (isLoading) {
    return <Spinner />;
  }
  if (error) {
    return <ErrorBanner error={error} />;
  }
  return <OrderSummary order={data} />;
}
```

```tsx
// parent (server) hands a promise; child (client) reads with `use`
// app/orders/[id]/page.tsx
export default function OrderPage({ params }: { params: { id: string } }) {
  const orderPromise = getOrder(params.id);
  return <OrderDetail orderPromise={orderPromise} />;
}

// components/order-detail.tsx
'use client';
import { use } from 'react';
export function OrderDetail({ orderPromise }: { orderPromise: Promise<Order> }) {
  const order = use(orderPromise);
  return <OrderSummary order={order} />;
}
```

If you find yourself reaching for `useEffect(() => { fetch(...) }, [])`, stop and ask: should this live in a server component? If yes, move it. If genuinely client-side, use SWR.

`useEffect` remains the right tool for non-fetching side effects: subscriptions, event listeners, imperative DOM work, third-party widget setup/teardown.

## Testing conventions

### 1. Write tests for new code; keep existing tests green

Every new component, hook, utility, and bug fix gets at least one test. Before declaring work done, run the project's test command (typically `npm test` / `pnpm test` / `yarn test`) and confirm the suite is green. Do not commit failing tests or untested behaviour.

### 2. Cover every condition (branch coverage)

For every new conditional — `if`/`else`, ternary, `??`, `||`, optional chain, switch case, early return, conditional render `{cond && <X />}` — write at least one test exercising each branch. The mental check: "for each `?` and `&&` and `if` I added, is there a test that hits both sides?" If you cannot easily reach a branch from a test, that's usually a sign the branch is dead code or the component is doing too much.

### 3. `userEvent` over `fireEvent`

Always use `@testing-library/user-event` for simulating interactions, not `fireEvent`. Why: `userEvent` simulates the full sequence a real user produces (focus → keydown → keypress → input → keyup → change), so tests catch keyboard-handling, focus-management, and accessibility bugs that `fireEvent.click` would silently miss.

```ts
// good
import userEvent from '@testing-library/user-event';

it('submits the form', async () => {
  const user = userEvent.setup();
  render(<SignupForm />);
  await user.type(screen.getByLabelText(/email/i), 'a@b.co');
  await user.click(screen.getByRole('button', { name: /sign up/i }));
  // ...
});

// bad
import { fireEvent } from '@testing-library/react';
fireEvent.click(screen.getByRole('button'));
```

Call `userEvent.setup()` once per test (or in a shared fixture). Avoid the older `userEvent.click(...)` static API.

### 4. `resetAllMocks` over `clearAllMocks`

In `beforeEach` / `afterEach` (and `beforeAll` / `afterAll` where appropriate), use `vi.resetAllMocks()` instead of `vi.clearAllMocks()`. Why: `clearAllMocks` only clears call history; stubbed implementations and return values stick around and leak into subsequent tests as a phantom default. `resetAllMocks` clears history *and* removes any `mockImplementation` / `mockReturnValue` set in a prior test, leaving each test with a clean slate.

```ts
import { beforeEach, vi } from 'vitest';

// good
beforeEach(() => {
  vi.resetAllMocks();
});

// bad — leaks mockReturnValue across tests
beforeEach(() => {
  vi.clearAllMocks();
});
```

If you genuinely need to keep an implementation across tests, set it once in `beforeEach` *after* the reset.

### 5. Don't use `jest-dom` matchers — use plain Jest + DOM

Avoid `@testing-library/jest-dom` matchers (`toBeInTheDocument`, `toHaveAttribute`, `toHaveTextContent`, `toBeVisible`, etc.). Use plain Jest assertions against the DOM node. Why: keeps the assertion surface small, makes failures show actual values not opaque "element not in document" messages, and avoids a dependency that frequently churns.

```ts
// good
expect(screen.queryByText('Welcome')).not.toBeNull();
expect(screen.getByRole('link').getAttribute('href')).toBe('/home');
expect(screen.getByRole('button').textContent).toBe('Sign in');

// bad
expect(screen.queryByText('Welcome')).toBeInTheDocument();
expect(screen.getByRole('link')).toHaveAttribute('href', '/home');
expect(screen.getByRole('button')).toHaveTextContent('Sign in');
```

### 6. Asserting absence — use `.toBeNull()` with `queryBy*`

When checking that something is *not* on the page, use a `queryBy*` (which returns `null` on miss) and assert `.toBeNull()`. Do not use `getBy*` — it throws on miss, which gives you a noisy stack trace instead of a clean failure message. `findBy*` waits, so it is also wrong for an absence assertion.

```ts
// good
expect(screen.queryByText('Error')).toBeNull();

// bad — throws "Unable to find element" before the assertion runs
expect(screen.getByText('Error')).toBeNull();
```

For asynchronous absence (something must *stay* gone after a tick), use `waitFor(() => expect(screen.queryByText('Error')).toBeNull())`.

