# shellcheck shell=bash
# Line 1: project title (repo name from the payload, falling back to the
# cwd basename).

segment_title() {
  local title=""
  if [ -n "$PAYLOAD_REPO_NAME" ] && [ "$PAYLOAD_REPO_NAME" != "null" ]; then
    title="$PAYLOAD_REPO_NAME"
  elif [ -n "$PAYLOAD_CWD" ]; then
    title="${PAYLOAD_CWD##*/}"
  fi
  [ -n "$title" ] && printf '%s%s%s' "$DIM" "$title" "$RESET"
}
register_segment 1 title segment_title STATUSLINE_SHOW_TITLE
