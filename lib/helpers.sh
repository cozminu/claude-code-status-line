# shellcheck shell=bash
# Pure helpers and segment builders: no I/O, explicit arguments in, text out.
# Kept independently unit-testable (test/unit.bats calls each directly).

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
# The whole bar is printed in one color by the caller, which buries the tick
# when it lands inside a run of same-colored fill (the common case once
# usage is well ahead of pace) -- so the tick cell is wrapped in reverse
# video, punching a visible notch out of the bar regardless of which color
# or position it falls on.
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
      out+="${REVERSE}${tick_glyph}${UNREVERSE}"
    elif [ "$i" -lt "$filled" ]; then
      out+="█"
    else
      out+="░"
    fi
  done
  printf "%s" "$out"
}

# Color by how usage tracks the even-spend pace: green below, yellow on
# (within ±STATUSLINE_PACE_TOL points), above_color (default orange) above.
# Callers pass a distinct above_color so segments sharing this scale (5h red,
# 7d orange) stay visually distinguishable from each other.
pace_color() {
  local pct="$1" elapsed_pct="$2" above_color="${3:-$ORANGE}"
  local diff=$(( pct - elapsed_pct ))
  if [ "$diff" -lt "-$STATUSLINE_PACE_TOL" ]; then
    printf "%s" "$GREEN"
  elif [ "$diff" -gt "$STATUSLINE_PACE_TOL" ]; then
    printf "%s" "$above_color"
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

# Renders one rate-limit window as a dim-labeled usage bar (no brackets, no
# reset countdown). Colored on the pace scale (green below / yellow on /
# red over the even-spend pace, via pace_color) when a reset time is present;
# the reset also positions the pace tick (pace_bar: ▮ at/ahead of pace, ▯
# behind). Without a reset, pace is unknowable, so it falls back to a plain
# bar colored by usage severity (pct_color). Prints nothing if the percentage
# can't be parsed.
usage_segment() {
  local label="$1" pct="$2" reset="$3" window_seconds="$4"
  local pct_int
  pct_int=$(printf '%.0f' "$pct" 2>/dev/null)
  [ -z "$pct_int" ] && return
  local color u_bar
  if [ -n "$reset" ] && [ "$reset" != "null" ]; then
    local elapsed_pct
    elapsed_pct=$(elapsed_pct_of_window "$reset" "$window_seconds")
    color=$(pace_color "$pct_int" "$elapsed_pct" "$RED")
    u_bar=$(pace_bar "$pct_int" "$elapsed_pct")
  else
    color=$(pct_color "$pct_int")
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
