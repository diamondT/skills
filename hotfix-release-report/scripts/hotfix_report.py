#!/usr/bin/env python3
"""Build hotfix release report artifacts from `acli jira workitem search --json` output."""

import argparse
import html
import json
import sys
from email.message import EmailMessage

SUBJECT = "NextCommerce Production release"
HEADERS = ("Issue", "Issue Type", "Issue Description")
CELL = 'style="border:1px solid #999;padding:4px 8px"'


def load_rows(issues_path, site):
    with open(issues_path, encoding="utf-8") as f:
        issues = json.load(f)
    base = f"https://{site}/browse/"
    return [
        (base + i["key"], i["fields"]["issuetype"]["name"], i["fields"]["summary"].strip())
        for i in issues
    ]


def html_table(rows, cell_attr=""):
    attr = f" {cell_attr}" if cell_attr else ""
    head = "".join(f"<th{attr}>{h}</th>" for h in HEADERS)
    body = "".join(
        f'<tr><td{attr}><a href="{u}">{u}</a></td>'
        f"<td{attr}>{html.escape(t)}</td><td{attr}>{html.escape(s)}</td></tr>"
        for u, t, s in rows
    )
    return f"<table><tbody><tr>{head}</tr>{body}</tbody></table>"


def cmd_markdown(a):
    rows = load_rows(a.issues, a.site)
    print("| " + " | ".join(HEADERS) + " |")
    print("|---|---|---|")
    for u, t, s in rows:
        print(f"| {u} | {t} | {s.replace('|', chr(92) + '|')} |")


def cmd_page(a):
    payload = {
        "spaceId": a.space_id,
        "parentId": a.parent_id,
        "status": "current",
        "title": a.title,
        "body": {"representation": "storage", "value": html_table(load_rows(a.issues, a.site))},
    }
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def cmd_parent(a):
    with open(a.parent_json, encoding="utf-8") as f:
        page = json.load(f)
    body = (page.get("body") or {}).get("storage", {}).get("value", "") or ""
    title_attr = html.escape(a.title, quote=True)
    if f'ri:content-title="{title_attr}"' in body:
        print("parent already links to this page", file=sys.stderr)
        sys.exit(3)
    item = f'<li><ac:link><ri:page ri:content-title="{title_attr}" /></ac:link></li>'
    i = body.find("<ul")
    if i >= 0:
        i = body.index(">", i) + 1
        body = body[:i] + item + body[i:]
    else:
        body = f"<ul>{item}</ul>" + body
    payload = {
        "id": page["id"],
        "status": "current",
        "title": page["title"],
        "body": {"representation": "storage", "value": body},
        "version": {"number": page["version"]["number"] + 1, "message": f"Add {a.title}"},
    }
    with open(a.out, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, indent=2)


def cmd_eml(a):
    rows = load_rows(a.issues, a.site)
    url = a.page_url
    text = (
        "all,\n\na new hotfix release has been deployed to production.\n\n\n"
        f"Changelog:\n{url}\n\n"
        + "\n".join(f"- {u} | {t} | {s}" for u, t, s in rows)
        + "\n\n\nthanks,\n"
    )
    body = f"""<html><body style="font-family:Calibri,Arial,sans-serif;font-size:11pt">
<p>all,</p>
<p>a new hotfix release has been deployed to production.</p>
<p>&nbsp;</p>
<p>Changelog:<br><a href="{html.escape(url, quote=True)}">{html.escape(url)}</a></p>
{html_table(rows, CELL).replace("<table>", '<table style="border-collapse:collapse">', 1)}
<p>&nbsp;</p>
<p>thanks,</p>
</body></html>"""
    msg = EmailMessage()
    msg["Subject"] = SUBJECT
    msg["To"] = ""
    msg["X-Unsent"] = "1"
    msg.set_content(text)
    msg.add_alternative(body, subtype="html")
    with open(a.out, "wb") as f:
        f.write(bytes(msg))


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sub = p.add_subparsers(required=True)

    s = sub.add_parser("markdown", help="print changelog as a markdown table")
    s.add_argument("--issues", required=True)
    s.add_argument("--site", required=True)
    s.set_defaults(func=cmd_markdown)

    s = sub.add_parser("page", help="write Confluence v2 create-page payload")
    s.add_argument("--issues", required=True)
    s.add_argument("--site", required=True)
    s.add_argument("--space-id", required=True)
    s.add_argument("--parent-id", required=True)
    s.add_argument("--title", required=True)
    s.add_argument("--out", required=True)
    s.set_defaults(func=cmd_page)

    s = sub.add_parser("parent", help="write update payload adding a bullet link to the parent page")
    s.add_argument("--parent-json", required=True, help="acli page view --body-format storage --include-version --json")
    s.add_argument("--title", required=True)
    s.add_argument("--out", required=True)
    s.set_defaults(func=cmd_parent)

    s = sub.add_parser("eml", help="write unsent .eml draft")
    s.add_argument("--issues", required=True)
    s.add_argument("--site", required=True)
    s.add_argument("--page-url", required=True)
    s.add_argument("--out", required=True)
    s.set_defaults(func=cmd_eml)

    a = p.parse_args()
    a.func(a)


if __name__ == "__main__":
    main()
