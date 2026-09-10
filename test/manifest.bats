# shellcheck shell=bash
# Manifest sanity: a broken .claude-plugin/*.json should fail CI immediately
# rather than surface as a cryptic /plugin install failure later.

setup() {
  # Hermetic per CLAUDE.md -- these tests never invoke statusline-command.sh,
  # but new suites set all three regardless.
  export STATUSLINE_CONFIG="$BATS_TEST_TMPDIR/no-such.conf"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/no-such-claude-dir"
  export STATUSLINE_SEGMENTS_DIR="$BATS_TEST_TMPDIR/no-such-segments-dir"
}

@test "plugin.json is valid JSON naming the claude-statusline plugin" {
  [ "$(jq -r '.name' "$BATS_TEST_DIRNAME/../.claude-plugin/plugin.json")" = "claude-statusline" ]
}

@test "marketplace.json is valid JSON with one plugin entry sourced from the repo root" {
  local f="$BATS_TEST_DIRNAME/../.claude-plugin/marketplace.json"
  [ "$(jq '.plugins | length' "$f")" = "1" ]
  [ "$(jq -r '.plugins[0].name' "$f")" = "claude-statusline" ]
  [ "$(jq -r '.plugins[0].source' "$f")" = "./" ]
}

@test "setup skill has frontmatter naming it setup" {
  local f="$BATS_TEST_DIRNAME/../skills/setup/SKILL.md"
  [ -f "$f" ]
  [ "$(sed -n '1p' "$f")" = "---" ]
  grep -q '^name: setup$' "$f"
  grep -q '^description:' "$f"
}
