# shellcheck shell=bash
# scripts/check-wiring.sh: read-only SessionStart nudge. Must never write
# settings.json, and must stay silent whenever wiring is healthy.

HOOK="$BATS_TEST_DIRNAME/../scripts/check-wiring.sh"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
COMMAND_PATH="$REPO_ROOT/statusline-command.sh"

setup() {
  export STATUSLINE_CONFIG="$BATS_TEST_TMPDIR/no-such.conf"
  export STATUSLINE_SEGMENTS_DIR="$BATS_TEST_TMPDIR/no-such-segments-dir"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  SETTINGS="$CLAUDE_CONFIG_DIR/settings.json"
}

@test "healthy wiring: silent, exit 0" {
  jq -n --arg cmd "$COMMAND_PATH" '{statusLine:{type:"command",command:$cmd}}' > "$SETTINGS"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "no statusLine key: one-line nudge naming the setup skill" {
  echo '{}' > "$SETTINGS"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/claude-statusline:setup"* ]]
}

@test "stale version: nudge names the old and current paths" {
  local old="$BATS_TEST_TMPDIR/plugins/cache/cozminu/claude-statusline/0.9.0/statusline-command.sh"
  jq -n --arg cmd "$old" '{statusLine:{type:"command",command:$cmd}}' > "$SETTINGS"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$old"* ]]
  [[ "$output" == *"$COMMAND_PATH"* ]]
}

@test "foreign statusLine (someone else's status line): silent, exit 0" {
  jq -n '{statusLine:{type:"command",command:"/usr/local/bin/other-statusline.sh"}}' > "$SETTINGS"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "no settings file at all: silent, exit 0" {
  run "$HOOK"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "malformed settings.json: silent, exit 0" {
  echo 'not json' > "$SETTINGS"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
