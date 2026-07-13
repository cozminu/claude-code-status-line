#!/bin/bash
# Claude Code statusLine script
# Line 1: project title | git branch (dirty indicator + staged/modified counts)
# Line 2: model name | effort level | context tokens used | 5h + 7d subscription usage | session cost
#
# Layout: constants -> helper functions -> segment builders -> main.
# Execution is source-guarded: running the script calls main (which reads the
# JSON payload from stdin), while `source`-ing it only defines functions and
# constants so tests can call each helper directly.

RESET=$'\033[0m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
MAGENTA=$'\033[35m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
ORANGE=$'\033[38;5;208m'
RED=$'\033[31m'
BRIGHT_BLUE=$'\033[94m'
TEAL=$'\033[38;5;43m'
WHITE=$'\033[37m'
BOLD_RED=$'\033[1;31m'
BOLD_MAGENTA=$'\033[1;35m'

# Every user-tunable variable; load_config resolves each one with precedence
# environment > config file > built-in default (defaults reproduce the
# original hard-coded behavior exactly).
STATUSLINE_CONFIG_VARS="STATUSLINE_BAR_WIDTH STATUSLINE_PCT_WARN
  STATUSLINE_PCT_CRIT STATUSLINE_PACE_TOL STATUSLINE_SHOW_TITLE
  STATUSLINE_SHOW_GIT STATUSLINE_SHOW_MODEL STATUSLINE_SHOW_EFFORT
  STATUSLINE_SHOW_CONTEXT STATUSLINE_SHOW_FIVE_HOUR
  STATUSLINE_SHOW_SEVEN_DAY STATUSLINE_SHOW_COST STATUSLINE_SHOW_EMAIL"

# Sources the optional config file (plain bash assignments, e.g.
# STATUSLINE_BAR_WIDTH=20) and fills in defaults. Environment variables win
# over the file: values already set in the environment are snapshotted and
# re-asserted after sourcing. STATUSLINE_CONFIG overrides the file path
# (tests point it at a nonexistent path to stay hermetic). An env var set to
# the empty string counts as unset.
load_config() {
  local conf="${STATUSLINE_CONFIG:-${XDG_CONFIG_HOME:-$HOME/.config}/claude-statusline.conf}"
  if [ -f "$conf" ]; then
    local v snapshot=""
    for v in $STATUSLINE_CONFIG_VARS; do
      [ -n "${!v:-}" ] && snapshot="$snapshot $v=$(printf '%q' "${!v}")"
    done
    # shellcheck disable=SC1090  # user-supplied path, nothing to follow
    . "$conf"
    [ -n "$snapshot" ] && eval "$snapshot"
  fi
  : "${STATUSLINE_BAR_WIDTH:=10}"       # width of the 5h/expanded-7d bars
  : "${STATUSLINE_PCT_WARN:=50}"        # usage severity green -> yellow
  : "${STATUSLINE_PCT_CRIT:=80}"        # usage severity yellow -> red
  : "${STATUSLINE_PACE_TOL:=5}"         # ± points that still count as "on pace"
  : "${STATUSLINE_SHOW_TITLE:=1}"       # segment toggles: 1 shows, 0 hides
  : "${STATUSLINE_SHOW_GIT:=1}"
  : "${STATUSLINE_SHOW_MODEL:=1}"
  : "${STATUSLINE_SHOW_EFFORT:=1}"
  : "${STATUSLINE_SHOW_CONTEXT:=1}"
  : "${STATUSLINE_SHOW_FIVE_HOUR:=1}"
  : "${STATUSLINE_SHOW_SEVEN_DAY:=1}"
  : "${STATUSLINE_SHOW_COST:=1}"
  : "${STATUSLINE_SHOW_EMAIL:=1}"       # 3rd line: logged-in account email
}

# Color scale for reasoning effort: low -> medium -> high -> xhigh -> max
# green -> yellow -> teal -> bold red -> bold magenta.
effort_color() {
  local level="$1"
  case "$level" in
    low) printf "%s" "$GREEN" ;;
    medium) printf "%s" "$YELLOW" ;;
    high) printf "%s" "$TEAL" ;;
    xhigh) printf "%s" "$BOLD_RED" ;;
    max) printf "%s" "$BOLD_MAGENTA" ;;
    *) printf "%s" "$CYAN" ;;
  esac
}

# Distinct color per model family, independent of effort.
model_color() {
  local name_lc
  name_lc=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$name_lc" in
    *opus*) printf "%s" "$BRIGHT_BLUE" ;;
    *sonnet*) printf "%s" "$CYAN" ;;
    *haiku*) printf "%s" "$WHITE" ;;
    *fable*) printf "%s" "$MAGENTA" ;;
    *) printf "%s" "$CYAN" ;;
  esac
}

fmt_tokens() {
  local n="$1"
  if [ "$n" -ge 1000000 ]; then
    awk -v n="$n" 'BEGIN { v=n/1000000; s=sprintf("%.1f", v); sub(/\.0$/, "", s); printf "%sM", s }'
  elif [ "$n" -ge 1000 ]; then
    awk -v n="$n" 'BEGIN { v=n/1000; s=sprintf("%.1f", v); sub(/\.0$/, "", s); printf "%sk", s }'
  else
    printf "%d" "$n"
  fi
}

pct_color() {
  local pct_int="$1"
  if [ "$pct_int" -lt "$STATUSLINE_PCT_WARN" ]; then
    printf "%s" "$GREEN"
  elif [ "$pct_int" -lt "$STATUSLINE_PCT_CRIT" ]; then
    printf "%s" "$YELLOW"
  else
    printf "%s" "$RED"
  fi
}

bar() {
  local pct="$1" width="$STATUSLINE_BAR_WIDTH"
  local filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled="$width"
  [ "$filled" -lt 0 ] && filled=0
  local empty=$(( width - filled ))
  local out="" i
  for (( i = 0; i < filled; i++ )); do out+="█"; done
  for (( i = 0; i < empty; i++ )); do out+="░"; done
  printf "%s" "$out"
}

# Usage bar with a pace tick marking where usage "should" be if evenly spent
# across the elapsed portion of the window. The tick overrides whatever glyph
# (filled/empty) would otherwise occupy that slot, and its shape encodes pace:
# solid ▮ when usage is at or ahead of pace, hollow ▯ when usage is behind it.
pace_bar() {
  local pct="$1" elapsed_pct="$2" width="$STATUSLINE_BAR_WIDTH"
  local filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled="$width"
  local tick=$(( elapsed_pct * width / 100 ))
  [ "$tick" -ge "$width" ] && tick=$(( width - 1 ))
  [ "$tick" -lt 0 ] && tick=0
  local tick_glyph="▯"
  [ "$pct" -ge "$elapsed_pct" ] && tick_glyph="▮"
  local out="" i
  for (( i = 0; i < width; i++ )); do
    if [ "$i" -eq "$tick" ]; then
      out+="$tick_glyph"
    elif [ "$i" -lt "$filled" ]; then
      out+="█"
    else
      out+="░"
    fi
  done
  printf "%s" "$out"
}

# Color by how usage tracks the even-spend pace: green below, yellow on
# (within ±STATUSLINE_PACE_TOL points), orange above.
pace_color() {
  local pct="$1" elapsed_pct="$2"
  local diff=$(( pct - elapsed_pct ))
  if [ "$diff" -lt "-$STATUSLINE_PACE_TOL" ]; then
    printf "%s" "$GREEN"
  elif [ "$diff" -gt "$STATUSLINE_PACE_TOL" ]; then
    printf "%s" "$ORANGE"
  else
    printf "%s" "$YELLOW"
  fi
}

# Percentage of a rate-limit window already elapsed, given its reset unix
# timestamp and the window length. Clamped to [0, 100]. The clock can be
# pinned via STATUSLINE_NOW so tests are deterministic.
elapsed_pct_of_window() {
  local reset="$1" window_seconds="$2"
  local now remaining
  now=${STATUSLINE_NOW:-$(date +%s)}
  remaining=$(( reset - now ))
  [ "$remaining" -lt 0 ] && remaining=0
  [ "$remaining" -gt "$window_seconds" ] && remaining="$window_seconds"
  printf '%s' $(( (window_seconds - remaining) * 100 / window_seconds ))
}

# Integer ceiling of time remaining until `reset` (unix seconds), in units of
# `unit_seconds` (3600 for hours, 86400 for days). Remaining is clamped to
# >= 0 first. Prints "<1" when less than one whole unit remains (including an
# already-past reset), so a stale/overdue reset never reads as a bare "0".
# The clock is injectable via STATUSLINE_NOW, like elapsed_pct_of_window.
reset_countdown() {
  local reset="$1" unit_seconds="$2"
  local now remaining units
  now=${STATUSLINE_NOW:-$(date +%s)}
  remaining=$(( reset - now ))
  [ "$remaining" -lt 0 ] && remaining=0
  units=$(( (remaining + unit_seconds - 1) / unit_seconds ))
  if [ "$units" -lt 1 ]; then
    printf '<1'
  else
    printf '%d' "$units"
  fi
}

# Maps a usage percentage to one of 8 partial-block glyphs (▁▂▃▄▅▆▇█).
gauge_glyph() {
  local pct_int="$1"
  local blocks=(▁ ▂ ▃ ▄ ▅ ▆ ▇ █)
  local idx=$(( pct_int * 8 / 100 ))
  [ "$idx" -gt 7 ] && idx=7
  [ "$idx" -lt 0 ] && idx=0
  printf "%s" "${blocks[$idx]}"
}

# Renders one rate-limit window as a dim-labeled usage bar colored by usage
# severity (no brackets, no reset countdown). The reset time, when present, is
# used only to position the pace tick (pace_bar: ▮ at/ahead of pace, ▯ behind)
# — it is not displayed; without it pace is unknowable and a plain bar renders
# instead. Prints nothing if the percentage can't be parsed.
usage_segment() {
  local label="$1" pct="$2" reset="$3" window_seconds="$4"
  local pct_int
  pct_int=$(printf '%.0f' "$pct" 2>/dev/null)
  [ -z "$pct_int" ] && return
  local color u_bar
  color=$(pct_color "$pct_int")
  if [ -n "$reset" ] && [ "$reset" != "null" ]; then
    u_bar=$(pace_bar "$pct_int" "$(elapsed_pct_of_window "$reset" "$window_seconds")")
  else
    u_bar=$(bar "$pct_int")
  fi
  printf '%s%s%s %s%s%s' "$DIM" "$label" "$RESET" "$color" "$u_bar" "$RESET"
}

# 7d rate-limit window: a compact single-cell pace marker (gauge glyph) by
# default, expanding into a full pace bar only when weekly usage is running
# ahead of the even-spend pace — the one case worth flagging. Colored on the
# pace scale throughout (green below / yellow on / orange over pace, via
# pace_color), so the expanded bar is always orange. Falls back to a plain
# marker colored by usage severity when no reset time is available to compute
# pace (in which case it can never expand). Prints nothing if the percentage
# can't be parsed.
seven_day_segment() {
  local label="$1" pct="$2" reset="$3" window_seconds="$4"
  local pct_int
  pct_int=$(printf '%.0f' "$pct" 2>/dev/null)
  [ -z "$pct_int" ] && return
  local color glyph_or_bar
  if [ -n "$reset" ] && [ "$reset" != "null" ]; then
    local elapsed_pct
    elapsed_pct=$(elapsed_pct_of_window "$reset" "$window_seconds")
    color=$(pace_color "$pct_int" "$elapsed_pct")
    # Expand to a full bar only when genuinely over pace (past the tolerance
    # band, i.e. where pace_color turns orange); on/under pace stays compact.
    if [ "$(( pct_int - elapsed_pct ))" -gt "$STATUSLINE_PACE_TOL" ]; then
      glyph_or_bar=$(pace_bar "$pct_int" "$elapsed_pct")
    else
      glyph_or_bar=$(gauge_glyph "$pct_int")
    fi
  else
    # No reset time: pace is unknowable, so show a plain compact marker colored
    # by usage severity and never expand.
    color=$(pct_color "$pct_int")
    glyph_or_bar=$(gauge_glyph "$pct_int")
  fi
  printf '%s%s%s %s%s%s' "$DIM" "$label" "$RESET" "$color" "$glyph_or_bar" "$RESET"
}

# Email of the currently logged-in Claude account, read from the active
# profile's config file (CLAUDE_CONFIG_DIR, defaulting to ~/.claude like
# Claude Code itself) rather than the stdin payload, which carries no
# account/user field. Missing dir/file/field all fall through to "".
account_email() {
  local conf_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  jq -r '.oauthAccount.emailAddress // ""' "$conf_dir/.claude.json" 2>/dev/null
}

# True when CLAUDE_CONFIG_DIR points at Claude Code's own default profile dir
# (unset, or explicitly set to it) -- the case where showing the account
# email adds no signal since there's only ever one profile in play.
using_default_claude_profile() {
  [ "${CLAUDE_CONFIG_DIR:-$HOME/.claude}" = "$HOME/.claude" ]
}

join_line() {
  local sep out i
  sep="${DIM} | ${RESET}"
  out=""
  for i in "$@"; do
    if [ -z "$out" ]; then
      out="$i"
    else
      out="${out}${sep}${i}"
    fi
  done
  printf "%s" "$out"
}

main() {
  load_config

  # Parse every payload field in a single jq pass over stdin — the status
  # line renders on every prompt, so one process beats eleven. The filter
  # emits exactly one line per field (`// ""` keeps absent fields as empty
  # lines) and the reads below consume them in the same order. Values used
  # here are names/paths/numbers, assumed newline-free.
  {
    IFS= read -r model
    IFS= read -r effort
    IFS= read -r cwd
    IFS= read -r used_pct
    IFS= read -r used_tokens
    IFS= read -r five_h_pct
    IFS= read -r five_h_reset
    IFS= read -r seven_d_pct
    IFS= read -r seven_d_reset
    IFS= read -r cost_usd
    IFS= read -r repo_name
  } < <(jq -r '
    (.model.display_name // "Claude"),
    (.effort.level // ""),
    (.workspace.current_dir // .cwd // ""),
    (.context_window.used_percentage // ""),
    ((.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // ""),
    (.cost.total_cost_usd // ""),
    (.workspace.repo.name // "")
  ')

  # Line 1: workspace (project title, git branch + dirty/clean state + file counts)
  segments=()

  project_title=""
  if [ -n "$repo_name" ] && [ "$repo_name" != "null" ]; then
    project_title="$repo_name"
  elif [ -n "$cwd" ]; then
    project_title="${cwd##*/}"
  fi
  if [ "$STATUSLINE_SHOW_TITLE" = 1 ] && [ -n "$project_title" ]; then
    segments+=("${DIM}${project_title}${RESET}")
  fi

  # Git branch with dirty/clean indicator and staged/modified/untracked file
  # counts, derived from a single `git status` call (skipped entirely outside
  # a git repo).
  if [ "$STATUSLINE_SHOW_GIT" = 1 ] && [ -n "$cwd" ]; then
    status_output=$(git -C "$cwd" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)
    if [ -n "$status_output" ]; then
      branch=$(printf '%s\n' "$status_output" | awk '/^# branch\.head /{print $3}')
      if [ "$branch" = "(detached)" ]; then
        oid=$(printf '%s\n' "$status_output" | awk '/^# branch\.oid /{print $3}')
        branch="detached@${oid:0:7}"
      fi
      staged=0
      modified=0
      untracked=0
      while IFS= read -r line; do
        case "$line" in
          "1 "*|"2 "*)
            xy=$(printf '%s' "$line" | awk '{print $2}')
            [ "${xy:0:1}" != "." ] && staged=$(( staged + 1 ))
            [ "${xy:1:1}" != "." ] && modified=$(( modified + 1 ))
            ;;
          "u "*)
            modified=$(( modified + 1 ))
            ;;
          "? "*)
            untracked=$(( untracked + 1 ))
            ;;
        esac
      done <<< "$status_output"
      if [ -n "$branch" ]; then
        if [ "$staged" -gt 0 ] || [ "$modified" -gt 0 ] || [ "$untracked" -gt 0 ]; then
          git_counts=""
          [ "$staged" -gt 0 ] && git_counts="${GREEN}+${staged}${RESET}"
          [ "$modified" -gt 0 ] && git_counts="${git_counts}${YELLOW}~${modified}${RESET}"
          [ "$untracked" -gt 0 ] && git_counts="${git_counts}${DIM}?${untracked}${RESET}"
          segments+=("${YELLOW}${branch} ✗${RESET} ${git_counts}")
        else
          segments+=("${GREEN}${branch} ✓${RESET}")
        fi
      fi
    fi
  fi

  # Line 2: model name, effort level, context usage, 5h subscription usage, session cost
  line2=()

  # 1. Model name (colored by model family)
  if [ "$STATUSLINE_SHOW_MODEL" = 1 ]; then
    line2+=("$(model_color "$model")${model}${RESET}")
  fi

  # 2. Effort / reasoning level (only if present in payload)
  if [ "$STATUSLINE_SHOW_EFFORT" = 1 ] && [ -n "$effort" ] && [ "$effort" != "null" ]; then
    line2+=("$(effort_color "$effort")${effort}${RESET}")
  fi

  # 3. Context usage: tokens used, color shifting as the window fills up
  if [ "$STATUSLINE_SHOW_CONTEXT" = 1 ] && [ -n "$used_pct" ] && [ "$used_pct" != "null" ] && [ -n "$used_tokens" ] && [ "$used_tokens" != "null" ]; then
    pct_int=$(printf '%.0f' "$used_pct" 2>/dev/null)
    if [ -n "$pct_int" ]; then
      line2+=("$(pct_color "$pct_int")$(fmt_tokens "$used_tokens")${RESET}")
    fi
  fi

  # 4. Subscription rate-limit usage (5-hour and 7-day windows; absent on
  # API-key billing). The label is a live reset countdown (integer hours/days
  # via reset_countdown) when a reset time is present, falling back to the
  # static period name otherwise.
  # 5h: always shown, colored by usage severity (green/yellow/red).
  if [ "$STATUSLINE_SHOW_FIVE_HOUR" = 1 ] && [ -n "$five_h_pct" ] && [ "$five_h_pct" != "null" ]; then
    five_h_label="5h"
    if [ -n "$five_h_reset" ] && [ "$five_h_reset" != "null" ]; then
      five_h_label="$(reset_countdown "$five_h_reset" 3600)h"
    fi
    seg=$(usage_segment "$five_h_label" "$five_h_pct" "$five_h_reset" 18000)
    [ -n "$seg" ] && line2+=("$seg")
  fi

  # 7d: always shown as a compact pace marker, expanding to a full bar only
  # when weekly usage is running ahead of pace.
  if [ "$STATUSLINE_SHOW_SEVEN_DAY" = 1 ] && [ -n "$seven_d_pct" ] && [ "$seven_d_pct" != "null" ]; then
    seven_d_label="7d"
    if [ -n "$seven_d_reset" ] && [ "$seven_d_reset" != "null" ]; then
      seven_d_label="$(reset_countdown "$seven_d_reset" 86400)d"
    fi
    seg=$(seven_day_segment "$seven_d_label" "$seven_d_pct" "$seven_d_reset" 604800)
    [ -n "$seg" ] && line2+=("$seg")
  fi

  # 5. Session cost
  if [ "$STATUSLINE_SHOW_COST" = 1 ] && [ -n "$cost_usd" ] && [ "$cost_usd" != "null" ]; then
    cost_fmt=$(printf '$%.2f' "$cost_usd" 2>/dev/null)
    [ -n "$cost_fmt" ] && line2+=("${GREEN}${cost_fmt}${RESET}")
  fi

  # Line 3: logged-in Claude account email, read from CLAUDE_CONFIG_DIR rather
  # than the stdin payload (which carries no account/user field). Only shown
  # on a non-default profile, where knowing which account is active is
  # actually useful signal.
  line3=()
  if [ "$STATUSLINE_SHOW_EMAIL" = 1 ] && ! using_default_claude_profile; then
    email=$(account_email)
    [ -n "$email" ] && line3+=("${CYAN}${email}${RESET}")
  fi

  # ${arr[@]+...} keeps empty-array expansion legal under set -u on bash 3.2.
  printf '%s\n' "$(join_line ${segments[@]+"${segments[@]}"})"
  [ "${#line2[@]}" -gt 0 ] && printf '%s\n' "$(join_line ${line2[@]+"${line2[@]}"})"
  [ "${#line3[@]}" -gt 0 ] && printf '%s\n' "$(join_line ${line3[@]+"${line3[@]}"})"
  exit 0
}

# Run only when executed, not when sourced (tests source this file to reach
# the helpers directly, and set their own shell options).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # -e is deliberately absent: missing payload fields are expected and handled
  # by fail-closed [ -n ... ] guards, not by aborting the render.
  set -u -o pipefail
  main
fi
