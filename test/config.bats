# Config-layer tests: precedence (env > file > default), segment toggles,
# and numeric tunables. Defaults must reproduce the golden output exactly.

SCRIPT="$BATS_TEST_DIRNAME/../statusline-command.sh"
STATUSLINE_EPOCH=1750000000

setup() {
  # Hermetic: never read a real user config unless a test writes one here.
  export STATUSLINE_CONFIG="$BATS_TEST_TMPDIR/statusline.conf"
  # Hermetic: never read a real logged-in account unless a test points here.
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/no-such-claude-dir"
  export STATUSLINE_NOW="$STATUSLINE_EPOCH"
}

render_full() {
  "$SCRIPT" < "$BATS_TEST_DIRNAME/fixtures/full.json"
}

strip_ansi() {
  sed $'s/\033\\[[0-9;]*m//g'
}

@test "defaults produce byte-identical golden output" {
  diff "$BATS_TEST_DIRNAME/golden/full.out" <(render_full)
}

@test "config file with explicit defaults produces byte-identical golden output" {
  cat > "$STATUSLINE_CONFIG" <<'EOF'
STATUSLINE_BAR_WIDTH=10
STATUSLINE_PCT_WARN=50
STATUSLINE_PCT_CRIT=80
STATUSLINE_PACE_TOL=5
EOF
  diff "$BATS_TEST_DIRNAME/golden/full.out" <(render_full)
}

@test "config file overrides default: bar width" {
  echo 'STATUSLINE_BAR_WIDTH=4' > "$STATUSLINE_CONFIG"
  run bash -c "'$SCRIPT' < '$BATS_TEST_DIRNAME/fixtures/full.json' | sed \$'s/\033\\[[0-9;]*m//g'"
  # 5h: 30% of 4 cells -> 1 filled, tick at cell 2 (elapsed 50%), hollow (behind)
  # label is a live countdown: full.json's five_hour reset is 2.5h out -> "3h"
  [[ "${lines[1]}" == *"3h █░▯░"* ]]
}

@test "environment overrides config file" {
  echo 'STATUSLINE_BAR_WIDTH=4' > "$STATUSLINE_CONFIG"
  run bash -c "STATUSLINE_BAR_WIDTH=6 '$SCRIPT' < '$BATS_TEST_DIRNAME/fixtures/full.json' | sed \$'s/\033\\[[0-9;]*m//g'"
  # 30% of 6 cells -> 1 filled, tick at cell 3, hollow
  [[ "${lines[1]}" == *"3h █░░▯░░"* ]]
}

@test "warn threshold is tunable: 42% context turns yellow when warn=30" {
  echo 'STATUSLINE_PCT_WARN=30' > "$STATUSLINE_CONFIG"
  local YELLOW=$'\033[33m'
  run render_full
  [[ "${lines[1]}" == *"${YELLOW}84k"* ]]
}

@test "pace tolerance is tunable: 7d 10 points over pace stays compact when tol=15" {
  # full.json: 7d usage 60%, elapsed 50%. Default tol 5 -> expanded orange bar;
  # tol 15 -> within band: compact yellow gauge glyph.
  echo 'STATUSLINE_PACE_TOL=15' > "$STATUSLINE_CONFIG"
  local YELLOW=$'\033[33m'
  run render_full
  [[ "${lines[1]}" == *"4d"*"${YELLOW}▅"* ]]
  [[ "${lines[1]}" != *"4d"*"█████"* ]]
}

@test "each line-2 toggle hides exactly its segment" {
  local plain toggles=(MODEL EFFORT CONTEXT FIVE_HOUR SEVEN_DAY COST)
  # full.json's reset timestamps -> live countdown labels "3h"/"4d" (not the
  # static "5h"/"7d") since STATUSLINE_NOW is pinned in setup().
  local markers=("Fable 5" "high" "84k" "3h" "4d" '$1.23')
  local i t
  for i in "${!toggles[@]}"; do
    t="${toggles[$i]}"
    plain=$(env "STATUSLINE_SHOW_$t=0" "$SCRIPT" < "$BATS_TEST_DIRNAME/fixtures/full.json" | strip_ansi)
    # Its own marker is gone...
    [[ "$plain" != *"${markers[$i]}"* ]]
    # ...and every other marker survives.
    local j
    for j in "${!markers[@]}"; do
      [ "$j" -eq "$i" ] && continue
      [[ "$plain" == *"${markers[$j]}"* ]]
    done
  done
}

@test "email toggle on: 3rd line shows the account email from CLAUDE_CONFIG_DIR" {
  local dir="$BATS_TEST_TMPDIR/fake-claude"
  mkdir -p "$dir"
  echo '{"oauthAccount":{"emailAddress":"test@example.com"}}' > "$dir/.claude.json"
  [[ "$(CLAUDE_CONFIG_DIR="$dir" render_full | strip_ansi)" == *"test@example.com"* ]]
}

@test "email toggle off: 3rd line hidden even with a logged-in account" {
  local dir="$BATS_TEST_TMPDIR/fake-claude"
  mkdir -p "$dir"
  echo '{"oauthAccount":{"emailAddress":"test@example.com"}}' > "$dir/.claude.json"
  [[ "$(CLAUDE_CONFIG_DIR="$dir" STATUSLINE_SHOW_EMAIL=0 render_full | strip_ansi)" != *"test@example.com"* ]]
}

@test "default profile: email still shown when CLAUDE_CONFIG_DIR is unset" {
  local home="$BATS_TEST_TMPDIR/fake-home"
  mkdir -p "$home/.claude"
  echo '{"oauthAccount":{"emailAddress":"test@example.com"}}' > "$home/.claude/.claude.json"
  local out
  out=$(unset CLAUDE_CONFIG_DIR; HOME="$home" render_full | strip_ansi)
  [[ "$out" == *"test@example.com"* ]]
}

@test "default profile: email still shown when CLAUDE_CONFIG_DIR equals \$HOME/.claude" {
  local home="$BATS_TEST_TMPDIR/fake-home2"
  mkdir -p "$home/.claude"
  echo '{"oauthAccount":{"emailAddress":"test@example.com"}}' > "$home/.claude/.claude.json"
  local out
  out=$(HOME="$home" CLAUDE_CONFIG_DIR="$home/.claude" render_full | strip_ansi)
  [[ "$out" == *"test@example.com"* ]]
}

@test "no logged-in account: email toggle on but no 3rd line renders" {
  local out
  out=$(render_full | strip_ansi)
  [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" = "2" ]
}

@test "title toggle empties line 1 for a non-git payload" {
  local plain
  plain=$(STATUSLINE_SHOW_TITLE=0 "$SCRIPT" < "$BATS_TEST_DIRNAME/fixtures/full.json" | strip_ansi)
  [ "$(printf '%s\n' "$plain" | head -1)" = "" ]
}

@test "git toggle hides the branch segment but keeps the title" {
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null
  local repo="$BATS_TEST_TMPDIR/proj"
  git -c init.defaultBranch=main init -q "$repo"
  local plain
  plain=$(printf '{"workspace":{"current_dir":"%s"}}' "$repo" \
    | STATUSLINE_SHOW_GIT=0 "$SCRIPT" | strip_ansi)
  [ "$(printf '%s\n' "$plain" | head -1)" = "proj" ]
}

@test "all toggles off still exits 0 and prints the (empty) line 1" {
  run env STATUSLINE_SHOW_TITLE=0 STATUSLINE_SHOW_GIT=0 STATUSLINE_SHOW_MODEL=0 \
    STATUSLINE_SHOW_EFFORT=0 STATUSLINE_SHOW_CONTEXT=0 STATUSLINE_SHOW_FIVE_HOUR=0 \
    STATUSLINE_SHOW_SEVEN_DAY=0 STATUSLINE_SHOW_COST=0 STATUSLINE_SHOW_EMAIL=0 \
    bash -c "'$SCRIPT' < '$BATS_TEST_DIRNAME/fixtures/full.json'"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
