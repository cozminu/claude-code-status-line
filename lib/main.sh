# shellcheck shell=bash

# Sources every *.sh in `dir` (the resolved STATUSLINE_SEGMENTS_DIR) so a user
# can register their own segments. Called only from inside main(), never at
# plain source time, so `source`-ing the entrypoint (as test/unit.bats does,
# to reach helpers/segment builders directly) never executes a real user's
# plugin scripts.
load_segment_plugins() {
  local dir="$1" plugin
  [ -d "$dir" ] || return 0
  for plugin in "$dir"/*.sh; do
    [ -e "$plugin" ] || continue
    # shellcheck disable=SC1090
    . "$plugin"
  done
}

# Defaults STATUSLINE_LINE{1,2,3}_SEGMENTS to the order register_segment
# built up from built-in segments/*.sh plus any plugins — but only if the env
# or config file didn't already set them (load_config's snapshot/reassert
# already captured that precedence; this just supplies the default once the
# default is knowable).
finalize_segment_order() {
  : "${STATUSLINE_LINE1_SEGMENTS:=$STATUSLINE_LINE1_DEFAULT_ORDER}"
  : "${STATUSLINE_LINE2_SEGMENTS:=$STATUSLINE_LINE2_DEFAULT_ORDER}"
  : "${STATUSLINE_LINE3_SEGMENTS:=$STATUSLINE_LINE3_DEFAULT_ORDER}"
}

main() {
  load_config
  load_segment_plugins "$STATUSLINE_SEGMENTS_DIR"
  finalize_segment_order
  parse_payload

  local line1=() line2=() line3=()
  local rendered

  rendered=$(render_line STATUSLINE_LINE1_SEGMENTS)
  if [ -n "$rendered" ]; then
    while IFS= read -r seg; do line1+=("$seg"); done <<< "$rendered"
  fi

  rendered=$(render_line STATUSLINE_LINE2_SEGMENTS)
  if [ -n "$rendered" ]; then
    while IFS= read -r seg; do line2+=("$seg"); done <<< "$rendered"
  fi

  rendered=$(render_line STATUSLINE_LINE3_SEGMENTS)
  if [ -n "$rendered" ]; then
    while IFS= read -r seg; do line3+=("$seg"); done <<< "$rendered"
  fi

  # ${arr[@]+...} keeps empty-array expansion legal under set -u on bash 3.2.
  printf '%s\n' "$(join_line ${line1[@]+"${line1[@]}"})"
  [ "${#line2[@]}" -gt 0 ] && printf '%s\n' "$(join_line ${line2[@]+"${line2[@]}"})"
  [ "${#line3[@]}" -gt 0 ] && printf '%s\n' "$(join_line ${line3[@]+"${line3[@]}"})"
  exit 0
}
