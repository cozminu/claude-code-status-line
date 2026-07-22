# shellcheck shell=bash
# Line 3: logged-in Claude account email, read from CLAUDE_CONFIG_DIR rather
# than the stdin payload (which carries no account/user field).

segment_email() {
  local email
  email=$(account_email)
  [ -n "$email" ] || return
  printf '%s%s%s' "$CYAN" "$email" "$RESET"
}
register_segment 3 email segment_email STATUSLINE_SHOW_EMAIL
