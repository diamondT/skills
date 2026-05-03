---
name: pom
description: >
  Author or modify Maven `pom.xml` files for Spring Boot projects following strict
  organisational conventions: versions only in `<properties>` + `<dependencyManagement>`,
  required plugins (maven-enforcer-plugin with pedantic-pom-enforcers, spotless, jacoco,
  git-commit-id, native-maven, spring-boot with AOT for Java 25+), and grouped dependency
  ordering. Use this skill whenever the user creates a new `pom.xml`, scaffolds a Spring Boot
  Maven project, adds or upgrades a dependency, configures a Maven plugin, edits parent/BOM,
  or asks anything like "add X to pom", "bump version", "configure plugin Y", "new spring boot
  project". Always apply this skill — do not edit `pom.xml` files ad-hoc without it.
---

# Spring Boot pom.xml conventions

Apply these rules every time you touch a `pom.xml` of a Spring Boot Maven project. The goal is strict, enforceable consistency across the organisation.

## Core rules

### 1. Versions live in `<properties>` only

Every version literal — dependency or plugin — must be declared as a property and referenced as `${...}`. Hard-coded versions inside `<dependency>` / `<plugin>` blocks are forbidden (the enforcer will fail the build). Why: single source of truth, easy upgrades, the pedantic-pom-enforcer requires it.

### 2. Dependency versions only in `<dependencyManagement>`

`<dependencies>` blocks must NOT contain `<version>`. Declare the version once in `<dependencyManagement>` (referencing a `${...}` property), then list the dependency without version in `<dependencies>`. Spring Boot's parent BOM already manages many — only add to `<dependencyManagement>` what the BOM does not cover.

### 3. Plugin versions only in `<properties>`

Plugin `<version>` values must be `${plugin-name.version}`. Property naming convention: `<artifactId-without-maven-plugin-suffix>.version` (e.g. `spotless.version`, `jacoco.version`, `pedantic-pom-enforcers.version`).

### 4. Dependency grouping (order matters)

Inside `<dependencies>`, group with a blank line between groups, in this order:

1. Spring dependencies (`org.springframework.*`, `spring-boot-starter-*`)
2. Dev-only (lombok, spring-boot-devtools, spring-boot-configuration-processor) — `<optional>true</optional>` or `<scope>provided</scope>` as appropriate
3. Third-party runtime (jackson modules, mapstruct, resilience4j, etc.)
4. Spring test (`spring-boot-starter-test`, `spring-security-test`, testcontainers-spring, etc.) — `<scope>test</scope>`
5. Third-party test (assertj, wiremock, awaitility, etc.) — `<scope>test</scope>`

Apply the same grouping inside `<dependencyManagement><dependencies>` when used.

## Required plugins

Every Spring Boot service `pom.xml` must declare ALL of the following under `<build><plugins>`. Do not omit unless the user explicitly opts out.

### maven-enforcer-plugin (organisation rules)

```xml
<plugin>
    <groupId>org.apache.maven.plugins</groupId>
    <artifactId>maven-enforcer-plugin</artifactId>
    <dependencies>
        <dependency>
            <groupId>com.github.ferstl</groupId>
            <artifactId>pedantic-pom-enforcers</artifactId>
            <version>${pedantic-pom-enforcers.version}</version>
        </dependency>
    </dependencies>
    <executions>
        <execution>
            <id>enforce-organisation-rules</id>
            <goals>
                <goal>enforce</goal>
            </goals>
            <phase>validate</phase>
            <configuration>
                <rules>
                    <dependencyConvergence/>
                    <requireUpperBoundDeps/>
                    <banDuplicatePomDependencyVersions/>
                    <banDistributionManagement>
                        <allowSite>true</allowSite>
                    </banDistributionManagement>
                    <requireSameVersions>
                        <dependencies>
                            <dependency>${project.groupId}</dependency>
                        </dependencies>
                    </requireSameVersions>
                    <compound
                            implementation="com.github.ferstl.maven.pomenforcers.CompoundPedanticEnforcer">
                        <enforcers>DEPENDENCY_CONFIGURATION</enforcers>
                        <manageDependencyVersions>true</manageDependencyVersions>
                        <allowUnmangedProjectVersions>true</allowUnmangedProjectVersions>
                        <manageDependencyExclusions>true</manageDependencyExclusions>
                    </compound>
                </rules>
            </configuration>
        </execution>
    </executions>
</plugin>
```

The maven-enforcer-plugin version comes from the Spring Boot parent BOM — do NOT add a `<version>` here. Only `pedantic-pom-enforcers.version` lives in `<properties>`.

### spotless-maven-plugin (auto-style on validate)

```xml
<plugin>
    <groupId>com.diffplug.spotless</groupId>
    <artifactId>spotless-maven-plugin</artifactId>
    <version>${spotless.version}</version>
    <configuration>
        <java>
            <googleJavaFormat/>
        </java>
    </configuration>
    <executions>
        <execution>
            <id>auto-style</id>
            <goals>
                <goal>apply</goal>
            </goals>
            <phase>validate</phase>
        </execution>
    </executions>
</plugin>
```

### git-commit-id-maven-plugin

```xml
<plugin>
    <groupId>io.github.git-commit-id</groupId>
    <artifactId>git-commit-id-maven-plugin</artifactId>
</plugin>
```

No `<version>` — inherited from `spring-boot-starter-parent`. Defaults are fine; only override if the user asks.

### jacoco-maven-plugin

```xml
<plugin>
    <groupId>org.jacoco</groupId>
    <artifactId>jacoco-maven-plugin</artifactId>
    <version>${jacoco.version}</version>
    <executions>
        <execution>
            <id>jacoco-initialize</id>
            <goals>
                <goal>prepare-agent</goal>
            </goals>
        </execution>
        <execution>
            <id>jacoco-site</id>
            <phase>package</phase>
            <goals>
                <goal>report</goal>
            </goals>
        </execution>
    </executions>
</plugin>
```

### native-maven-plugin (GraalVM native image)

```xml
<plugin>
    <groupId>org.graalvm.buildtools</groupId>
    <artifactId>native-maven-plugin</artifactId>
</plugin>
```

No `<version>` — inherited from `spring-boot-starter-parent`.

### spring-boot-maven-plugin

Always present. If the project's `<java.version>` (or `maven.compiler.release`) is **25 or greater**, add the `process-aot` execution:

```xml
<plugin>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-maven-plugin</artifactId>
    <executions>
        <execution>
            <id>process-aot</id>
            <goals>
                <goal>process-aot</goal>
            </goals>
        </execution>
    </executions>
</plugin>
```

For Java < 25, omit the `<executions>` block.

## Workflow

### When creating a new pom.xml

1. Ask (or infer) Java version, Spring Boot version, groupId, artifactId, project name.
2. Use `spring-boot-starter-parent` as `<parent>`.
3. Define `<properties>`: `java.version`, all `*.version` properties for plugins listed above, and any third-party dependency versions you'll add.
4. Add `<dependencyManagement>` only for non-Spring-Boot-BOM dependencies.
5. Populate `<dependencies>` in the 5 grouped order above.
6. Add all required plugins under `<build><plugins>`.
7. Apply AOT execution to spring-boot-maven-plugin only if Java ≥ 25.

### When editing an existing pom.xml

1. **Adding a dependency**: place under the correct group (Spring / dev / 3rd-party / Spring test / 3rd-party test). If a version is needed, add a `${name.version}` property AND a `<dependencyManagement>` entry — never inline.
2. **Bumping a version**: change only the property value.
3. **Adding/configuring a plugin**: declare its `${name.version}` in `<properties>` first; do not inline the version.
4. **Audit**: if you notice violations of rules 1–4 in unrelated parts of the file (inline versions, mis-grouped deps), surface them to the user and offer to fix in the same edit.
5. After every change, mentally re-run the enforcer rules: dependencyConvergence, requireUpperBoundDeps, banDuplicatePomDependencyVersions, manageDependencyVersions. Fix anything that would fail.

## Common pitfalls

- Do NOT add `<version>` to a plugin already managed by `spring-boot-starter-parent`'s pluginManagement (e.g. `maven-compiler-plugin`, `maven-surefire-plugin`, `maven-enforcer-plugin`). Spring Boot pins them — overriding triggers `requireUpperBoundDeps`/`dependencyConvergence` failures.
- Do NOT mix `<scope>test</scope>` deps into the main groups.
- Do NOT use `<dependencies>` direct version when a `<dependencyManagement>` entry exists — `manageDependencyVersions=true` will fail.
- Lombok belongs in the dev-only group with `<optional>true</optional>`, not in 3rd-party.

## Property naming reference

Only the plugins NOT managed by `spring-boot-starter-parent` need a version property:

| Plugin / dep                  | Property                          | Inherited from parent? |
|-------------------------------|-----------------------------------|------------------------|
| pedantic-pom-enforcers        | `pedantic-pom-enforcers.version`  | no — set property      |
| spotless-maven-plugin         | `spotless.version`                | no — set property      |
| jacoco-maven-plugin           | `jacoco.version`                  | no — set property      |
| git-commit-id-maven-plugin    | —                                 | yes                    |
| native-maven-plugin           | —                                 | yes                    |
| maven-enforcer-plugin         | —                                 | yes                    |
| Java                          | `java.version`                    | n/a                    |

## Resolving versions

When you need a version (Spring Boot parent, `pedantic-pom-enforcers.version`, `spotless.version`, `jacoco.version`, or any third-party dep), look up the **latest stable release at the time the skill runs**. Do not hard-code values you remember from training — they go stale.

Lookup options, in order of preference:

1. `https://search.maven.org/solrsearch/select?q=g:<groupId>+AND+a:<artifactId>&rows=1&wt=json` — returns `latestVersion` in JSON.
2. `https://repo1.maven.org/maven2/<group/path>/<artifact>/maven-metadata.xml` — read `<release>`.
3. WebFetch on the artifact's mvnrepository.com page if the above are unavailable.

Skip pre-releases (`*-M*`, `*-RC*`, `*-alpha*`, `*-beta*`, `*-SNAPSHOT`). If the user pinned a version explicitly, honour that instead.

## Starter template

When creating a brand new `pom.xml`, start from `assets/template.xml` (sibling file in this skill). Replace the `__PLACEHOLDERS__`, resolve latest versions per the rules above, and prune sections the user does not need (e.g. test starters they will not use). The template already encodes correct ordering, grouping, and plugin configuration.
