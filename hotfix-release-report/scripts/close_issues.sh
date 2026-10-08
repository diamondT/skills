#!/usr/bin/env bash
# Usage: close_issues.sh <dd-mm-yyyy> KEY...
# Comments "deployed to prod on <date>" on each issue, then walks it to Done.
# Safe to re-run: skips existing comments and issues already Done.
set -u

date=$1
shift
comment="deployed to prod on $date"
chain=("Ready for Production" "Verification" "Done")
rc=0

st() { acli jira workitem view "$1" --fields status --json | jq -r .fields.status.name; }

# acli exits 0 even when a transition is not allowed; trust only the status read-back.
move() {
  acli jira workitem transition --key "$1" --status "$2" --yes >/dev/null 2>&1
  local s
  s=$(st "$1")
  [ "${s,,}" = "${2,,}" ]
}

for k in "$@"; do
  if ! acli jira workitem view "$k" --fields comment --json |
    jq -e --arg c "$comment" 'any(.fields.comment.comments[]?; (.body | tostring) | contains($c))' >/dev/null; then
    out=$(acli jira workitem comment create --key "$k" --body "$comment" 2>&1)
    case $out in
      *successfully*) ;;
      *) echo "$k: comment FAILED: $out"; rc=1; continue ;;
    esac
  fi

  cur=$(st "$k")
  path=$cur
  start=0
  for i in "${!chain[@]}"; do
    [ "${chain[$i],,}" = "${cur,,}" ] && start=$((i + 1))
  done

  for target in "${chain[@]:start}"; do
    move "$k" "$target" && path="$path → $target"
  done

  if [ "$(st "$k" | tr '[:upper:]' '[:lower:]')" = done ]; then
    echo "$k: ok | $path"
  else
    echo "$k: STUCK at $(st "$k") | $path"
    rc=1
  fi
done
exit $rc
