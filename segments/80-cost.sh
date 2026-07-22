# shellcheck shell=bash
# Line 2: session cost in USD.

segment_cost() {
  [ -n "$PAYLOAD_COST_USD" ] && [ "$PAYLOAD_COST_USD" != "null" ] || return
  local cost_fmt
  cost_fmt=$(printf '$%.2f' "$PAYLOAD_COST_USD" 2>/dev/null)
  [ -n "$cost_fmt" ] || return
  printf '%s%s%s' "$GREEN" "$cost_fmt" "$RESET"
}
register_segment 2 cost segment_cost STATUSLINE_SHOW_COST
