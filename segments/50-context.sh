# shellcheck shell=bash
# Line 2: context-window usage, tokens used, colored by usage severity.

segment_context() {
  [ -n "$PAYLOAD_CTX_USED_PCT" ] && [ "$PAYLOAD_CTX_USED_PCT" != "null" ] \
    && [ -n "$PAYLOAD_CTX_TOKENS" ] && [ "$PAYLOAD_CTX_TOKENS" != "null" ] || return
  local pct_int
  pct_int=$(printf '%.0f' "$PAYLOAD_CTX_USED_PCT" 2>/dev/null)
  [ -n "$pct_int" ] || return
  printf '%s%s%s' "$(pct_color "$pct_int")" "$(fmt_tokens "$PAYLOAD_CTX_TOKENS")" "$RESET"
}
register_segment 2 context segment_context STATUSLINE_SHOW_CONTEXT
