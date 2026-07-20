#!/usr/bin/env bash
# Claude Code statusline.
# Also invoked as a UserPromptSubmit / PreToolUse hook with --hook, where the
# payload only carries cwd/transcript_path — every section below is optional so
# the same script degrades gracefully there.
input=$(cat)

eval "$(echo "$input" | jq -r '
  @sh "cwd=\(.workspace.current_dir // .cwd // "")",
  @sh "model=\(.model.display_name // "")",
  @sh "effort=\(.effort.level // "")",
  @sh "ctx_used=\(.context_window.used_percentage // "")",
  @sh "ctx_tokens=\(.context_window.total_input_tokens // "")",
  @sh "h5_used=\(.rate_limits.five_hour.used_percentage // "")",
  @sh "h5_reset=\(.rate_limits.five_hour.resets_at // "")",
  @sh "d7_used=\(.rate_limits.seven_day.used_percentage // "")"
')"

# shorten home dir (escape the ~ or bash tilde-expands the replacement back to $HOME)
short_cwd="${cwd/#"$HOME"/\~}"

# git branch (skip optional locks)
branch=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
fi

sep="$(printf '\033[2m') │ $(printf '\033[0m')"
reset=$(printf '\033[0m')

# helper: build a progress bar
# usage: make_bar <percentage_int> <width>
make_bar() {
  local pct=$1 width=$2
  local filled=$(( pct * width / 100 ))
  local bar="" i
  for (( i = 1; i <= width; i++ )); do
    if [ "$i" -le "$filled" ]; then
      bar+="█"
    else
      bar+="░"
    fi
  done
  printf '%s' "$bar"
}

# helper: color for a "how full is it" value — green low, red high
fill_color() {
  local val=$1
  if [ "$val" -ge 80 ]; then
    printf '\033[31m'   # red
  elif [ "$val" -ge 50 ]; then
    printf '\033[33m'   # yellow
  else
    printf '\033[32m'   # green
  fi
}

# helper: color for a "how much is left" value — green high, red low
left_color() {
  local val=$1
  if [ "$val" -le 20 ]; then
    printf '\033[31m'   # red
  elif [ "$val" -le 50 ]; then
    printf '\033[33m'   # yellow
  else
    printf '\033[32m'   # green
  fi
}

sections=()

# model in dim white with brain icon, effort appended
if [ -n "$model" ]; then
  label="$model"
  [ -n "$effort" ] && label+=" ·${effort}"
  sections+=("$(printf '\033[2m')🧠 ${label}${reset}")
fi

# session limit: remaining 5h quota as a bar, plus wall-clock reset time
if [ -n "$h5_used" ]; then
  h5_left=$(echo "$h5_used" | awk '{v = 100 - $1; if (v < 0) v = 0; printf "%.0f", v}')
  color=$(left_color "$h5_left")
  bar=$(make_bar "$h5_left" 10)
  chunk="${color}🔋 ${bar} ${h5_left}%"
  if [ -n "$h5_reset" ]; then
    chunk+=" ⏱ $(date -d "@${h5_reset}" +%H:%M 2>/dev/null)"
  fi
  # weekly quota, compact
  if [ -n "$d7_used" ]; then
    d7_left=$(echo "$d7_used" | awk '{v = 100 - $1; if (v < 0) v = 0; printf "%.0f", v}')
    chunk+=" $(printf '\033[0;90m')//$(printf '\033[0;36m') 7d ${d7_left}%"
  fi
  sections+=("${chunk}${reset}")
fi

# context progress bar with gauge icon — token count is the numerator behind
# used_percentage (input + cache creation + cache read of the latest turn)
if [ -n "$ctx_used" ]; then
  ctx_int=${ctx_used%.*}
  color=$(fill_color "$ctx_int")
  bar=$(make_bar "$ctx_int" 10)
  amount="${ctx_int}%"
  if [ -n "$ctx_tokens" ]; then
    fmt_tokens=$(echo "$ctx_tokens" | awk '{
      if ($1 >= 1000000) printf "%.1fM", $1 / 1000000
      else if ($1 >= 1000) printf "%.0fK", $1 / 1000
      else printf "%d", $1
    }')
    amount="${fmt_tokens} (${ctx_int}%)"
  fi
  sections+=("${color}📊 ${bar} ${amount}${reset}")
fi

# cwd in blue with folder icon
sections+=("$(printf '\033[34m')📁 ${short_cwd}${reset}")

# git branch in magenta with branch icon
if [ -n "$branch" ]; then
  sections+=("$(printf '\033[35m')🌿 ${branch}${reset}")
fi

# join sections with separator
result=""
for section in "${sections[@]}"; do
  if [ -z "$result" ]; then
    result="$section"
  else
    result+="${sep}${section}"
  fi
done

printf '%s' "$result"
