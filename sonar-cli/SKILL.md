---
name: sonar-cli
description: >
  List SonarQube issues for a pull request (or project) using the `sonar` CLI
  (SonarSource/sonarqube-cli). Use whenever the user wants to see, check, or
  review SonarQube / SonarCloud findings — e.g. "what does sonar say about PR 73",
  "list sonar issues for ecomm-ui-payments", "check code quality issues on this
  pull request", "any blockers from sonar on my PR", "sonar list issues". Trigger
  even when the user names only the project and PR number without saying "sonar
  list issues", as long as SonarQube/Sonar issues for a PR are clearly meant.
---

# Listing SonarQube issues with the `sonar` CLI

The job here is almost always the same: the user has a pull request and wants to
know what SonarQube flagged on it. Build the right `sonar list issues` command,
run it, and report back the findings in a way that's useful to act on.

## The command

```
sonar list issues --project <PROJECT_KEY> --pull-request <PR_ID>
```

`--project` and `--pull-request` are the two parameters that matter. The PR id is
the pull request number on the host (e.g. the Bitbucket/GitHub PR number), not a
Sonar-internal id.

**Example:**

```
sonar list issues --project ecomm-ui-payments --pull-request 73
```

Get the project key and PR id from the user. If only one is given, ask for the
other — don't guess a project key, since it must match exactly what's configured
in SonarQube. If the working directory has a `sonar-project.properties`, the
project key may be auto-detected and `--project` can be omitted; prefer being
explicit when you know the key.

## Choosing the output format

`--format` controls the output: `json` (default), `table`, `csv`, or `toon`.

You are reading this output to summarize it, so pick a machine-parseable format
rather than `table`. Use `--format json` for reliable parsing. `toon` is a
token-efficient, YAML-flavoured format built for LLMs — reach for it instead when
a PR has many issues and you want to keep the output small.

```
sonar list issues --project ecomm-ui-payments --pull-request 73 --format json
```

## Narrowing the results

Add these only when the user asks for them — by default list everything on the PR:

- `--severities BLOCKER,CRITICAL,MAJOR,MINOR,INFO` — keep only the given severities (comma-separated, no spaces).
- `--statuses OPEN,CONFIRMED` — filter by issue status.
- `--page-size <1-500>` / `--page <n>` — paginate. If results look truncated, raise the page size or fetch the next page so you don't miss issues.

## Reporting back

After running the command, summarize for the user rather than dumping raw JSON:
group by severity (lead with blockers/criticals), and for each issue give the
rule message, the file and line, and the severity. Call out clearly when the PR
is clean (no issues) — that's a useful answer too.

## Prerequisites and troubleshooting

The CLI needs to be installed and authenticated against the right SonarQube
server before any command works.

- **`sonar: command not found`** — the CLI isn't installed. Point the user to the
  install instructions at https://github.com/SonarSource/sonarqube-cli (don't
  silently install it for them).
- **Authentication / 401 / "not authenticated" errors** — the user needs to log
  in. Interactively that's `sonar auth login` (add `--server <url>` for a
  self-hosted instance); check state with `sonar auth status`. For CI/automation
  it's driven by env vars: `SONARQUBE_CLI_TOKEN`, `SONARQUBE_CLI_SERVER`
  (self-hosted server URL), and `SONARQUBE_CLI_ORG` (SonarQube Cloud org). Tell
  the user which one is missing rather than attempting to set tokens yourself.
- **No issues returned but you expected some** — confirm the PR has been analysed
  by SonarQube (a scan must have run for that pull request), and that the project
  key and PR id are correct.

## Scope

This skill covers listing issues for a pull request. Other `sonar` subcommands
are out of scope here — don't improvise them.
