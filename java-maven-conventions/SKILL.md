---
name: java-maven-conventions
description: >
  Enforce organisational Java coding and testing conventions in any Java + Maven project
  (detected by a `pom.xml` at the repo root or in a parent directory). Covers idiomatic
  style (always `var`, always braces, fluent streams over loops, records + Lombok `@Builder`
  for DTOs, `Optional.ofNullable().map().orElse(...)` over ternaries, `StringUtils` /
  `CollectionUtils` over hand-rolled null/empty checks) and testing rules (no Mockito
  lenient mode, write tests for new code, 100% branch coverage validated via the JaCoCo
  report). Use this skill whenever you write, edit, refactor, or review `.java` files in a
  Maven project, add new methods, write tests, or are asked anything resembling "add this
  feature", "fix this bug", "refactor X", "write a test for Y", or "improve coverage".
  Trigger even when the user does not name the skill — these conventions are mandatory and
  ad-hoc Java edits in these projects are not allowed.
---

# Java + Maven coding conventions

Apply these rules every time you write or modify Java code in a Maven project (a `pom.xml` exists at the repo root or an ancestor directory). They encode organisational style and testing standards. The goal is consistency that survives code review without back-and-forth.

If you find existing code in the file that already violates a rule, fix it opportunistically only if it is in or directly adjacent to the code you are touching — do not start drive-by reformatting unrelated sections.

## Coding conventions

### 1. Always use braces, even for single-statement blocks

Every `if`, `else`, `for`, `while`, `do`, and lambda body that contains a statement gets `{}`. No "one-liner" `if (x) doThing();`. Why: prevents the classic dangling-statement bug when someone later adds a second line, and keeps diffs clean.

```java
// good
if (user.isActive()) {
    notify(user);
}

// bad
if (user.isActive()) notify(user);
```

### 2. Always prefer `var` for local variables

Use `var` for every local variable declaration where the compiler can infer the type — including loop variables, lambda parameters where allowed, and `try`-with-resources. Why: less noise, easier rename refactors, the right-hand side is already authoritative. The only time you fall back to an explicit type is when the inferred type would be wrong (e.g. you need a supertype reference) or when the RHS is `null` / a diamond `<>` with no context.

```java
// good
var orders = orderRepository.findByCustomerId(id);
for (var order : orders) { ... }

// bad
List<Order> orders = orderRepository.findByCustomerId(id);
```

`var` applies only to locals — fields, method parameters, and return types still need explicit types.

### 3. Fluent streams instead of imperative loops

When transforming, filtering, grouping, or reducing collections, reach for `Stream` / `Collectors` rather than a `for` loop with a mutable accumulator. Why: intent reads top-to-bottom, no temporary state to mis-mutate, plays well with `Optional` and `Collectors.toMap` / `groupingBy`.

```java
// good
var activeEmails = users.stream()
    .filter(User::isActive)
    .map(User::email)
    .toList();

// bad
var activeEmails = new ArrayList<String>();
for (var u : users) {
    if (u.isActive()) {
        activeEmails.add(u.email());
    }
}
```

A plain `forEach` over a collection just to call a void method is fine and often clearer than a stream — don't force a stream when there is no transformation.

### 4. Records + Lombok `@Builder` for DTOs

Data carriers (request bodies, response payloads, internal value objects, event payloads) are Java `record`s annotated with Lombok `@Builder`. Use `@Builder(toBuilder = true)` whenever a caller needs to derive a modified copy (`existing.toBuilder().status(NEW).build()`). Why: records give immutability, equality, and `toString` for free; `@Builder` keeps construction readable when there are more than two or three fields; `toBuilder` avoids hand-rolled "with..." copy methods.

```java
@Builder(toBuilder = true)
public record OrderDto(
    UUID id,
    String customerEmail,
    BigDecimal total,
    OrderStatus status
) {}
```

Reserve classes for things that genuinely need mutability, inheritance, or JPA entity semantics.

### 5. `Optional.ofNullable().map().orElse(...)` over ternaries for null checks

When deriving a value from a possibly-null reference, use the `Optional` chain instead of `x != null ? f(x) : fallback`. Why: it composes (multiple `.map` steps), the fallback is explicit, and it reads as "if present, transform; otherwise default" rather than as a conditional.

```java
// good
var displayName = Optional.ofNullable(user)
    .map(User::name)
    .orElse("anonymous");

// bad
var displayName = user != null ? user.name() : "anonymous";
```

For deeper chains (`a?.b?.c`), the `Optional` form scales; the ternary form does not. Don't wrap an already non-null value in `Optional.ofNullable` just to call `.map` — only use it where the source can actually be null.

### 6. Spring `StringUtils` / `CollectionUtils` over hand-rolled null/empty checks

Use Spring's `org.springframework.util.StringUtils` (`hasText`, `hasLength`) and `org.springframework.util.CollectionUtils` (`isEmpty`) instead of `s == null || s.isEmpty()` or `list == null || list.isEmpty()`. Why: a single call documents intent, handles null safely, and the Spring variants come for free with any Spring Boot project — no extra dependency. Use Spring's `StringUtils`, not Apache Commons' — these projects standardise on the Spring one to avoid two libraries with the same class name colliding in imports.

Mapping the concepts:
- "not null and not empty string" → `StringUtils.hasLength(s)`
- "not null and contains non-whitespace" (the usual one) → `StringUtils.hasText(s)`
- "null or empty/blank" → negate the above (`!StringUtils.hasText(s)`)
- "list null or empty" → `CollectionUtils.isEmpty(list)`

```java
// good
if (!StringUtils.hasText(input)) { return defaultValue; }
if (CollectionUtils.isEmpty(orders)) { return List.of(); }

// bad
if (input == null || input.isBlank()) { return defaultValue; }
if (orders == null || orders.isEmpty()) { return List.of(); }
```

If a Spring Boot project for some reason lacks `spring-core` on the classpath (very rare), add it via the `pom` skill rather than inlining the null/empty check or pulling in Apache Commons just for this.

## Testing conventions

### 1. Never enable Mockito lenient mode

Do not use `Mockito.lenient()`, `@MockitoSettings(strictness = Strictness.LENIENT)`, or any other mechanism that downgrades strictness. Why: lenient mode hides unused stubs, which routinely mask "the test passed but never exercised the code path I thought it did" bugs. If a stub is reported as unused, that is real signal — either the production code does not call it (delete the stub, or fix the production code) or the test arranges more than it asserts (split the test). Strict stubbing is a feature, not a nuisance.

```java
// good — strict by default
@ExtendWith(MockitoExtension.class)
class OrderServiceTest { ... }

// bad
@MockitoSettings(strictness = Strictness.LENIENT)
class OrderServiceTest { ... }

// bad
lenient().when(repo.find(any())).thenReturn(...);
```

### 2. Write tests for new code; keep existing tests green

Every new public method, branch, and bug fix gets at least one test. Before declaring work done, run the project's test command (typically `mvn test` or `mvn verify`) and confirm the suite is green. Do not commit if tests are failing or if you skipped writing tests for new behaviour because "it's obvious".

### 3. 100% branch (condition) coverage, validated via JaCoCo

Aim for 100% branch coverage on code you add or substantially modify. Branches include both legs of every `if`, every `case` of a `switch`, every short-circuit `&&` / `||`, every ternary, and the present/empty paths of every `Optional`. Verify by running JaCoCo and reading the report — do not eyeball it.

```bash
mvn clean verify           # runs tests + JaCoCo report
# open target/site/jacoco/index.html
# drill into your changed class and confirm "Missed Branches" = 0
```

If the project is multi-module, the per-module report lives at `<module>/target/site/jacoco/index.html`. If JaCoCo is not configured, add it via the `pom` skill before claiming coverage.

When 100% is genuinely impractical (defensive `default` in a sealed switch, a `private` constructor on a utility class, a generated method), document the gap in the test class with a one-line comment explaining why — but treat it as the rare exception, not the default.

## Working order for a typical change

1. Read the surrounding code; note any local idioms that override these defaults (rare, but possible).
2. Make the change, applying the rules above.
3. Add/extend tests for every new branch.
4. Run `mvn verify` and open the JaCoCo report; drive missed branches to zero.
5. Re-read the diff with these rules in mind before handing off.
