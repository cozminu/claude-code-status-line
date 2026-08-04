# Emotion Segment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a line-2 segment that renders Claude's inferred emotional state — read from the separately-installed `emotion-statusline` plugin's per-session cache file — as a colored label, with a bold-red special case for `desperate`.

**Architecture:** Thread `session_id` through the existing single-jq-pass payload parser (`lib/payload.sh`), add a new external-state reader `lib/emotion.sh` (peer to `lib/git.sh`/`lib/account.sh`) that reads and freshness-checks the plugin's cache file, and a new `segments/25-emotion.sh` that maps the 14 emotion names onto this repo's existing color palette and registers itself first on line 2. This repo never classifies emotion — it only renders whatever cache file the plugin's own `Stop` hook already wrote.

**Tech Stack:** bash 3.2 (macOS system bash), `jq`, bats-core (vendored under `test/vendor/`), shellcheck.

## Global Constraints

- Must stay bash 3.2 compatible: no `mapfile`, no associative arrays, no `${var,,}` (from `CLAUDE.md`).
- `shellcheck -x statusline-command.sh` and `shellcheck segments/*.sh` must both stay at zero findings (from `CLAUDE.md`).
- Golden e2e output (`test/golden/*.out`) is byte-exact; a change must come from an intentional, reviewed regeneration, never a silent side effect (from `CLAUDE.md`). This plan's tasks are designed so **no existing golden file changes** — verify this explicitly in Task 3 and Task 4.
- Every new/changed test suite touchpoint must stay hermetic: point `STATUSLINE_CONFIG`, `CLAUDE_CONFIG_DIR`, and `STATUSLINE_SEGMENTS_DIR` at nonexistent paths unless a test deliberately provides one (from `CLAUDE.md`). All tasks below reuse the existing suites' `setup()` blocks, which already do this.
- Clock reads must go through `${STATUSLINE_NOW:-$(date +%s)}`, never raw `date +%s` directly, so goldens stay deterministic (established by `elapsed_pct_of_window`/`reset_countdown` in `lib/helpers.sh`).
- New external-state segments read state via a dedicated `lib/*.sh` function (`git_segment_text()`, `account_email()`), never inline in the `segments/*.sh` file — the segment file only formats/colors what the reader returns.
- Full design detail lives in `docs/superpowers/specs/2026-07-31-emotion-segment-design.md`; this plan implements it task-by-task.

---

### Task 1: Thread `session_id` through the payload parser

**Files:**
- Modify: `lib/payload.sh`
- Test: `test/unit.bats`

**Interfaces:**
- Produces: `PAYLOAD_SESSION_ID` — a new global set by `parse_payload()`, empty string when `session_id` is absent from the JSON payload. Task 2's `emotion_state()` reads this global directly (same pattern every other segment builder uses for `PAYLOAD_*`).

- [ ] **Step 1: Write the failing tests**

Append to the end of `test/unit.bats`:

```bash
# --- parse_payload (session_id) ------------------------------------------------

@test "parse_payload: extracts session_id into PAYLOAD_SESSION_ID" {
  parse_payload <<< '{"session_id":"abc-123"}'
  [ "$PAYLOAD_SESSION_ID" = "abc-123" ]
}

@test "parse_payload: PAYLOAD_SESSION_ID is empty when session_id is absent" {
  parse_payload <<< '{}'
  [ "$PAYLOAD_SESSION_ID" = "" ]
}
```

**Do not write these as `echo '{...}' | parse_payload`.** `parse_payload()` doesn't
read stdin in its own loop — it feeds `jq` via `< <(...)` and reads *that* — so a
pipeline puts the JSON in the right place but runs the whole function body in a
subshell, discarding every `PAYLOAD_*` assignment before the assertion sees it.
The test would then fail identically before *and* after the implementation.
Verified against the current code:

```
$ PAYLOAD_MODEL=SENTINEL; echo '{"model":{"display_name":"Zed"}}' | parse_payload; echo "$PAYLOAD_MODEL"
SENTINEL
$ parse_payload <<< '{"model":{"display_name":"Zed"}}'; echo "$PAYLOAD_MODEL"
Zed
```

There are no pre-existing `parse_payload` bats tests to copy an idiom from — these
are the first, so the here-string form has to be gotten right here.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./test/vendor/bats-core/bin/bats test/unit.bats`
Expected: the first test FAILs — `parse_payload()` doesn't set the variable, and
bats runs tests without `set -u` (its `SHELLOPTS` is `errexit:errtrace:functrace:...`,
no `nounset`), so `$PAYLOAD_SESSION_ID` expands to `""` and the comparison against
`abc-123` is what fails. The second test asserts *emptiness*, so it passes
trivially at this point — that's expected, it's a regression guard for the
absent-field default, not a red-first test.

- [ ] **Step 3: Implement — add the field to `parse_payload()`**

Replace the full body of `parse_payload()` in `lib/payload.sh` with:

```bash
parse_payload() {
  PAYLOAD_MODEL="Claude"
  PAYLOAD_EFFORT=""
  PAYLOAD_CWD=""
  PAYLOAD_CTX_USED_PCT=""
  PAYLOAD_CTX_TOKENS=""
  PAYLOAD_FIVE_H_PCT=""
  PAYLOAD_FIVE_H_RESET=""
  PAYLOAD_SEVEN_D_PCT=""
  PAYLOAD_SEVEN_D_RESET=""
  PAYLOAD_COST_USD=""
  PAYLOAD_REPO_NAME=""
  PAYLOAD_SESSION_ID=""

  local key value
  while IFS=$'\t' read -r key value; do
    case "$key" in
      model)         PAYLOAD_MODEL="$value" ;;
      effort)        PAYLOAD_EFFORT="$value" ;;
      cwd)           PAYLOAD_CWD="$value" ;;
      ctx_used_pct)  PAYLOAD_CTX_USED_PCT="$value" ;;
      ctx_tokens)    PAYLOAD_CTX_TOKENS="$value" ;;
      five_h_pct)    PAYLOAD_FIVE_H_PCT="$value" ;;
      five_h_reset)  PAYLOAD_FIVE_H_RESET="$value" ;;
      seven_d_pct)   PAYLOAD_SEVEN_D_PCT="$value" ;;
      seven_d_reset) PAYLOAD_SEVEN_D_RESET="$value" ;;
      cost_usd)      PAYLOAD_COST_USD="$value" ;;
      repo_name)     PAYLOAD_REPO_NAME="$value" ;;
      session_id)    PAYLOAD_SESSION_ID="$value" ;;
      *) : ;;  # unknown key: ignore, forward-compatible with future fields
    esac
  done < <(jq -r '
    "model\t\(.model.display_name // "Claude")",
    "effort\t\(.effort.level // "")",
    "cwd\t\(.workspace.current_dir // .cwd // "")",
    "ctx_used_pct\t\(.context_window.used_percentage // "")",
    "ctx_tokens\t\(((.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)))",
    "five_h_pct\t\(.rate_limits.five_hour.used_percentage // "")",
    "five_h_reset\t\(.rate_limits.five_hour.resets_at // "")",
    "seven_d_pct\t\(.rate_limits.seven_day.used_percentage // "")",
    "seven_d_reset\t\(.rate_limits.seven_day.resets_at // "")",
    "cost_usd\t\(.cost.total_cost_usd // "")",
    "repo_name\t\(.workspace.repo.name // "")",
    "session_id\t\(.session_id // "")"
  ')
}
```

(Only three lines are new: the `PAYLOAD_SESSION_ID=""` init, the `session_id)` case arm, and the `"session_id\t\(.session_id // "")"` jq line — order among the jq lines/case arms doesn't matter, per `lib/payload.sh`'s existing header comment.)

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./test/vendor/bats-core/bin/bats test/unit.bats`
Expected: PASS, all tests including the two new ones.

- [ ] **Step 5: Run the full suite to confirm no golden regressions**

Run: `./run-tests.sh`
Expected: PASS. No `test/golden/*.out` diffs — `session_id` is a new, previously-unparsed field; no existing segment reads it yet.

- [ ] **Step 6: Commit**

```bash
git add lib/payload.sh test/unit.bats
git commit -m "Parse session_id into PAYLOAD_SESSION_ID"
```

---

### Task 2: `lib/emotion.sh` — read the emotion cache file

**Files:**
- Create: `lib/emotion.sh`
- Modify: `statusline-command.sh`
- Test: `test/unit.bats`

**Interfaces:**
- Consumes: `PAYLOAD_SESSION_ID` (Task 1), `CLAUDE_CONFIG_DIR`/`HOME` env, `STATUSLINE_NOW` env (optional, injected clock).
- Produces: `emotion_state()` — zero-argument function, prints the emotion name (e.g. `curious`, `desperate`) to stdout with no trailing newline artifacts beyond what `jq -r` emits, or prints nothing on any failure (no cache file, stale cache, malformed JSON, missing `.emotion` field). Always returns 0. Task 3's `segment_emotion()` calls this directly.

- [ ] **Step 1: Write the failing tests**

Append to the end of `test/unit.bats`:

```bash
# --- emotion_state --------------------------------------------------------------

@test "emotion_state: reads emotion from a fresh session-specific cache file" {
  local dir="$BATS_TEST_TMPDIR/fake-claude"
  mkdir -p "$dir/cache"
  echo '{"emotion":"curious"}' > "$dir/cache/claude-emotion-sess1.json"
  [ "$(CLAUDE_CONFIG_DIR="$dir" PAYLOAD_SESSION_ID=sess1 emotion_state)" = "curious" ]
}

@test "emotion_state: falls back to the global cache file when there is no session id" {
  local dir="$BATS_TEST_TMPDIR/fake-claude"
  mkdir -p "$dir/cache"
  echo '{"emotion":"calm"}' > "$dir/cache/claude-emotion.json"
  [ "$(CLAUDE_CONFIG_DIR="$dir" PAYLOAD_SESSION_ID='' emotion_state)" = "calm" ]
}

@test "emotion_state: falls back to the global cache when the session-specific file doesn't exist" {
  local dir="$BATS_TEST_TMPDIR/fake-claude"
  mkdir -p "$dir/cache"
  echo '{"emotion":"focused"}' > "$dir/cache/claude-emotion.json"
  [ "$(CLAUDE_CONFIG_DIR="$dir" PAYLOAD_SESSION_ID=sess-missing emotion_state)" = "focused" ]
}

@test "emotion_state: a cache exactly 600s old is still fresh" {
  local dir="$BATS_TEST_TMPDIR/fake-claude"
  mkdir -p "$dir/cache"
  echo '{"emotion":"curious"}' > "$dir/cache/claude-emotion.json"
  local mtime
  mtime=$(stat -f %m "$dir/cache/claude-emotion.json")
  [ "$(CLAUDE_CONFIG_DIR="$dir" PAYLOAD_SESSION_ID='' STATUSLINE_NOW="$(( mtime + 600 ))" emotion_state)" = "curious" ]
}

@test "emotion_state: empty string once the cache is older than 600s" {
  local dir="$BATS_TEST_TMPDIR/fake-claude"
  mkdir -p "$dir/cache"
  echo '{"emotion":"curious"}' > "$dir/cache/claude-emotion.json"
  local mtime
  mtime=$(stat -f %m "$dir/cache/claude-emotion.json")
  [ "$(CLAUDE_CONFIG_DIR="$dir" PAYLOAD_SESSION_ID='' STATUSLINE_NOW="$(( mtime + 601 ))" emotion_state)" = "" ]
}

@test "emotion_state: empty string when no cache file exists" {
  [ "$(CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/no-such-claude-dir" PAYLOAD_SESSION_ID='' emotion_state)" = "" ]
}

@test "emotion_state: empty string when the cache file is malformed JSON" {
  local dir="$BATS_TEST_TMPDIR/fake-claude"
  mkdir -p "$dir/cache"
  echo 'not json' > "$dir/cache/claude-emotion.json"
  [ "$(CLAUDE_CONFIG_DIR="$dir" PAYLOAD_SESSION_ID='' emotion_state)" = "" ]
}

@test "emotion_state: empty string when the cache file has no emotion field" {
  local dir="$BATS_TEST_TMPDIR/fake-claude"
  mkdir -p "$dir/cache"
  echo '{}' > "$dir/cache/claude-emotion.json"
  [ "$(CLAUDE_CONFIG_DIR="$dir" PAYLOAD_SESSION_ID='' emotion_state)" = "" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./test/vendor/bats-core/bin/bats test/unit.bats`
Expected: the 4 tests asserting a *value* (`curious` twice, `calm`, `focused`) FAIL —
`emotion_state: command not found`, so `$(...)` captures nothing and the comparison
against the emotion name fails. The 4 tests asserting `= ""` (601s stale, no cache
file, malformed JSON, no `.emotion` field) **pass trivially at this point**, since a
missing command also yields empty output; they are fail-closed regression guards, not
red-first tests. Do not treat their passing as a sign the implementation already
exists.

- [ ] **Step 3: Implement — create `lib/emotion.sh`**

```bash
# shellcheck shell=bash

# Reads the cache file written by the separately-installed emotion-statusline
# plugin (bencium/bencium-marketplace) and returns the classified emotion for
# this session, or "" if unavailable/stale/malformed. This repo never
# classifies emotion or writes this cache — only renders it, the same
# "external state, not the stdin payload" pattern account_email() uses for
# line 3. Fails closed on every error path, matching account_email/
# git_segment_text.
emotion_state() {
  local session="${PAYLOAD_SESSION_ID:-}"
  local cache_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cache"
  local file="$cache_dir/claude-emotion.json"
  if [ -n "$session" ] && [ -f "$cache_dir/claude-emotion-$session.json" ]; then
    file="$cache_dir/claude-emotion-$session.json"
  fi
  [ -f "$file" ] || return 0

  local mtime now age
  mtime=$(stat -f %m "$file" 2>/dev/null) || return 0
  now="${STATUSLINE_NOW:-$(date +%s)}"
  age=$(( now - mtime ))
  [ "$age" -le 600 ] || return 0

  jq -r '.emotion // ""' "$file" 2>/dev/null
}
```

Two details that are load-bearing:

- `-le 600`, not `-lt`: the spec defines stale as `age > 600`, so a cache file
  exactly 600s old is still fresh. The two boundary tests above pin both sides.
- `${PAYLOAD_SESSION_ID:-}`, not a bare `$PAYLOAD_SESSION_ID`: a real render runs
  under `set -u` (see the source guard in `statusline-command.sh`), and while
  `parse_payload` always runs before any segment builder today, the `:-` costs
  nothing and keeps a plugin that calls `emotion_state()` out of band from
  aborting the whole render.

- [ ] **Step 4: Source the new file from the entrypoint**

In `statusline-command.sh`, add the source line right after `lib/account.sh`:

```bash
# shellcheck source=lib/git.sh
. "$DIR/lib/git.sh"
# shellcheck source=lib/account.sh
. "$DIR/lib/account.sh"
# shellcheck source=lib/emotion.sh
. "$DIR/lib/emotion.sh"
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./test/vendor/bats-core/bin/bats test/unit.bats`
Expected: PASS, all tests including the 8 new ones (both freshness-boundary cases included).

- [ ] **Step 6: Run the full suite and shellcheck**

Run: `./run-tests.sh`
Expected: PASS, zero shellcheck findings (the new `# shellcheck source=lib/emotion.sh` directive pulls `lib/emotion.sh` into the same analysis unit as the entrypoint), no golden diffs (`emotion_state()` exists but nothing calls it yet).

- [ ] **Step 7: Commit**

```bash
git add lib/emotion.sh statusline-command.sh test/unit.bats
git commit -m "Add emotion_state(): read the emotion-statusline plugin's cache file"
```

---

### Task 3: `segments/25-emotion.sh` — render the label

**Files:**
- Create: `segments/25-emotion.sh`
- Modify: `lib/config.sh`
- Test: `test/config.bats`

**Interfaces:**
- Consumes: `emotion_state()` (Task 2); `$CYAN $WHITE $GREEN $YELLOW $MAGENTA $BRIGHT_BLUE $RED $TEAL $DIM $BOLD_RED $RESET` (`lib/colors.sh`); `register_segment()` (`lib/registry.sh`); `STATUSLINE_SHOW_EMOTION` (new config var, this task).
- Produces: `segment_emotion()`, registered as `register_segment 2 emotion segment_emotion STATUSLINE_SHOW_EMOTION` — sorts first in the default line-2 order since `25-emotion.sh` sorts before `30-model.sh`.

- [ ] **Step 1: Write the failing tests**

Add to `test/config.bats`, after the existing `email` toggle tests (i.e. right before the `"title toggle empties line 1..."` test):

```bash
@test "emotion toggle on by default: cache emotion leads line 2" {
  local dir="$BATS_TEST_TMPDIR/fake-claude-emotion"
  mkdir -p "$dir/cache"
  echo '{"emotion":"curious"}' > "$dir/cache/claude-emotion.json"
  touch -t "$(date -r "$STATUSLINE_EPOCH" +%Y%m%d%H%M.%S)" "$dir/cache/claude-emotion.json"
  [[ "$(CLAUDE_CONFIG_DIR="$dir" render_full | strip_ansi)" == *"curious"* ]]
}

@test "emotion toggle off: cache emotion hidden even when present" {
  local dir="$BATS_TEST_TMPDIR/fake-claude-emotion"
  mkdir -p "$dir/cache"
  echo '{"emotion":"curious"}' > "$dir/cache/claude-emotion.json"
  touch -t "$(date -r "$STATUSLINE_EPOCH" +%Y%m%d%H%M.%S)" "$dir/cache/claude-emotion.json"
  [[ "$(CLAUDE_CONFIG_DIR="$dir" STATUSLINE_SHOW_EMOTION=0 render_full | strip_ansi)" != *"curious"* ]]
}

@test "emotion desperate case: renders the bold-red warning text" {
  local dir="$BATS_TEST_TMPDIR/fake-claude-emotion"
  mkdir -p "$dir/cache"
  echo '{"emotion":"desperate"}' > "$dir/cache/claude-emotion.json"
  touch -t "$(date -r "$STATUSLINE_EPOCH" +%Y%m%d%H%M.%S)" "$dir/cache/claude-emotion.json"
  [[ "$(CLAUDE_CONFIG_DIR="$dir" render_full | strip_ansi)" == *"DESPERATE — verify output quality"* ]]
}

@test "emotion unrecognized: renders as plain uncolored text rather than dropping" {
  local dir="$BATS_TEST_TMPDIR/fake-claude-emotion"
  mkdir -p "$dir/cache"
  echo '{"emotion":"flabbergasted"}' > "$dir/cache/claude-emotion.json"
  touch -t "$(date -r "$STATUSLINE_EPOCH" +%Y%m%d%H%M.%S)" "$dir/cache/claude-emotion.json"
  local out
  # emotion is the first segment on line 2, so an uncolored render means line 2
  # begins with the bare word — no leading escape sequence at all.
  out=$(CLAUDE_CONFIG_DIR="$dir" render_full | sed -n 2p)
  [[ "$out" == "flabbergasted"* ]]
}
```

(That last case covers design point 4 of the spec — an emotion name the upstream
classifier adds later must fail *open* on rendering, even though the cache-read
path fails closed on availability.)

(`STATUSLINE_EPOCH` and `strip_ansi` are already defined at the top of `test/config.bats`; `setup()` already exports `STATUSLINE_NOW="$STATUSLINE_EPOCH"`. The `touch -t` pins the cache file's mtime to that same epoch so `emotion_state()`'s freshness check is deterministic regardless of when the repo was checked out — BSD `date -r`/`touch -t`, matching this repo's macOS-only tooling assumption used elsewhere, e.g. `git.bats`.)

Also extend the existing "all toggles off" test (near the end of `test/config.bats`) to include the new toggle — change:

```bash
@test "all toggles off still exits 0 and prints the (empty) line 1" {
  run env STATUSLINE_SHOW_TITLE=0 STATUSLINE_SHOW_GIT=0 STATUSLINE_SHOW_MODEL=0 \
    STATUSLINE_SHOW_EFFORT=0 STATUSLINE_SHOW_CONTEXT=0 STATUSLINE_SHOW_FIVE_HOUR=0 \
    STATUSLINE_SHOW_SEVEN_DAY=0 STATUSLINE_SHOW_COST=0 STATUSLINE_SHOW_EMAIL=0 \
    bash -c "'$SCRIPT' < '$BATS_TEST_DIRNAME/fixtures/full.json'"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
```

to:

```bash
@test "all toggles off still exits 0 and prints the (empty) line 1" {
  run env STATUSLINE_SHOW_TITLE=0 STATUSLINE_SHOW_GIT=0 STATUSLINE_SHOW_MODEL=0 \
    STATUSLINE_SHOW_EFFORT=0 STATUSLINE_SHOW_CONTEXT=0 STATUSLINE_SHOW_FIVE_HOUR=0 \
    STATUSLINE_SHOW_SEVEN_DAY=0 STATUSLINE_SHOW_COST=0 STATUSLINE_SHOW_EMAIL=0 \
    STATUSLINE_SHOW_EMOTION=0 \
    bash -c "'$SCRIPT' < '$BATS_TEST_DIRNAME/fixtures/full.json'"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./test/vendor/bats-core/bin/bats test/config.bats`
Expected: the 3 tests asserting *presence* — "on by default", "desperate", "unrecognized" — FAIL, since no `segment_emotion`/`STATUSLINE_SHOW_EMOTION` exists yet and nothing renders. The "toggle off" test asserts *absence*, so it **passes trivially at this point**; it only becomes meaningful once Steps 3–4 land, so don't read its green as the feature already working. The modified "all toggles off" test also still PASSes (it was already passing; the added var is inert right now).

- [ ] **Step 3: Implement — create `segments/25-emotion.sh`**

```bash
# shellcheck shell=bash
# Line 2 (first segment): Claude's inferred emotional state for this
# session, read from the separately-installed emotion-statusline plugin's
# cache file via emotion_state() (lib/emotion.sh). This repo never
# classifies emotion itself — only renders whatever that plugin's Stop hook
# already wrote.

segment_emotion() {
  local emotion
  emotion=$(emotion_state)
  [ -n "$emotion" ] || return

  if [ "$emotion" = "desperate" ]; then
    printf '%sDESPERATE — verify output quality%s' "$BOLD_RED" "$RESET"
    return
  fi

  local color
  case "$emotion" in
    curious)       color="$CYAN" ;;
    focused)       color="$WHITE" ;;
    satisfied)     color="$GREEN" ;;
    cautious)      color="$YELLOW" ;;
    enthusiastic)  color="$MAGENTA" ;;
    contemplative) color="$BRIGHT_BLUE" ;;
    confident)     color="$GREEN" ;;
    uncertain)     color="$YELLOW" ;;
    determined)    color="$WHITE" ;;
    amused)        color="$MAGENTA" ;;
    concerned)     color="$RED" ;;
    relieved)      color="$GREEN" ;;
    calm)          color="$TEAL" ;;
    unknown)       color="$DIM" ;;
    *)             color="" ;;
  esac
  printf '%s%s%s' "$color" "$emotion" "$RESET"
}
register_segment 2 emotion segment_emotion STATUSLINE_SHOW_EMOTION
```

- [ ] **Step 4: Implement — add the config var**

In `lib/config.sh`, add `STATUSLINE_SHOW_EMOTION` to the `STATUSLINE_CONFIG_VARS` list:

```bash
STATUSLINE_CONFIG_VARS="STATUSLINE_BAR_WIDTH STATUSLINE_SEVEN_DAY_BAR_WIDTH
  STATUSLINE_PCT_WARN
  STATUSLINE_PCT_CRIT STATUSLINE_PACE_TOL STATUSLINE_SHOW_TITLE
  STATUSLINE_SHOW_GIT STATUSLINE_SHOW_MODEL STATUSLINE_SHOW_EFFORT
  STATUSLINE_SHOW_CONTEXT STATUSLINE_SHOW_FIVE_HOUR
  STATUSLINE_SHOW_SEVEN_DAY STATUSLINE_SHOW_COST STATUSLINE_SHOW_EMAIL
  STATUSLINE_SHOW_EMOTION
  STATUSLINE_SEGMENTS_DIR STATUSLINE_LINE1_SEGMENTS
  STATUSLINE_LINE2_SEGMENTS STATUSLINE_LINE3_SEGMENTS"
```

And add the default, right after `STATUSLINE_SHOW_COST`'s default:

```bash
  : "${STATUSLINE_SHOW_COST:=1}"
  : "${STATUSLINE_SHOW_EMOTION:=1}"    # line 2: emotion-statusline plugin's cached emotion label
  : "${STATUSLINE_SHOW_EMAIL:=0}"       # 3rd line: logged-in account email
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./test/vendor/bats-core/bin/bats test/config.bats`
Expected: PASS, all tests including the 4 new ones.

- [ ] **Step 6: Run the full suite and confirm no existing golden changed**

Run: `./run-tests.sh`
Expected: PASS, zero shellcheck findings, **no diffs in any existing `test/golden/*.out` file** — every other suite's `CLAUDE_CONFIG_DIR` points at a nonexistent directory, so `emotion_state()` finds no cache file and `segment_emotion()` renders nothing there, even though `STATUSLINE_SHOW_EMOTION` now defaults to `1`. If any existing golden diffs, stop and investigate before proceeding — that would mean the segment is leaking output somewhere it shouldn't.

- [ ] **Step 7: Commit**

```bash
git add segments/25-emotion.sh lib/config.sh test/config.bats
git commit -m "Add emotion segment: render the emotion-statusline plugin's cached label"
```

---

### Task 4: e2e golden coverage for the emotion segment

**Files:**
- Create: `test/fixtures/fake-claude-emotion/cache/claude-emotion.json`
- Create: `test/fixtures/fake-claude-emotion-desperate/cache/claude-emotion.json`
- Modify: `test/e2e.bats`
- Create: `test/golden/emotion.out`
- Create: `test/golden/emotion-desperate.out`

**Interfaces:**
- Consumes: `segment_emotion()`/`STATUSLINE_SHOW_EMOTION` (Task 3), the existing `test/fixtures/full.json` fixture (unchanged — reused exactly as the `email.out` golden test reuses it, only `CLAUDE_CONFIG_DIR` differs per test).
- Produces: nothing consumed by later tasks — this is the final behavioral verification.

This intentionally does **not** add a new `test/fixtures/*.json` file. `test/regen-golden.sh` blanket-regenerates a golden file for every `fixtures/*.json` basename using a nonexistent `CLAUDE_CONFIG_DIR`; a same-named fixture would collide with these hand-generated goldens the next time someone runs an unrelated regeneration. `email.out` avoids this by reusing `full.json` as input with a custom `CLAUDE_CONFIG_DIR` in its own `@test` block instead of `check_golden()`; this task follows that exact precedent.

**Accepted deviation from the spec:** the spec's blast-radius list asks for "a fixture payload carrying `session_id`". Reusing `full.json` (which has no `session_id`) means the *global* cache path is what gets e2e coverage; per-session cache-file selection and the `PAYLOAD_SESSION_ID` thread are covered only by Task 2's unit tests, never end-to-end. That's the deliberate trade for not fighting `regen-golden.sh` — accept it, don't silently "fix" it by adding a fixture.

- [ ] **Step 1: Create the fixture cache directories**

```bash
mkdir -p test/fixtures/fake-claude-emotion/cache
echo '{"emotion":"curious"}' > test/fixtures/fake-claude-emotion/cache/claude-emotion.json

mkdir -p test/fixtures/fake-claude-emotion-desperate/cache
echo '{"emotion":"desperate"}' > test/fixtures/fake-claude-emotion-desperate/cache/claude-emotion.json
```

- [ ] **Step 2: Write the failing tests**

Add to `test/e2e.bats`, after the existing `"logged-in account: 3rd line renders the email..."` test:

```bash
@test "emotion cache present: colored emotion label leads line 2" {
  touch -t "$(date -r "$STATUSLINE_EPOCH" +%Y%m%d%H%M.%S)" \
    "$BATS_TEST_DIRNAME/fixtures/fake-claude-emotion/cache/claude-emotion.json"
  CLAUDE_CONFIG_DIR="$BATS_TEST_DIRNAME/fixtures/fake-claude-emotion" \
    STATUSLINE_NOW="$STATUSLINE_EPOCH" "$SCRIPT" \
    < "$BATS_TEST_DIRNAME/fixtures/full.json" \
    > "$BATS_TEST_TMPDIR/emotion.out"
  diff "$BATS_TEST_DIRNAME/golden/emotion.out" "$BATS_TEST_TMPDIR/emotion.out"
}

@test "emotion cache says desperate: bold red warning leads line 2" {
  touch -t "$(date -r "$STATUSLINE_EPOCH" +%Y%m%d%H%M.%S)" \
    "$BATS_TEST_DIRNAME/fixtures/fake-claude-emotion-desperate/cache/claude-emotion.json"
  CLAUDE_CONFIG_DIR="$BATS_TEST_DIRNAME/fixtures/fake-claude-emotion-desperate" \
    STATUSLINE_NOW="$STATUSLINE_EPOCH" "$SCRIPT" \
    < "$BATS_TEST_DIRNAME/fixtures/full.json" \
    > "$BATS_TEST_TMPDIR/emotion-desperate.out"
  diff "$BATS_TEST_DIRNAME/golden/emotion-desperate.out" "$BATS_TEST_TMPDIR/emotion-desperate.out"
}
```

(The `touch -t` pins each fixture cache file's mtime to `STATUSLINE_EPOCH` so `emotion_state()`'s 600s freshness check is deterministic no matter when the repo was checked out — same technique as Task 3's config.bats tests.)

- [ ] **Step 3: Run the tests to verify they fail**

Run: `./test/vendor/bats-core/bin/bats test/e2e.bats`
Expected: the 2 new tests FAIL — `diff` reports "No such file or directory" for the not-yet-created `test/golden/emotion.out` / `test/golden/emotion-desperate.out`.

- [ ] **Step 4: Generate the golden files**

```bash
touch -t "$(date -r 1750000000 +%Y%m%d%H%M.%S)" \
  test/fixtures/fake-claude-emotion/cache/claude-emotion.json
STATUSLINE_CONFIG=/nonexistent/statusline.conf \
  STATUSLINE_SEGMENTS_DIR=/nonexistent/segments.d \
  CLAUDE_CONFIG_DIR=test/fixtures/fake-claude-emotion \
  STATUSLINE_NOW=1750000000 ./statusline-command.sh \
  < test/fixtures/full.json > test/golden/emotion.out

touch -t "$(date -r 1750000000 +%Y%m%d%H%M.%S)" \
  test/fixtures/fake-claude-emotion-desperate/cache/claude-emotion.json
STATUSLINE_CONFIG=/nonexistent/statusline.conf \
  STATUSLINE_SEGMENTS_DIR=/nonexistent/segments.d \
  CLAUDE_CONFIG_DIR=test/fixtures/fake-claude-emotion-desperate \
  STATUSLINE_NOW=1750000000 ./statusline-command.sh \
  < test/fixtures/full.json > test/golden/emotion-desperate.out
```

`STATUSLINE_CONFIG` and `STATUSLINE_SEGMENTS_DIR` are **not optional here.** `e2e.bats`'s `setup()` exports all three isolation vars at nonexistent paths, and `test/regen-golden.sh` exports `STATUSLINE_CONFIG=/nonexistent/...` for the same reason. Generating these two goldens from a bare shell instead would bake whoever's real `~/.config/claude-statusline.conf` (a custom `STATUSLINE_BAR_WIDTH`, say) or real `segments.d` plugins into the expected output, and Step 5 would then fail with a confusing bar-width or extra-segment diff on a machine that has neither.

Then inspect both files by eye before trusting them:

```bash
cat -v test/golden/emotion.out
cat -v test/golden/emotion-desperate.out
```

Expected: `emotion.out` line 2 starts with `curious` in cyan (`^[[36m`) followed by the usual `Fable 5 | high | ...` content; `emotion-desperate.out` line 2 starts with `DESPERATE — verify output quality` in bold red (`^[[1;31m`).

- [ ] **Step 5: Run the tests to verify they pass**

Run: `./test/vendor/bats-core/bin/bats test/e2e.bats`
Expected: PASS, all tests including the 2 new ones.

- [ ] **Step 6: Run the full suite**

Run: `./run-tests.sh`
Expected: PASS, zero shellcheck findings, no diffs in any *other* existing golden file.

- [ ] **Step 7: Commit**

```bash
git add test/fixtures/fake-claude-emotion test/fixtures/fake-claude-emotion-desperate \
  test/e2e.bats test/golden/emotion.out test/golden/emotion-desperate.out
git commit -m "Add e2e golden coverage for the emotion segment"
```

---

### Task 5: Documentation

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`
- Modify: `STDIN_PAYLOAD.md`
- Modify: `statusline-command.sh`

**Interfaces:**
- Consumes: nothing new — this task only documents Tasks 1-4's finished behavior.
- Produces: nothing consumed by other tasks; this is the last task.

- [ ] **Step 1: Update `statusline-command.sh`'s header comment**

Change:

```bash
# Claude Code statusLine script
# Line 1: project title | git branch (dirty indicator + staged/modified counts)
# Line 2: model name | effort level | context tokens used | 5h + 7d subscription usage | session cost
```

to:

```bash
# Claude Code statusLine script
# Line 1: project title | git branch (dirty indicator + staged/modified counts)
# Line 2: emotion state | model name | effort level | context tokens used | 5h + 7d subscription usage | session cost
```

- [ ] **Step 2: Update `README.md`'s intro example and Line 2 bullet**

Change the example block:

```
status-line | main ✗ +1~2?1
Fable 5 | high | 84k | 2½h ███░░▯░░░░ | 3½d ▄ | $1.23
you@example.com
```

to:

```
status-line | main ✗ +1~2?1
curious | Fable 5 | high | 84k | 2½h ███░░▯░░░░ | 3½d ▄ | $1.23
you@example.com
```

Change the Line 2 bullet:

```
- **Line 2** — model name (colored by family), reasoning effort, context
  tokens used, 5-hour and 7-day subscription usage, session cost.
```

to:

```
- **Line 2** — Claude's inferred emotional state for this session (if the
  separately-installed [emotion-statusline](https://github.com/bencium/bencium-marketplace)
  plugin's cache is present and fresh), model name (colored by family),
  reasoning effort, context tokens used, 5-hour and 7-day subscription
  usage, session cost.
```

Add a paragraph after the existing "5h and 7d use the same pace scale..." paragraph:

```
The emotion label is read from `~/.claude/cache/claude-emotion-<session_id>.json`
(falling back to `~/.claude/cache/claude-emotion.json`), written by the
independently-installed `emotion-statusline` plugin's `Stop` hook — this repo
never classifies emotion itself, only renders a cache file up to 10 minutes
old. `desperate` renders as a bold-red `DESPERATE — verify output quality`
warning instead of the bare word, since Anthropic's emotion-concepts research
ties that state to reward-hacking risk; every other name renders as the bare
word in its own color. No cache file (plugin not installed, or none written
yet) means the segment silently renders nothing.

| Emotion | Color | Emotion | Color |
|---|---|---|---|
| `curious` | cyan | `determined` | white |
| `focused` | white | `amused` | magenta |
| `satisfied` | green | `concerned` | red |
| `cautious` | yellow | `relieved` | green |
| `enthusiastic` | magenta | `desperate` | bold red (warning text) |
| `contemplative` | bright blue | `calm` | teal |
| `confident` | green | `unknown` | dim |
| `uncertain` | yellow | *(anything else)* | uncolored |

A name outside that set — say the upstream plugin adds a 15th state — still
renders, just without a color, rather than disappearing.
```

(The color table is required by the spec's blast-radius list, not optional
prose; it must stay in sync with `segments/25-emotion.sh`'s `case`.)

- [ ] **Step 3: Update `README.md`'s file layout tree**

Change:

```
  git.sh                  # git_segment_text(): line-1 branch/dirty-state rendering
  account.sh              # account_email(): line-3 logged-in account lookup
```

to:

```
  git.sh                  # git_segment_text(): line-1 branch/dirty-state rendering
  account.sh              # account_email(): line-3 logged-in account lookup
  emotion.sh               # emotion_state(): line-2 emotion-statusline plugin cache lookup
```

- [ ] **Step 4: Update `README.md`'s config table**

Add a row right after `STATUSLINE_SHOW_COST`:

```
| `STATUSLINE_SHOW_COST` | `1` | Session cost |
| `STATUSLINE_SHOW_EMOTION` | `1` | Emotion label from the emotion-statusline plugin's cache (line 2) |
| `STATUSLINE_SHOW_EMAIL` | `0` | Logged-in account email (line 3) |
```

Update the `STATUSLINE_LINE2_SEGMENTS` default value:

```
| `STATUSLINE_LINE2_SEGMENTS` | `emotion model effort context five_hour seven_day cost` | Line 2 segment names and order |
```

- [ ] **Step 5: Update `README.md`'s custom-segments `PAYLOAD_*` table**

Add a row:

```
| `PAYLOAD_REPO_NAME` | `.workspace.repo.name` |
| `PAYLOAD_SESSION_ID` | `.session_id` |
```

- [ ] **Step 6: Update `STDIN_PAYLOAD.md`'s used-fields tally**

Task 1 makes `session_id` a field the script actually consumes, so its
"Used by script?" cell and the running count both go stale. Change:

```
- **Script currently uses:** ~11 fields (marked ✅ below)
```

to:

```
- **Script currently uses:** ~12 fields (marked ✅ below)
```

and in the "Top-level fields" table change:

```
| `session_id` | no | Current session UUID |
```

to:

```
| `session_id` | ✅ | Current session UUID — picks the per-session emotion cache file |
```

- [ ] **Step 7: Update `CLAUDE.md`'s architecture description**

In the "Architecture" section's file-layout code block, add `emotion.sh` next to `account.sh`:

```
  git.sh                  # git_segment_text(): line-1 branch/dirty-state text
  account.sh              # account_email(): line-3 logged-in account lookup
  emotion.sh               # emotion_state(): line-2 emotion-statusline plugin cache lookup
```

In the "Line 2" paragraph, change the default-order sentence:

```
**Line 2** (default order: `model effort context five_hour seven_day cost`): model name...
```

to:

```
**Line 2** (default order: `emotion model effort context five_hour seven_day cost`): the emotion-statusline plugin's cached emotion label (see below) → model name...
```

Add a new paragraph after the "Branch, dirty state, ..." paragraph (which ends the Line 1 discussion) and before "**Line 3**":

```
The emotion segment (`segments/25-emotion.sh`, `segment_emotion()`) is the
one line-2 segment that, like the line-3 email segment, ignores the stdin
payload's own fields (beyond `PAYLOAD_SESSION_ID`, used only to pick which
cache file to read) and instead reads external state: `emotion_state()`
(`lib/emotion.sh`) looks up `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cache/claude-emotion-<session_id>.json`,
falling back to `.../cache/claude-emotion.json`, written by the
separately-installed `emotion-statusline` plugin's `Stop` hook (not part of
this repo). A cache file older than 600s (via the same `STATUSLINE_NOW`
injection point as `elapsed_pct_of_window`/`reset_countdown`) is treated as
absent (staleness is `age > 600`, so a file exactly 600s old still renders).
Each of the 14 emotion names maps to one of `lib/colors.sh`'s
existing constants; `desperate` is special-cased to a bold-red
`DESPERATE — verify output quality` warning instead of the bare word,
matching the upstream plugin's behavior (its "Anthropic's research on
emotion concepts" is what motivates this — see the plugin's own README for
detail). An emotion name outside the mapped set still renders in plain,
uncolored text rather than being dropped.
```

- [ ] **Step 8: Run the full suite one last time**

Run: `./run-tests.sh`
Expected: PASS — doc-only changes, but this confirms nothing was accidentally broken while editing adjacent files.

- [ ] **Step 9: Commit**

```bash
git add README.md CLAUDE.md STDIN_PAYLOAD.md statusline-command.sh
git commit -m "Document the emotion segment in README.md and CLAUDE.md"
```
