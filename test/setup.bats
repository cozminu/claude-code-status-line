# shellcheck shell=bash
# scripts/setup.sh: the only thing in this repo allowed to write
# settings.json. Covers every row of the decision table in the plugin
# packaging spec, plus --force and the non-interactive refusal.

SETUP="$BATS_TEST_DIRNAME/../scripts/setup.sh"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
COMMAND_PATH="$REPO_ROOT/statusline-command.sh"

setup() {
  export STATUSLINE_CONFIG="$BATS_TEST_TMPDIR/no-such.conf"
  export STATUSLINE_SEGMENTS_DIR="$BATS_TEST_TMPDIR/no-such-segments-dir"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  SETTINGS="$BATS_TEST_TMPDIR/settings.json"
}

@test "no settings file: creates it with just the statusLine key" {
  run "$SETUP" --settings "$SETTINGS"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.command' "$SETTINGS")" = "$COMMAND_PATH" ]
  [ "$(jq -r '.statusLine.type' "$SETTINGS")" = "command" ]
  [ "$(jq 'keys | length' "$SETTINGS")" = "1" ]
}

@test "settings path has no parent directory yet: creates it" {
  SETTINGS="$BATS_TEST_TMPDIR/nested/does/not/exist/settings.json"
  run "$SETUP" --settings "$SETTINGS"
  [ "$status" -eq 0 ]
  [ -f "$SETTINGS" ]
}

@test "without --settings, writes to \$CLAUDE_CONFIG_DIR/settings.json" {
  run "$SETUP"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.command' "$CLAUDE_CONFIG_DIR/settings.json")" = "$COMMAND_PATH" ]
}

@test "settings file exists without a statusLine key: adds it without prompting" {
  echo '{"other":"stuff"}' > "$SETTINGS"
  run "$SETUP" --settings "$SETTINGS"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.command' "$SETTINGS")" = "$COMMAND_PATH" ]
  [ "$(jq -r '.other' "$SETTINGS")" = "stuff" ]
}

@test "statusLine already points at our path: reports and writes nothing" {
  jq -n --arg cmd "$COMMAND_PATH" '{statusLine:{type:"command",command:$cmd}}' > "$SETTINGS"
  cp "$SETTINGS" "$SETTINGS.orig"
  run "$SETUP" --settings "$SETTINGS"
  [ "$status" -eq 0 ]
  diff "$SETTINGS.orig" "$SETTINGS"
  [[ "$output" == *"nothing to do"* ]]
}

@test "statusLine points at an older version of this plugin: rewrites without prompting" {
  local old="$BATS_TEST_TMPDIR/plugins/cache/cozminu/claude-statusline/0.9.0/statusline-command.sh"
  jq -n --arg cmd "$old" '{statusLine:{type:"command",command:$cmd}}' > "$SETTINGS"
  run "$SETUP" --settings "$SETTINGS"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.command' "$SETTINGS")" = "$COMMAND_PATH" ]
}

@test "statusLine points somewhere foreign, non-interactive: refuses, exit 1, prints a paste block" {
  jq -n '{statusLine:{type:"command",command:"/usr/local/bin/other-statusline.sh"}}' > "$SETTINGS"
  run "$SETUP" --settings "$SETTINGS"
  [ "$status" -eq 1 ]
  [ "$(jq -r '.statusLine.command' "$SETTINGS")" = "/usr/local/bin/other-statusline.sh" ]
  [[ "$output" == *"--force"* ]]
  [[ "$output" == *"$COMMAND_PATH"* ]]
}

@test "statusLine points somewhere foreign, interactive accept: rewrites" {
  jq -n '{statusLine:{type:"command",command:"/usr/local/bin/other-statusline.sh"}}' > "$SETTINGS"
  run bash -c "STATUSLINE_SETUP_TTY=1 '$SETUP' --settings '$SETTINGS' <<< y"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.command' "$SETTINGS")" = "$COMMAND_PATH" ]
}

@test "statusLine points somewhere foreign, interactive decline: leaves it unchanged, exit 1" {
  jq -n '{statusLine:{type:"command",command:"/usr/local/bin/other-statusline.sh"}}' > "$SETTINGS"
  run bash -c "STATUSLINE_SETUP_TTY=1 '$SETUP' --settings '$SETTINGS' <<< n"
  [ "$status" -eq 1 ]
  [ "$(jq -r '.statusLine.command' "$SETTINGS")" = "/usr/local/bin/other-statusline.sh" ]
}

@test "malformed settings.json: refuses and writes nothing" {
  echo 'not json' > "$SETTINGS"
  run "$SETUP" --settings "$SETTINGS"
  [ "$status" -eq 1 ]
  [ "$(cat "$SETTINGS")" = "not json" ]
}

@test "--force overwrites a foreign value without prompting and backs it up" {
  jq -n '{statusLine:{type:"command",command:"/usr/local/bin/other-statusline.sh"}}' > "$SETTINGS"
  run "$SETUP" --settings "$SETTINGS" --force
  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.command' "$SETTINGS")" = "$COMMAND_PATH" ]
  [ "$(jq -r '.statusLine.command' "$SETTINGS.bak")" = "/usr/local/bin/other-statusline.sh" ]
}

@test "--help prints usage and exits 0" {
  run "$SETUP" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}
