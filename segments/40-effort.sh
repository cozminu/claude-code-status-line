# shellcheck shell=bash
# Line 2: reasoning effort level, only when present in the payload.

segment_effort() {
  [ -n "$PAYLOAD_EFFORT" ] && [ "$PAYLOAD_EFFORT" != "null" ] || return
  printf '%s%s%s' "$(effort_color "$PAYLOAD_EFFORT")" "$PAYLOAD_EFFORT" "$RESET"
}
register_segment 2 effort segment_effort STATUSLINE_SHOW_EFFORT
