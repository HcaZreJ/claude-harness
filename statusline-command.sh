#!/usr/bin/env bash
# Claude Code status line — mirrors Gruvbox Dark Starship theme
# Colors from starship.toml palette
FG0='\033[38;2;251;241;199m'   # color_fg0  #fbf1c7
BG1='\033[48;2;60;56;54m'      # color_bg1  #3c3836
BG3='\033[48;2;102;92;84m'     # color_bg3  #665c54
BLUE='\033[48;2;69;133;136m'   # color_blue #458588
AQUA='\033[48;2;104;157;106m'  # color_aqua #689d6a
ORANGE='\033[48;2;214;93;14m'  # color_orange #d65d0e
YELLOW='\033[48;2;215;153;33m' # color_yellow #d79921
FG_ORANGE='\033[38;2;214;93;14m'
FG_YELLOW='\033[38;2;215;153;33m'
FG_AQUA='\033[38;2;104;157;106m'
FG_BLUE='\033[38;2;69;133;136m'
FG_BG3='\033[38;2;102;92;84m'
FG_BG1='\033[38;2;60;56;54m'
RESET='\033[0m'

input=$(cat)

user=$(whoami)

# Logged-in Claude account (from ~/.claude.json), fall back to shell user
account=$(jq -r '.oauthAccount.emailAddress // .oauthAccount.displayName // empty' ~/.claude.json 2>/dev/null)
[ -z "$account" ] && account="$user"

dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
[ -z "$dir" ] && dir=$(pwd)
# Substitute home directory; show the full path (no truncation)
dir_display="${dir/#\/Users\/$user/~}"

model=$(echo "$input" | jq -r '.model.display_name // empty')

# Context usage
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')

# 5-hour rate limit
five_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_reset_ts=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')

# Weekly account usage
week_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
week_reset_ts=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# GAP: one space with no background color between segments
GAP="${RESET} "

# Build a compact 8-block progress bar from a percentage value (0-100).
# Full blocks: █  Empty blocks: ░
make_bar() {
  local pct="${1:-0}"
  local total=8
  local filled=$(printf '%.0f' "$(echo "$pct $total" | awk '{printf "%f", $1 * $2 / 100}')")
  local empty=$(( total - filled ))
  local bar=""
  local i
  for (( i=0; i<filled; i++ )); do bar="${bar}█"; done
  for (( i=0; i<empty;  i++ )); do bar="${bar}░"; done
  printf '%s' "$bar"
}

# ── Line 1: Claude account · working dir ───────────────────────
printf "${ORANGE}${FG0} ${account} ${RESET}"
printf "${GAP}"
printf "${YELLOW}${FG0} ${dir_display} ${RESET}"

printf "\n"

# ── Line 2: model + context · 5h usage · 7d usage ──────────────
if [ -n "$model" ]; then
  printf "${BLUE}${FG0} ${model}"
  if [ -n "$used_pct" ]; then
    ctx_bar=$(make_bar "$used_pct")
    ctx_pct_rounded=$(printf '%.0f' "$used_pct")
    printf " ${ctx_bar} ${ctx_pct_rounded}%%"
  fi
  printf " ${RESET}"
fi

if [ -n "$five_pct" ]; then
  PURPLE='\033[48;2;177;98;134m'      # color_purple bg #b16286
  five_bar=$(make_bar "$five_pct")
  five_pct_rounded=$(printf '%.0f' "$five_pct")
  five_reset_label=""
  if [ -n "$five_reset_ts" ]; then
    five_reset_label=" → $(date -r "$five_reset_ts" '+%H:%M')"
  fi
  printf "${GAP}"
  printf "${PURPLE}${FG0} 5h ${five_bar} ${five_pct_rounded}%%${five_reset_label} ${RESET}"
fi

if [ -n "$week_pct" ]; then
  week_bar=$(make_bar "$week_pct")
  week_pct_rounded=$(printf '%.0f' "$week_pct")
  week_reset_label=""
  if [ -n "$week_reset_ts" ]; then
    week_reset_label=" → $(date -r "$week_reset_ts" '+%m/%d %H:%M')"
  fi
  printf "${GAP}"
  printf "${BG3}${FG0} 7d ${week_bar} ${week_pct_rounded}%%${week_reset_label} ${RESET}"
fi

printf "\n"
