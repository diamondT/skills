---
name: hotfix-release-report
description: Publish hotfix release Confluence page and email, close hotfix Jira issues.
disable-model-invocation: true
---

# Hotfix release report

Four steps, in order: **Jira → Confluence → email → close Jira issues**. Each step
feeds the next (issues → page URL → email link). Closing the issues comes last because
it empties the filter.

Invoking this skill is the go-ahead to publish the Confluence page, edit the parent
page, and comment on and close the issues. Stop and ask only on anomalies: 0 issues,
title already exists, auth failures, an issue stuck before Done.

## Fixed values

| What | Value |
|---|---|
| Jira filter | `15341` ("NextComm Hotfix (current)") — use another ID if the user gives one |
| Site | `pmmretail.atlassian.net` (confirm with `acli jira auth status`) |
| Confluence cloudId | `769d4918-7836-47b8-aecf-ccca144cc71f` (from `https://<site>/_edge/tenant_info`) |
| Space | `ITWEB`, spaceId `1130790912` |
| Parent page | `4201840645` — NextCommerce Hotfix Releases |
| Page title | `Hotfix // dd-mm-yyyy` — today's date unless the user gives another |
| Jira comment | `deployed to prod on dd-mm-yyyy` — same date as the page title |
| Jira workflow | `Ready for Production` → `Verification` → `Done` |
| Email subject | `NextCommerce Production release` |
| Email To | v.skaraki, p.panagakou, n.chytiris, m.melissianou `@publicnext.gr` (`TO` in the script) |
| API token | `~/.config/atlassian/token` (scoped, `create:page`) |

## Setup

```bash
S=<this skill dir>/scripts/hotfix_report.py
C=<this skill dir>/scripts/close_issues.sh
W=/tmp/hotfix-$(date +%Y%m%d); mkdir -p "$W"
DATE=$(date +%d-%m-%Y)
TITLE="Hotfix // $DATE"
SITE=pmmretail.atlassian.net
CLOUD=769d4918-7836-47b8-aecf-ccca144cc71f
EMAIL=$(acli jira auth status | awk '/Email:/{print $2}')
```

Shell state doesn't persist between Bash calls — re-declare what each call needs.
Run the script with `python3 -I "$S" ...`.

## 1. Jira: filter → issues

```bash
JQL=$(acli jira filter view --id 15341 --json | jq -r .jql)
acli jira workitem search --jql "$JQL" --fields "key,issuetype,summary" --paginate --json > "$W/issues.json"
jq length "$W/issues.json"
python3 -I "$S" markdown --issues "$W/issues.json" --site "$SITE"
```

- Note: `filter view` needs `--id`; `filter get` is deprecated.
- Use `--paginate` so nothing is truncated.
- "Issue Description" = summary. The real description field is long ADF with images — unusable in a table.
- Don't use `.self` from the results for links; it's an internal host. The script builds `https://<site>/browse/<KEY>`.
- 0 issues → stop and tell the user (the filter only shows issues not yet Done).

Show the user the JQL and the markdown table (columns: Issue, Issue Type, Issue Description).

## 2. Confluence: create page, link from parent

acli (checked 1.3.39) has no `confluence page create` — only `page view`. Create and
update go through REST v2 with curl. If `acli confluence page --help` ever lists
`create`, prefer it.

**Token gotchas** (both cost time before):
- Scoped tokens work **only** via `https://api.atlassian.com/ex/confluence/<cloudId>/...`. The site URL returns 401.
- The token has write scope only, so GETs (e.g. "who am I") return 401 even with a valid token. Do all reads with acli (OAuth) and use the token only for POST/PUT.

If `~/.config/atlassian/token` is missing, ask the user to create a scoped token with
`create:page` at https://id.atlassian.com/manage-profile/security/api-tokens and save it:
`! mkdir -p ~/.config/atlassian && umask 077 && printf '%s' '<TOKEN>' > ~/.config/atlassian/token`.

**Create the page:**

```bash
python3 -I "$S" page --issues "$W/issues.json" --site "$SITE" --space-id 1130790912 \
  --parent-id 4201840645 --title "$TITLE" --out "$W/page.json"
curl -sS -o "$W/page-resp.json" -w '%{http_code}\n' -u "$EMAIL:$(cat ~/.config/atlassian/token)" \
  -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -X POST "https://api.atlassian.com/ex/confluence/$CLOUD/wiki/api/v2/pages" --data-binary @"$W/page.json"
jq -r '._links.base + ._links.webui' "$W/page-resp.json"   # PAGE_URL
```

- Expect 200. Save `PAGE_URL` for step 3.
- If the title already exists (a second hotfix the same day), ask the user for a title — don't invent a suffix.

**Add a bullet to the parent page:**

```bash
acli confluence page view --id 4201840645 --body-format storage --include-version --json > "$W/parent.json"
python3 -I "$S" parent --parent-json "$W/parent.json" --title "$TITLE" --out "$W/parent-update.json"
curl -sS -o "$W/parent-resp.json" -w '%{http_code}\n' -u "$EMAIL:$(cat ~/.config/atlassian/token)" \
  -H 'Content-Type: application/json' -H 'Accept: application/json' \
  -X PUT "https://api.atlassian.com/ex/confluence/$CLOUD/wiki/api/v2/pages/4201840645" --data-binary @"$W/parent-update.json"
acli confluence page view --id 4201840645 --body-format view --json | jq -r .body.view.value
```

- The script inserts a page-link `<li>` at the top of the first `<ul>` (newest first), or creates the list at the top of the page if there is none.
- It bumps the version number. A 409 means someone edited the parent meanwhile: re-read it and retry.
- Exit code 3 = the parent already links to the page (re-run). Skip the PUT.
- Check in the rendered view that the new link appears.

## 3. Email draft

```bash
python3 -I "$S" eml --issues "$W/issues.json" --site "$SITE" --page-url "$PAGE_URL" --out "$W/hotfix-release.eml"
explorer.exe "$(wslpath -w "$W/hotfix-release.eml")"; true
```

- There's no email tool, so the draft is an `.eml` with `X-Unsent: 1`. Outlook opens it as a new editable message. Never send anything.
- `explorer.exe` returns exit code 1 even on success, so ignore it.
- `To:` is prefilled from `TO` in the script.

The body is fixed and was agreed with the user. Keep the lowercase "all," / "thanks,"
exactly as below: the user corrected an attempt to capitalise them.

```
all,

a new hotfix release has been deployed to production.

<blank line>
Changelog:
<Confluence page URL>
<changelog table>

<blank line>
thanks,
```

## 4. Close Jira issues (very last step)

```bash
bash "$C" "$DATE" $(jq -r '.[].key' "$W/issues.json")
acli jira workitem search --jql "$JQL" --count   # expect 0
```

- Take the keys from `issues.json`. Don't re-run the filter: issues drop out of it as they reach Done.
- For each issue the script:
  - adds the comment, unless it's already there;
  - walks the remaining statuses in the workflow chain;
  - skips any transition that isn't allowed and tries the next one.
- Issues at an unexpected status get the whole chain tried in order.
- acli can't list available transitions.
- acli exits 0 even on a refused transition (`✗ Failure: ... No allowed transitions found for given status`). The script therefore reads the status back after every step.
- Status names come back in mixed case (`VERIFICATION`), so compare case-insensitively.
- Run it with `bash`, not inline in the zsh tool shell. In zsh, `status` is a reserved variable and `${x,,}` doesn't work.
- `STUCK` lines (non-zero exit) mean the issue is commented but not Done. Report its current status to the user and ask — don't guess other status names.

## Final report to user

Keep it short:
- JQL used and issue count
- Confluence page URL, plus confirmation that the parent bullet was added
- `.eml` path and whether it was opened.
- Per issue: comment added and the status path to Done (or STUCK)
