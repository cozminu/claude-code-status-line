# End-to-end golden tests: each fixture payload is piped through the executed
# script with the clock pinned, and the output must match its golden file
# byte-for-byte (ANSI escapes included). This is the no-behavior-change
# safety net — if a refactor changes a single output byte, these fail.
#
# Fixtures use /nonexistent/... paths for current_dir so the git segment is
# deterministically skipped; git behavior is covered in git.bats.

SCRIPT="$BATS_TEST_DIRNAME/../statusline-command.sh"
# Must match STATUSLINE_NOW in regen-golden.sh.
STATUSLINE_EPOCH=1750000000

setup() {
  # Hermetic: a real user config file must not influence golden comparisons.
  export STATUSLINE_CONFIG="$BATS_TEST_TMPDIR/no-such.conf"
  # Hermetic: a real logged-in account must not leak into golden comparisons.
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/no-such-claude-dir"
  # Hermetic: a real segments.d plugin directory must not leak into golden comparisons.
  export STATUSLINE_SEGMENTS_DIR="$BATS_TEST_TMPDIR/no-such-segments-dir"
}

check_golden() {
  local name="$1"
  STATUSLINE_NOW="$STATUSLINE_EPOCH" "$SCRIPT" \
    < "$BATS_TEST_DIRNAME/fixtures/$name.json" \
    > "$BATS_TEST_TMPDIR/$name.out"
  diff "$BATS_TEST_DIRNAME/golden/$name.out" "$BATS_TEST_TMPDIR/$name.out"
}

@test "full payload: every segment renders" {
  check_golden full
}

@test "no effort field: effort segment dropped" {
  check_golden no-effort
}

@test "no rate_limits (API billing): 5h/7d segments dropped" {
  check_golden no-rate-limits
}

@test "resets_at missing: plain 5h bar, compact severity-colored 7d marker" {
  check_golden no-resets
}

@test "7d under pace: green compact marker" {
  check_golden seven-day-under-pace
}

@test "7d on pace (within tolerance): yellow compact marker" {
  check_golden seven-day-on-pace
}

@test "5h ahead of pace: solid pace tick, colored red not yellow/orange" {
  check_golden five-hour-ahead
}

@test "boundaries below thresholds: 49% green ctx, 79% yellow 5h, 999 tokens" {
  check_golden boundary-low
}

@test "boundaries at thresholds: 50% yellow ctx, 80% red 5h, 1k tokens" {
  check_golden boundary-high
}

@test "millions of tokens formatted as M; float pct rounds" {
  check_golden tokens-million
}

@test "cost-only payload: empty line 1, default model name" {
  check_golden cost-only
}

@test "empty JSON object: still renders and exits 0" {
  check_golden empty
}

@test "logged-in account: 3rd line renders the email from CLAUDE_CONFIG_DIR" {
  CLAUDE_CONFIG_DIR="$BATS_TEST_DIRNAME/fixtures/fake-claude-config" \
    STATUSLINE_SHOW_EMAIL=1 \
    STATUSLINE_NOW="$STATUSLINE_EPOCH" "$SCRIPT" \
    < "$BATS_TEST_DIRNAME/fixtures/full.json" \
    > "$BATS_TEST_TMPDIR/email.out"
  diff "$BATS_TEST_DIRNAME/golden/email.out" "$BATS_TEST_TMPDIR/email.out"
}

@test "script exits 0 for every fixture" {
  local f
  for f in "$BATS_TEST_DIRNAME"/fixtures/*.json; do
    STATUSLINE_NOW="$STATUSLINE_EPOCH" "$SCRIPT" < "$f" > /dev/null
  done
}
