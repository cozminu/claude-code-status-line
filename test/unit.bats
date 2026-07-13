# Unit tests for the pure helpers: the script is sourced (the source guard
# keeps main from running), load_config fills in defaults, and each function
# is called directly.

setup() {
  export STATUSLINE_CONFIG="$BATS_TEST_TMPDIR/no-such.conf"
  source "$BATS_TEST_DIRNAME/../statusline-command.sh"
  load_config
}

# --- fmt_tokens --------------------------------------------------------------

@test "fmt_tokens: below 1000 prints the raw number" {
  [ "$(fmt_tokens 0)" = "0" ]
  [ "$(fmt_tokens 999)" = "999" ]
}

@test "fmt_tokens: thousands get a k suffix, .0 stripped" {
  [ "$(fmt_tokens 1000)" = "1k" ]
  [ "$(fmt_tokens 1500)" = "1.5k" ]
  [ "$(fmt_tokens 84000)" = "84k" ]
}

@test "fmt_tokens: millions get an M suffix, .0 stripped" {
  [ "$(fmt_tokens 1000000)" = "1M" ]
  [ "$(fmt_tokens 2500000)" = "2.5M" ]
  [ "$(fmt_tokens 2000000)" = "2M" ]
}

# --- color scales -------------------------------------------------------------

@test "pct_color: green below warn, yellow below crit, red at and above crit" {
  [ "$(pct_color 0)" = "$GREEN" ]
  [ "$(pct_color 49)" = "$GREEN" ]
  [ "$(pct_color 50)" = "$YELLOW" ]
  [ "$(pct_color 79)" = "$YELLOW" ]
  [ "$(pct_color 80)" = "$RED" ]
  [ "$(pct_color 100)" = "$RED" ]
}

@test "pace_color: green under pace, yellow within ±tolerance, orange over" {
  [ "$(pace_color 40 50)" = "$GREEN" ]   # 10 under
  [ "$(pace_color 45 50)" = "$YELLOW" ]  # exactly -tol
  [ "$(pace_color 55 50)" = "$YELLOW" ]  # exactly +tol
  [ "$(pace_color 56 50)" = "$ORANGE" ]  # past +tol
}

@test "effort_color: five levels plus a fallback" {
  [ "$(effort_color low)" = "$GREEN" ]
  [ "$(effort_color medium)" = "$YELLOW" ]
  [ "$(effort_color high)" = "$TEAL" ]
  [ "$(effort_color xhigh)" = "$BOLD_RED" ]
  [ "$(effort_color max)" = "$BOLD_MAGENTA" ]
  [ "$(effort_color surprise)" = "$CYAN" ]
}

@test "model_color: per-family colors, case-insensitive, cyan fallback" {
  [ "$(model_color 'Opus 4.8')" = "$BRIGHT_BLUE" ]
  [ "$(model_color 'SONNET 5')" = "$CYAN" ]
  [ "$(model_color 'Haiku 4.5')" = "$WHITE" ]
  [ "$(model_color 'Fable 5')" = "$MAGENTA" ]
  [ "$(model_color 'Mystery 1')" = "$CYAN" ]
}

# --- bars and gauges -----------------------------------------------------------

@test "bar: fill proportion at width 10, truncating" {
  [ "$(bar 0)" = "░░░░░░░░░░" ]
  [ "$(bar 9)" = "░░░░░░░░░░" ]
  [ "$(bar 10)" = "█░░░░░░░░░" ]
  [ "$(bar 50)" = "█████░░░░░" ]
  [ "$(bar 100)" = "██████████" ]
}

@test "bar: over 100% clamps to full" {
  [ "$(bar 130)" = "██████████" ]
}

@test "pace_bar: hollow tick when behind pace, at the elapsed position" {
  [ "$(pace_bar 30 50)" = "███░░▯░░░░" ]
}

@test "pace_bar: solid tick when at or ahead of pace" {
  [ "$(pace_bar 60 50)" = "█████▮░░░░" ]
  [ "$(pace_bar 50 50)" = "█████▮░░░░" ]
}

@test "pace_bar: tick clamps inside the bar at both ends" {
  [ "$(pace_bar 100 100)" = "█████████▮" ]
  [ "$(pace_bar 10 0)" = "▮░░░░░░░░░" ]
}

@test "gauge_glyph: maps 0-100% onto 8 block heights, clamped" {
  [ "$(gauge_glyph 0)" = "▁" ]
  [ "$(gauge_glyph 12)" = "▁" ]
  [ "$(gauge_glyph 13)" = "▂" ]
  [ "$(gauge_glyph 50)" = "▅" ]
  [ "$(gauge_glyph 99)" = "█" ]
  [ "$(gauge_glyph 100)" = "█" ]
}

# --- pace math -----------------------------------------------------------------

@test "elapsed_pct_of_window: halfway through a 5h window" {
  STATUSLINE_NOW=1750000000
  [ "$(elapsed_pct_of_window 1750009000 18000)" = "50" ]
}

@test "elapsed_pct_of_window: clamps to 100 when reset has passed" {
  STATUSLINE_NOW=1750000000
  [ "$(elapsed_pct_of_window 1749999999 18000)" = "100" ]
}

@test "elapsed_pct_of_window: clamps to 0 when reset is a full window away" {
  STATUSLINE_NOW=1750000000
  [ "$(elapsed_pct_of_window 1750100000 18000)" = "0" ]
}

@test "reset_countdown: ceils partial units up" {
  STATUSLINE_NOW=1750000000
  [ "$(reset_countdown 1750009000 3600)" = "3" ]   # 2.5h away -> 3
}

@test "reset_countdown: exact multiple of the unit does not round up" {
  STATUSLINE_NOW=1750000000
  [ "$(reset_countdown 1750003600 3600)" = "1" ]   # exactly 1h away -> 1, not 2
}

@test "reset_countdown: zero or past reset prints <1" {
  STATUSLINE_NOW=1750000000
  [ "$(reset_countdown 1750000000 3600)" = "<1" ]  # reset is now
  [ "$(reset_countdown 1749999999 3600)" = "<1" ]  # reset already passed
}

@test "reset_countdown: works in day-sized units" {
  STATUSLINE_NOW=1750000000
  [ "$(reset_countdown 1750302400 86400)" = "4" ]  # 3.5d away -> 4
}

# --- join_line -------------------------------------------------------------------

@test "join_line: empty, single, and multiple segments" {
  [ "$(join_line)" = "" ]
  [ "$(join_line one)" = "one" ]
  [ "$(join_line a b c)" = "a${DIM} | ${RESET}b${DIM} | ${RESET}c" ]
}

# --- segment builders ------------------------------------------------------------

@test "usage_segment: dim label + severity-colored pace bar" {
  STATUSLINE_NOW=1750000000
  [ "$(usage_segment 5h 30 1750009000 18000)" = "${DIM}5h${RESET} ${GREEN}███░░▯░░░░${RESET}" ]
}

@test "usage_segment: plain bar without a reset time" {
  [ "$(usage_segment 5h 45 '' 18000)" = "${DIM}5h${RESET} ${GREEN}████░░░░░░${RESET}" ]
}

@test "usage_segment: unparseable percentage coerces to a 0% bar" {
  # bash printf '%.0f' turns junk into 0, so this renders an empty bar
  # rather than nothing; callers guard against empty/null before calling.
  [ "$(usage_segment 5h junk '' 18000)" = "${DIM}5h${RESET} ${GREEN}░░░░░░░░░░${RESET}" ]
}

@test "seven_day_segment: compact glyph on pace, expanded orange bar over pace" {
  STATUSLINE_NOW=1750000000
  # 52% at 50% elapsed: within tolerance, compact yellow gauge
  [ "$(seven_day_segment 7d 52 1750302400 604800)" = "${DIM}7d${RESET} ${YELLOW}▅${RESET}" ]
  # 60% at 50% elapsed: over pace, expands to an orange pace bar
  [ "$(seven_day_segment 7d 60 1750302400 604800)" = "${DIM}7d${RESET} ${ORANGE}█████▮░░░░${RESET}" ]
}

@test "seven_day_segment: no reset time falls back to severity-colored compact glyph" {
  [ "$(seven_day_segment 7d 85 '' 604800)" = "${DIM}7d${RESET} ${RED}▇${RESET}" ]
}

# --- account_email -------------------------------------------------------------

@test "account_email: reads oauthAccount.emailAddress from CLAUDE_CONFIG_DIR/.claude.json" {
  local dir="$BATS_TEST_TMPDIR/fake-claude"
  mkdir -p "$dir"
  echo '{"oauthAccount":{"emailAddress":"test@example.com"}}' > "$dir/.claude.json"
  [ "$(CLAUDE_CONFIG_DIR="$dir" account_email)" = "test@example.com" ]
}

@test "account_email: empty string when CLAUDE_CONFIG_DIR has no .claude.json" {
  [ "$(CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/no-such-dir" account_email)" = "" ]
}

@test "account_email: empty string when .claude.json has no oauthAccount" {
  local dir="$BATS_TEST_TMPDIR/fake-claude-nologin"
  mkdir -p "$dir"
  echo '{}' > "$dir/.claude.json"
  [ "$(CLAUDE_CONFIG_DIR="$dir" account_email)" = "" ]
}

# --- using_default_claude_profile -----------------------------------------------

@test "using_default_claude_profile: true when CLAUDE_CONFIG_DIR is unset" {
  (unset CLAUDE_CONFIG_DIR; HOME=/fake/home using_default_claude_profile)
}

@test "using_default_claude_profile: true when CLAUDE_CONFIG_DIR equals \$HOME/.claude" {
  HOME=/fake/home CLAUDE_CONFIG_DIR=/fake/home/.claude using_default_claude_profile
}

@test "using_default_claude_profile: false when CLAUDE_CONFIG_DIR points elsewhere" {
  ! HOME=/fake/home CLAUDE_CONFIG_DIR=/fake/home/.claude-perso using_default_claude_profile
}
