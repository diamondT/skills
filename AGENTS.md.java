Use the `java-maven-conventions` skill.

## Build Commands

```bash
mvn clean package          # build (includes spotless format + enforcer on validate phase)
mvn test                   # run tests
mvn test -Dtest=TestName   # run single test
mvn spotless:apply         # format code (Google Java Format)
mvn spotless:check         # check formatting without applying
```
