---
name: java-conventions
description: >
  Gemeric, composable Java coding and testing conventions (style, idioms, JaCoCo branch
  coverage). Use whenever you write, edit, refactor, review, or test `.java` files across
  all Java contexts. Triggers on any request to write or review Java code where context-specific 
  skills or instructions do not already cover style.
---

# Scope

- Language-level rules for Java 25 only — syntax, style, naming, visibility, structure, methods, streams, exceptions, comments.
- If you find existing code in the file that already violates a rule, fix it opportunistically only if it is in or directly adjacent to the code you are touching — do not start drive-by reformatting unrelated sections.

## Java syntax

- always use braces, even for single-statement blocks
- use modern syntax naturally: `var`, records, sealed types, pattern matching, text blocks, switch expressions
- always prefer `var` for local variables where the compiler can infer the type
- use module imports (e.g. `import module java.net.http;`) over individual type imports
- do not import packages from `java.base` — it is automatically available
- use switch expressions with arrow syntax (`case X -> ...`) over old `case X:` statements with `break`
- use pattern matching for `instanceof` — `if (o instanceof String s)` over cast-and-assign
- use pattern matching in `switch` for type-based dispatch
- use the diamond operator `<>` for generic type inference
- never use raw generic types — always parameterize
- prefer `void main()` / `void main(String... args)` over `public static void main(String[] args)`; instance main, not static
- use records + Lombok `@Builder` for DTOs
- use `Optional.ofNullable().map().orElse(...)` over ternaries for null checks

## Java SE APIs

- use Java SE APIs over writing custom code — the standard library has it, usually in `java.util`, `java.nio.file`, `java.net.http`, or `java.time`
- prefer the most specific Java SE type for the domain — `Path` over `String`, `URI` over `String`, `Duration` over `long millis`, `Instant`/`LocalDate` over `Date`/`long`

## Spring APIs

- use Spring's `StringUtils` / `CollectionUtils` over hand-rolled null/empty checks

## Testing conventions
- never enable Mockito lenient mode
- aim for 100% branch (condition) coverage, validated via JaCoCo. Verify by running JaCoCo and reading the report — do not eyeball it.
- express variations of the same behavior (inputs, boundaries, edge cases) as one parameterized test, not as separate methods

## Interfaces & Classes

- for stateless or procedural logic, prefer interfaces with `static` methods over classes with private constructors
- prefer composition over inheritance

## Stream & Collections

- prefer fluent streams over imperative loops
- avoid `forEach`; prefer terminal operations that return values
- prefer `Stream.of` over `Arrays.stream` for known elements
- avoid creating unnecessary intermediate collections when streaming arrays
- prefer `Stream.gather(...)` with a `Gatherer` (Java 24+) over custom `Spliterator` or stateful `forEach` for stream transformations that need to keep state across elements or flush a remainder at end-of-stream
- prefer returning empty collections (`List.of()`, `Set.of()`, `Map.of()`) instead of `null`

## Code Style

- KISS and YAGNI — always implement the simplest possible solution that works
- use text blocks (`"""`) for all multiline string content (JSON, SQL, HTML, help/usage text, templates) — never `+`-concatenation or embedded `\n` escapes
- prefer `String.formatted()` (instance) over `String.format(...)` (static) for readability at the call site
- always prefer imports over fully qualified class names
- separate side effects from conditions — do the work first, then branch on the result; keep the `if` a pure decision
- avoid `Optional` as a parameter type; use `Optional` as a return type only when absence is a meaningful part of the contract

## Exceptions

- never throw raw `java.lang.Exception` or `RuntimeException` directly — throw a specific subclass
- do not re-throw with `throw e` adding no value
- do not catch and silently ignore exceptions — at minimum, log with context or rethrow wrapped
- use the underscore `_` for unused catch parameters (`catch (IOException _)`) instead of named variables like `e` or `ignored`
- create custom exceptions only when they significantly improve robustness or maintainability

## Comments & JavaDoc

- default to no comments
- only comment when the *why* is non-obvious: hidden constraint, subtle invariant, workaround for a specific bug, behavior that would surprise a reader
- do not explain *what* the code does — well-named identifiers do that
- do not write JavaDoc that restates the method signature or rephrases the code
- either describe the *why* or omit the comment entirely
- when JavaDoc is written, always use Markdown JavaDoc (`///`, JEP 467); never use HTML-tagged `/** */` blocks

