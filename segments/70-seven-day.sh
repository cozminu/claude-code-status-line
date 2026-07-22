# shellcheck shell=bash
# Line 2: 7-day subscription rate-limit usage, compact pace marker that
# expands into a full bar only when running over pace.

segment_seven_day() {
  [ -n "$PAYLOAD_SEVEN_D_PCT" ] && [ "$PAYLOAD_SEVEN_D_PCT" != "null" ] || return
  local label="7d"
  if [ -n "$PAYLOAD_SEVEN_D_RESET" ] && [ "$PAYLOAD_SEVEN_D_RESET" != "null" ]; then
    label="$(reset_countdown "$PAYLOAD_SEVEN_D_RESET" 86400)d"
  fi
  seven_day_segment "$label" "$PAYLOAD_SEVEN_D_PCT" "$PAYLOAD_SEVEN_D_RESET" 604800
}
register_segment 2 seven_day segment_seven_day STATUSLINE_SHOW_SEVEN_DAY
