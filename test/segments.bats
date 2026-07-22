# Segment registry tests: default ordering, config-driven reordering, a
# plugin's own show-toggle, name-collision override behavior, and the
# source-time-safety property (plugins never run just from `source`-ing the
# entrypoint, only from a real executed render).

SCRIPT="$BATS_TEST_DIRNAME/../statusline-command.sh"
STATUSLINE_EPOCH=1750000000

strip_ansi() {
  sed $'s/\033\\[[0-9;]*m//g'
}

setup() {
  export STATUSLINE_CONFIG="$BATS_TEST_TMPDIR/no-such.conf"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/no-such-claude-dir"
  export STATUSLINE_SEGMENTS_DIR="$BATS_TEST_TMPDIR/segments.d"
  export STATUSLINE_NOW="$STATUSLINE_EPOCH"
}

render_full() {
  "$SCRIPT" < "$BATS_TEST_DIRNAME/fixtures/full.json"
}

@test "default line order matches the shipped segments/ prefixes" {
  diff "$BATS_TEST_DIRNAME/golden/full.out" <(render_full)
}

@test "STATUSLINE_LINE2_SEGMENTS reorders line 2" {
  local out
  out=$(STATUSLINE_LINE2_SEGMENTS="cost model" render_full | strip_ansi | sed -n 2p)
  [[ "$out" == '$1.23'*"Fable 5"* ]]
}

@test "STATUSLINE_LINE2_SEGMENTS can drop a segment by omitting it from the list" {
  local out
  out=$(STATUSLINE_LINE2_SEGMENTS="model cost" render_full | strip_ansi | sed -n 2p)
  [[ "$out" != *"high"* ]]        # effort dropped
  [[ "$out" == *"Fable 5"* ]]
  [[ "$out" == *'$1.23'* ]]
}

@test "custom plugin segment registers, renders, and respects its own show-var" {
  mkdir -p "$STATUSLINE_SEGMENTS_DIR"
  cat > "$STATUSLINE_SEGMENTS_DIR/10-hello.sh" <<'EOF'
segment_hello() {
  printf 'HELLO_PLUGIN'
}
register_segment 2 hello segment_hello STATUSLINE_SHOW_HELLO
EOF
  local out
  out=$(STATUSLINE_LINE2_SEGMENTS="model hello" render_full | strip_ansi | sed -n 2p)
  [[ "$out" == *"HELLO_PLUGIN"* ]]

  out=$(STATUSLINE_LINE2_SEGMENTS="model hello" STATUSLINE_SHOW_HELLO=0 render_full | strip_ansi | sed -n 2p)
  [[ "$out" != *"HELLO_PLUGIN"* ]]
}

@test "a plugin can override a built-in segment by reusing its name" {
  mkdir -p "$STATUSLINE_SEGMENTS_DIR"
  cat > "$STATUSLINE_SEGMENTS_DIR/10-override-cost.sh" <<'EOF'
segment_cost_override() {
  printf 'OVERRIDDEN_COST'
}
register_segment 2 cost segment_cost_override
EOF
  local out status_out
  out=$(render_full | strip_ansi | sed -n 2p)
  [[ "$out" == *"OVERRIDDEN_COST"* ]]
  [[ "$out" != *'$1.23'* ]]

  status_out=$(render_full 2>&1 >/dev/null)
  [[ "$status_out" == *'"cost" already registered'* ]]
}

@test "plugins do not run when the entrypoint is merely sourced" {
  mkdir -p "$STATUSLINE_SEGMENTS_DIR"
  cat > "$STATUSLINE_SEGMENTS_DIR/poison.sh" <<'EOF'
echo "POISON EXECUTED" >> "$BATS_TEST_TMPDIR/poison-marker"
EOF
  ( source "$SCRIPT" )
  [ ! -e "$BATS_TEST_TMPDIR/poison-marker" ]
}

@test "plugins do run under a real executed render" {
  mkdir -p "$STATUSLINE_SEGMENTS_DIR"
  cat > "$STATUSLINE_SEGMENTS_DIR/marker.sh" <<'EOF'
echo "MARKER EXECUTED" >> "$BATS_TEST_TMPDIR/marker-ran"
segment_marker() { printf ''; }
register_segment 2 marker segment_marker
EOF
  render_full >/dev/null
  [ -e "$BATS_TEST_TMPDIR/marker-ran" ]
}
