#!/bin/bash
# The only script in this repo allowed to write settings.json. Everything
# else here (statusline-command.sh, segments/*.sh, scripts/check-wiring.sh)
# only ever reads it.
set -u -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMAND_PATH="$DIR/statusline-command.sh"

FORCE=0
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

usage() {
  cat <<'EOF'
Usage: setup.sh [--force] [--settings PATH] [--help]

Wires this plugin's statusline-command.sh into Claude Code's
statusLine.command setting.

  --force          Overwrite an existing foreign statusLine value without
                    prompting (backs up the old settings.json to
                    settings.json.bak first).
  --settings PATH  Write to PATH instead of the default
                    ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json.
  --help           Show this message.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --settings)
      [ $# -ge 2 ] || { echo "setup.sh: --settings requires a path" >&2; exit 1; }
      SETTINGS="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "setup.sh: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

DESIRED=$(jq -n --arg cmd "$COMMAND_PATH" '{type:"command",command:$cmd}')

# "A different version of this same plugin": the existing value's command
# sits in the plugin cache under this plugin's name but at a different
# version directory than the one we just resolved -- an upgrade in
# progress. Kept in sync with scripts/check-wiring.sh's copy of this same
# function; both must agree on what "stale" means.
is_stale_version() {
  case "$1" in
    */plugins/cache/*/claude-statusline/*/statusline-command.sh)
      [ "$1" != "$COMMAND_PATH" ] ;;
    *) return 1 ;;
  esac
}

# Overridable for tests, which never have a real tty attached to stdin: set
# STATUSLINE_SETUP_TTY=1 to force the interactive prompt path, or leave
# unset to fall back to the real [ -t 0 ] check.
is_tty() {
  if [ -n "${STATUSLINE_SETUP_TTY:-}" ]; then
    [ "$STATUSLINE_SETUP_TTY" = "1" ]
  else
    [ -t 0 ]
  fi
}

write_settings() {
  local tmp
  tmp="$(mktemp "${SETTINGS}.XXXXXX")" || { echo "setup.sh: could not create a temp file" >&2; exit 1; }
  if ! jq --argjson sl "$DESIRED" '.statusLine = $sl' "$SETTINGS" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    echo "setup.sh: failed to write $SETTINGS" >&2
    exit 1
  fi
  mv "$tmp" "$SETTINGS"
}

mkdir -p "$(dirname "$SETTINGS")" || { echo "setup.sh: could not create $(dirname "$SETTINGS")" >&2; exit 1; }

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  echo "setup.sh: $SETTINGS is not valid JSON, refusing to touch it" >&2
  exit 1
fi

HAS_KEY=$(jq -r 'has("statusLine")' "$SETTINGS")

if [ "$HAS_KEY" != "true" ]; then
  write_settings
  echo "setup.sh: wrote statusLine -> $COMMAND_PATH"
  exit 0
fi

EXISTING=$(jq -r '.statusLine.command // empty' "$SETTINGS")

if [ "$EXISTING" = "$COMMAND_PATH" ]; then
  echo "setup.sh: statusLine already points at $COMMAND_PATH, nothing to do"
  exit 0
fi

if is_stale_version "$EXISTING"; then
  write_settings
  echo "setup.sh: updated statusLine from an older plugin version ($EXISTING) to $COMMAND_PATH"
  exit 0
fi

# Anything else: a foreign statusLine value, or a statusLine key present
# without a usable command field.
if [ "$FORCE" = "1" ]; then
  cp "$SETTINGS" "$SETTINGS.bak"
  write_settings
  echo "setup.sh: replaced foreign statusLine value (backed up to $SETTINGS.bak)"
  exit 0
fi

if is_tty; then
  echo "setup.sh: statusLine is currently set to:"
  echo "  $EXISTING"
  printf 'Replace it with %s? [y/N] ' "$COMMAND_PATH"
  read -r ans
  case "$ans" in
    [yY]|[yY][eE][sS])
      write_settings
      echo "setup.sh: wrote statusLine -> $COMMAND_PATH"
      exit 0
      ;;
    *)
      echo "setup.sh: left statusLine unchanged"
      exit 1
      ;;
  esac
else
  echo "setup.sh: statusLine is currently set to:"
  echo "  $EXISTING"
  echo "setup.sh: not prompting without a terminal. Either:"
  echo "  - re-run this in a terminal: ! bash \"$0\""
  echo "  - or pass --force to overwrite it"
  echo "setup.sh: paste this block into settings.json yourself if you prefer:"
  jq -n --argjson sl "$DESIRED" '{statusLine:$sl}'
  exit 1
fi
