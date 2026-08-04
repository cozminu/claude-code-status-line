# shellcheck shell=bash
# Line 2: context-window usage, tokens used, colored by its own 4-band
# usage severity scale (ctx_pct_color: green/yellow/orange/red).

segment_context() {
  [ -n "$PAYLOAD_CTX_USED_PCT" ] && [ "$PAYLOAD_CTX_USED_PCT" != "null" ] \
    && [ -n "$PAYLOAD_CTX_TOKENS" ] && [ "$PAYLOAD_CTX_TOKENS" != "null" ] || return
  local pct_int
  pct_int=$(printf '%.0f' "$PAYLOAD_CTX_USED_PCT" 2>/dev/null)
  [ -n "$pct_int" ] || return
  printf '%s%s%s' "$(ctx_pct_color "$pct_int")" "$(fmt_tokens "$PAYLOAD_CTX_TOKENS")" "$RESET"
}
register_segment 2 context segment_context STATUSLINE_SHOW_CONTEXT
