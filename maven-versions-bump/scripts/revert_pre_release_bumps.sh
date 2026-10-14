#!/usr/bin/env bash
# revert_pre_release_bumps.sh
#
# After `mvn versions:update-properties` has rewritten <properties> in pom.xml,
# this script reverts any property whose NEW value is unstable while the
# OLD (committed) value was a stable release.
#
# Unstable = pre-release (alpha/beta/M/RC/SNAPSHOT/CR/EA) or vendor rebuild
# (redhat/jbossorg), with a `-` or `.` separator (`-M1`, `.Beta2`, `.redhat-00001`).
# Rationale: unstable artifacts should never be picked up automatically. But if
# the project was already tracking an unstable line, the user is doing it
# intentionally — leave it.
#
# Compares each modified pom.xml (root + nested) at HEAD against the working
# tree, so it must run AFTER mvn versions and stays anchored to the committed
# values however many passes are run.
#
# Usage:
#   ./scripts/revert_pre_release_bumps.sh           # dry-run, prints actions
#   ./scripts/revert_pre_release_bumps.sh --apply   # actually rewrite pom files
#
# Exit codes:
#   0 — no unstable bumps found, nothing to do
#   0 — unstable bumps found and reported (dry-run) or reverted (--apply)
#   2 — no pom.xml differs from HEAD (forgot to run mvn first?)

set -euo pipefail

APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
fi

cd "$(git rev-parse --show-toplevel)"

mapfile -t POMS < <(git diff HEAD --name-only --diff-filter=M -- 'pom.xml' '**/pom.xml' | sort -u)

if [[ ${#POMS[@]} -eq 0 ]]; then
  echo "No pom.xml changes detected in working tree." >&2
  echo "Did you run 'mvn versions:update-properties -DgenerateBackupPoms=false' first?" >&2
  exit 2
fi

python3 - "$APPLY" "${POMS[@]}" <<'PY'
import re, subprocess, sys

apply = sys.argv[1] == "1"
poms = sys.argv[2:]

PROP = re.compile(r"<([A-Za-z0-9._-]+\.version)>\s*([^<]+?)\s*</\1>")
UNSTABLE = re.compile(
    r"[-.](M\d+|RC\d*|CR\d+|alpha\d*|beta\d*|SNAPSHOT|EA|(redhat|jbossorg)-?\d+)",
    re.IGNORECASE,
)


def unstable(v):
    return UNSTABLE.search(v) is not None


def keyed(matches):
    seen = {}
    out = {}
    for m in matches:
        name = m.group(1)
        n = seen.get(name, 0)
        seen[name] = n + 1
        out[(name, n)] = m
    return out


checked = reverted = 0
for pom in poms:
    old_text = subprocess.run(
        ["git", "show", f"HEAD:{pom}"], check=True, capture_output=True
    ).stdout.decode("utf-8")
    with open(pom, encoding="utf-8", newline="") as f:
        new_text = f.read()

    old = {k: m.group(2) for k, m in keyed(PROP.finditer(old_text)).items()}
    edits = []
    for (name, n), m in keyed(PROP.finditer(new_text)).items():
        old_val, new_val = old.get((name, n)), m.group(2)
        if old_val is None or old_val == new_val:
            continue
        checked += 1
        if unstable(new_val) and not unstable(old_val):
            print(f"REVERT  {pom}  <{name}>: {new_val}  →  {old_val}  (was stable, became pre-release/vendor build)")
            reverted += 1
            edits.append((m.start(2), m.end(2), old_val))
        elif unstable(new_val) and unstable(old_val):
            print(f"KEEP    {pom}  <{name}>: {old_val} → {new_val}  (was already pre-release/vendor build)")

    if apply and edits:
        for start, end, val in reversed(edits):
            new_text = new_text[:start] + val + new_text[end:]
        with open(pom, "w", encoding="utf-8", newline="") as f:
            f.write(new_text)

print()
print(f"Checked: {checked} version-property bumps")
print(f"Reverted: {reverted}")
if reverted and not apply:
    print("(dry-run — re-run with --apply to actually revert)")
PY
