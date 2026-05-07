## Coding conventions
- **never** use "any". define type interfaces instead.
- **always** prefer ?? instead of ||
- **always** enclose code blocks in braces {}, even if single line

## Data Fetching Strategy

- always prefer fetching data in server components
- if you need to fetch data in a client component utilize the `use` or `useSWR` hooks
- never use `useEffect` for fetching data in client components

## Testing
- write tests for new code, make sure existing tests are passing
- ensure condition (branch) coverage, i.e. test all conditions
- **Unit Tests**: always favor `userEvent from "@testing-library/user-event"` over `fireEvent`
- **Unit Tests**: always favor `resetAllMocks()` over `clearAllMocks()` in `beforeAll` or `afterAll` functions
- **Unit Tests**: don't use jest-dom. for example favor `.not.toBeNull()` over `.toBeInTheDocument()` and
  `.getAttribute('KEY').toBe('VALUE')` over `.toHaveAttribute('KEY', 'VALUE')`
- when testing if something does not appear in a page, use `.toBeNull()`, e.g. `expect(screen.getByText("foo")).toBeNull()`

