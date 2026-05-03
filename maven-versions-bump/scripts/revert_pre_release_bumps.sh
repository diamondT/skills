#!/usr/bin/env bash
# revert_pre_release_bumps.sh
#
# After `mvn versions:update-properties` has rewritten <properties> in pom.xml,
# this script reverts any property whose NEW value is a pre-release while the
# OLD (committed) value was a stable release.
#
# Rationale: pre-release artifacts (alpha/beta/M/RC/SNAPSHOT/CR/EA) are unstable
# and should never be picked up automatically. But if the project was already
# tracking a pre-release line, the user is doing it intentionally — leave it.
#
# Operates on `git diff` of pom.xml files (root + nested), so the working tree
# must already contain the post-update changes (i.e. run AFTER mvn versions).
#
# Usage:
#   ./scripts/revert_pre_release_bumps.sh           # dry-run, prints actions
#   ./scripts/revert_pre_release_bumps.sh --apply   # actually rewrite pom files
#
# Exit codes:
#   0 — no pre-release bumps found, nothing to do
#   0 — pre-release bumps found and reported (dry-run) or reverted (--apply)
#   2 — git diff produced no output (forgot to run mvn first?)

set -euo pipefail

APPLY=0
if [[ "${1:-}" == "--apply" ]]; then
  APPLY=1
fi

PRE_RELEASE_REGEX='(-M[0-9]+|-RC[0-9]+|-SNAPSHOT|-alpha[0-9]*|-beta[0-9]*|-CR[0-9]+|-EA)'

is_pre_release() {
  local v="$1"
  echo "$v" | grep -Eqi "$PRE_RELEASE_REGEX"
}

# Collect modified pom.xml files
mapfile -t POMS < <(git diff --name-only -- '**/pom.xml' 'pom.xml' | sort -u)

if [[ ${#POMS[@]} -eq 0 ]]; then
  echo "No pom.xml changes detected in working tree." >&2
  echo "Did you run 'mvn versions:update-properties -DgenerateBackupPoms=false' first?" >&2
  exit 2
fi

reverted=0
checked=0

for pom in "${POMS[@]}"; do
  # Iterate diff hunks of <something.version> properties only.
  # We pair each `-` line (old) with the immediately-following `+` line (new).
  while IFS= read -r line; do
    if [[ "$line" =~ ^-[[:space:]]*\<([a-zA-Z0-9._-]+\.version)\>([^<]+)\</([a-zA-Z0-9._-]+\.version)\> ]]; then
      old_prop="${BASH_REMATCH[1]}"
      old_val="${BASH_REMATCH[2]}"
      # Read next line to get the corresponding `+`
      IFS= read -r next_line || break
      if [[ "$next_line" =~ ^\+[[:space:]]*\<([a-zA-Z0-9._-]+\.version)\>([^<]+)\</([a-zA-Z0-9._-]+\.version)\> ]]; then
        new_prop="${BASH_REMATCH[1]}"
        new_val="${BASH_REMATCH[2]}"
        if [[ "$old_prop" == "$new_prop" ]]; then
          checked=$((checked + 1))
          if is_pre_release "$new_val" && ! is_pre_release "$old_val"; then
            echo "REVERT  $pom  <${new_prop}>: ${new_val}  →  ${old_val}  (was stable, became pre-release)"
            reverted=$((reverted + 1))
            if [[ $APPLY -eq 1 ]]; then
              # Use a delimiter that won't collide with version strings
              # to avoid sed parsing issues with characters like /
              python3 - "$pom" "$new_prop" "$new_val" "$old_val" <<'PY'
import sys, re, pathlib
pom_path, prop, new_val, old_val = sys.argv[1:5]
p = pathlib.Path(pom_path)
text = p.read_text()
pattern = re.compile(rf"<{re.escape(prop)}>{re.escape(new_val)}</{re.escape(prop)}>")
new_text, n = pattern.subn(f"<{prop}>{old_val}</{prop}>", text, count=1)
if n != 1:
    print(f"WARN: could not locate <{prop}>{new_val}</{prop}> in {pom_path}", file=sys.stderr)
    sys.exit(1)
p.write_text(new_text)
PY
            fi
          elif is_pre_release "$new_val" && is_pre_release "$old_val"; then
            echo "KEEP    $pom  <${new_prop}>: ${old_val} → ${new_val}  (was already pre-release)"
          fi
        fi
      fi
    fi
  done < <(git diff -- "$pom" | grep -E '^[-+][[:space:]]*<[a-zA-Z0-9._-]+\.version>')
done

echo
echo "Checked: $checked version-property bumps"
echo "Reverted: $reverted"
if [[ $reverted -gt 0 && $APPLY -eq 0 ]]; then
  echo "(dry-run — re-run with --apply to actually revert)"
fi
