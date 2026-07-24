# shellcheck shell=bash
# Every user-tunable variable; load_config resolves each one with precedence
# environment > config file > built-in default (defaults reproduce the
# original hard-coded behavior exactly).
#
# STATUSLINE_LINE{1,2,3}_SEGMENTS have no default asserted here: their default
# is the built-in registration order, which isn't known until every
# lib/segments.sh + segments/*.sh + plugin file has registered — see
# finalize_segment_order() in lib/main.sh. They're still listed here so
# load_config's env-wins-over-file snapshot/reassert applies to them too.
STATUSLINE_CONFIG_VARS="STATUSLINE_BAR_WIDTH STATUSLINE_SEVEN_DAY_BAR_WIDTH
  STATUSLINE_PCT_WARN
  STATUSLINE_PCT_CRIT STATUSLINE_PACE_TOL STATUSLINE_SHOW_TITLE
  STATUSLINE_SHOW_GIT STATUSLINE_SHOW_MODEL STATUSLINE_SHOW_EFFORT
  STATUSLINE_SHOW_CONTEXT STATUSLINE_SHOW_FIVE_HOUR
  STATUSLINE_SHOW_SEVEN_DAY STATUSLINE_SHOW_COST STATUSLINE_SHOW_EMAIL
  STATUSLINE_SEGMENTS_DIR STATUSLINE_LINE1_SEGMENTS
  STATUSLINE_LINE2_SEGMENTS STATUSLINE_LINE3_SEGMENTS"

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
  : "${STATUSLINE_BAR_WIDTH:=10}"       # width of the 5h bar
  : "${STATUSLINE_SEVEN_DAY_BAR_WIDTH:=14}"  # width of the expanded 7d bar
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
  : "${STATUSLINE_SHOW_EMAIL:=0}"       # 3rd line: logged-in account email
  : "${STATUSLINE_SEGMENTS_DIR:=${XDG_CONFIG_HOME:-$HOME/.config}/claude-statusline/segments.d}"
}
