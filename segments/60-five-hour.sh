# shellcheck shell=bash
# Line 2: 5-hour subscription rate-limit usage. Label is a live reset
# countdown when a reset time is present, falling back to "5h" otherwise.

segment_five_hour() {
  [ -n "$PAYLOAD_FIVE_H_PCT" ] && [ "$PAYLOAD_FIVE_H_PCT" != "null" ] || return
  local label="5h"
  if [ -n "$PAYLOAD_FIVE_H_RESET" ] && [ "$PAYLOAD_FIVE_H_RESET" != "null" ]; then
    label="$(reset_countdown "$PAYLOAD_FIVE_H_RESET" 3600)h"
  fi
  usage_segment "$label" "$PAYLOAD_FIVE_H_PCT" "$PAYLOAD_FIVE_H_RESET" 18000
}
register_segment 2 five_hour segment_five_hour STATUSLINE_SHOW_FIVE_HOUR
