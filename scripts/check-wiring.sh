#!/bin/bash
# Read-only SessionStart nudge: never writes settings.json (scripts/setup.sh
# is the only writer in this repo). Must stay silent whenever wiring is
# healthy, since SessionStart stdout is injected into Claude's context on
# every new session -- the healthy case has to cost zero tokens.
set -u -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMAND_PATH="$DIR/statusline-command.sh"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

# Kept in sync with scripts/setup.sh's copy of this same function; both must
# agree on what "an older version of this plugin" looks like.
is_stale_version() {
  case "$1" in
    */plugins/cache/*/claude-statusline/*/statusline-command.sh)
      [ "$1" != "$COMMAND_PATH" ] ;;
    *) return 1 ;;
  esac
}

command -v jq >/dev/null 2>&1 || exit 0
[ -f "$SETTINGS" ] || exit 0

EXISTING=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null) || exit 0

[ "$EXISTING" = "$COMMAND_PATH" ] && exit 0

if [ -z "$EXISTING" ]; then
  echo "claude-statusline is installed but not wired up as your statusLine. Run /claude-statusline:setup to enable it (don't edit settings.json by hand)."
  exit 0
fi

if is_stale_version "$EXISTING"; then
  echo "claude-statusline's statusLine still points at an older install ($EXISTING). Run /claude-statusline:setup to update it to $COMMAND_PATH (don't edit settings.json by hand)."
  exit 0
fi

exit 0
