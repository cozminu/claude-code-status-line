# Quad-Shaded Pace Bar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace `pace_bar()`'s single-cell direction tick (`▮`/`▯`) with a 4-glyph shaded bar (`█`/`▓`/`▒`/`░`) that shows both the direction and the magnitude of the gap between actual usage and the even-spend pace point.

**Architecture:** `pace_bar(pct, elapsed_pct)` in `lib/helpers.sh` computes two boundary counts — `filled` (cells representing `pct`) and `paced` (cells representing `elapsed_pct`, replacing the old single-index `tick` variable) — using the same `count * width / 100` formula for both. Each cell then falls into one of three regions by comparing its index against `min(filled, paced)` and `max(filled, paced)`. No caller changes: `usage_segment()` and `seven_day_segment()` keep calling `pace_bar(pct, elapsed_pct)` and get back the same fixed-width string type as before.

**Tech Stack:** Bash 3.2, bats-core (vendored, `test/vendor/bats-core`), shellcheck.

## Global Constraints

- Must stay bash 3.2 compatible (macOS system bash) — no `mapfile`, no associative arrays, no `${var,,}`.
- `./run-tests.sh` (bats suites + shellcheck) must pass at zero findings after every task.
- Golden e2e files (`test/golden/*.out`) are byte-exact; regenerate only via `test/regen-golden.sh`, only when the change is intentional, and always review the diff before committing.
- No new config knobs — shading is not user-configurable (matches spec: `docs/superpowers/specs/2026-07-22-triple-shaded-pace-bar-design.md`).

---

### Task 1: Rewrite `pace_bar()` and its direct test coverage

**Files:**
- Modify: `lib/helpers.sh:66-90` (docstring comment + `pace_bar()` body)
- Modify: `test/unit.bats:85-97` (`pace_bar` tests), `test/unit.bats:159,165,171,189` (`usage_segment`/`seven_day_segment` assertions that embed `pace_bar` output)
- Modify: `test/config.bats:39-51` (bar-width tunable tests that embed `pace_bar` output)

**Interfaces:**
- Consumes: `STATUSLINE_BAR_WIDTH` (global, already set by `load_config`), `STATUSLINE_PACE_TOL` (unchanged, unused directly by `pace_bar`).
- Produces: `pace_bar(pct, elapsed_pct)` → a `STATUSLINE_BAR_WIDTH`-length string of `█`/`▓`/`▒`/`░`. Same signature and same string-length contract as before; `usage_segment()` and `seven_day_segment()` (both already in `lib/helpers.sh`, both unmodified by this task) keep working unchanged.

- [ ] **Step 1: Update `pace_bar` unit tests to the new expected output (still failing against old code)**

Replace `test/unit.bats:85-97`:

```bash
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
```

with:

```bash
@test "pace_bar: lighter gap shade when pace is ahead of usage (behind pace)" {
  [ "$(pace_bar 30 50)" = "███▒▒░░░░░" ]
}

@test "pace_bar: denser gap shade when usage has run past pace (overspend)" {
  [ "$(pace_bar 60 50)" = "█████▓░░░░" ]
}

@test "pace_bar: no gap when exactly on pace" {
  [ "$(pace_bar 50 50)" = "█████░░░░░" ]
}

@test "pace_bar: clamps at both extremes" {
  [ "$(pace_bar 100 100)" = "██████████" ]
  [ "$(pace_bar 10 0)" = "▓░░░░░░░░░" ]
  [ "$(pace_bar 0 100)" = "▒▒▒▒▒▒▒▒▒▒" ]
}
```

- [ ] **Step 2: Update the `usage_segment`/`seven_day_segment` assertions that embed the old tick glyphs**

In `test/unit.bats`, apply these four exact replacements (only the bar portion changes; labels and colors are untouched):

Line 159:
```bash
  [ "$(usage_segment 5h 30 1750009000 18000)" = "${DIM}5h${RESET} ${GREEN}███░░▯░░░░${RESET}" ]
```
→
```bash
  [ "$(usage_segment 5h 30 1750009000 18000)" = "${DIM}5h${RESET} ${GREEN}███▒▒░░░░░${RESET}" ]
```

Line 165:
```bash
  [ "$(usage_segment 5h 50 1750009000 18000)" = "${DIM}5h${RESET} ${YELLOW}█████▮░░░░${RESET}" ]
```
→
```bash
  [ "$(usage_segment 5h 50 1750009000 18000)" = "${DIM}5h${RESET} ${YELLOW}█████░░░░░${RESET}" ]
```

Line 171:
```bash
  [ "$(usage_segment 5h 60 1750009000 18000)" = "${DIM}5h${RESET} ${RED}█████▮░░░░${RESET}" ]
```
→
```bash
  [ "$(usage_segment 5h 60 1750009000 18000)" = "${DIM}5h${RESET} ${RED}█████▓░░░░${RESET}" ]
```

Line 189:
```bash
  [ "$(seven_day_segment 7d 60 1750302400 604800)" = "${DIM}7d${RESET} ${ORANGE}█████▮░░░░${RESET}" ]
```
→
```bash
  [ "$(seven_day_segment 7d 60 1750302400 604800)" = "${DIM}7d${RESET} ${ORANGE}█████▓░░░░${RESET}" ]
```

- [ ] **Step 3: Update the bar-width tunable assertions in `test/config.bats`**

Replace `test/config.bats:39-45`:

```bash
@test "config file overrides default: bar width" {
  echo 'STATUSLINE_BAR_WIDTH=4' > "$STATUSLINE_CONFIG"
  run bash -c "'$SCRIPT' < '$BATS_TEST_DIRNAME/fixtures/full.json' | sed \$'s/\033\\[[0-9;]*m//g'"
  # 5h: 30% of 4 cells -> 1 filled, tick at cell 2 (elapsed 50%), hollow (behind)
  # label is a live countdown: full.json's five_hour reset is 2.5h out -> "3h"
  [[ "${lines[1]}" == *"3h █░▯░"* ]]
}
```

with:

```bash
@test "config file overrides default: bar width" {
  echo 'STATUSLINE_BAR_WIDTH=4' > "$STATUSLINE_CONFIG"
  run bash -c "'$SCRIPT' < '$BATS_TEST_DIRNAME/fixtures/full.json' | sed \$'s/\033\\[[0-9;]*m//g'"
  # 5h: 30% of 4 cells -> 1 filled, 1 light gap cell (paced=2, behind pace)
  # label is a live countdown: full.json's five_hour reset is 2.5h out -> "3h"
  [[ "${lines[1]}" == *"3h █▒░░"* ]]
}
```

Replace `test/config.bats:47-52`:

```bash
@test "environment overrides config file" {
  echo 'STATUSLINE_BAR_WIDTH=4' > "$STATUSLINE_CONFIG"
  run bash -c "STATUSLINE_BAR_WIDTH=6 '$SCRIPT' < '$BATS_TEST_DIRNAME/fixtures/full.json' | sed \$'s/\033\\[[0-9;]*m//g'"
  # 30% of 6 cells -> 1 filled, tick at cell 3, hollow
  [[ "${lines[1]}" == *"3h █░░▯░░"* ]]
}
```

with:

```bash
@test "environment overrides config file" {
  echo 'STATUSLINE_BAR_WIDTH=4' > "$STATUSLINE_CONFIG"
  run bash -c "STATUSLINE_BAR_WIDTH=6 '$SCRIPT' < '$BATS_TEST_DIRNAME/fixtures/full.json' | sed \$'s/\033\\[[0-9;]*m//g'"
  # 30% of 6 cells -> 1 filled, 2 light gap cells (paced=3, behind pace)
  [[ "${lines[1]}" == *"3h █▒▒░░░"* ]]
}
```

- [ ] **Step 4: Run the affected tests to confirm they fail against the current implementation**

Run: `./test/vendor/bats-core/bin/bats test/unit.bats test/config.bats`
Expected: FAILs on the tests just edited (old `pace_bar` still emits `▮`/`▯`), everything else still passing.

- [ ] **Step 5: Rewrite `pace_bar()` in `lib/helpers.sh`**

Replace the docstring comment and function body at `lib/helpers.sh:66-90`:

```bash
# Usage bar with a pace tick marking where usage "should" be if evenly spent
# across the elapsed portion of the window. The tick overrides whatever glyph
# (filled/empty) would otherwise occupy that slot, and its shape encodes pace:
# solid ▮ when usage is at or ahead of pace, hollow ▯ when usage is behind it.
pace_bar() {
  local pct="$1" elapsed_pct="$2" width="$STATUSLINE_BAR_WIDTH"
  local filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled="$width"
  local tick=$(( elapsed_pct * width / 100 ))
  [ "$tick" -ge "$width" ] && tick=$(( width - 1 ))
  [ "$tick" -lt 0 ] && tick=0
  local tick_glyph="▯"
  [ "$pct" -ge "$elapsed_pct" ] && tick_glyph="▮"
  local out="" i
  for (( i = 0; i < width; i++ )); do
    if [ "$i" -eq "$tick" ]; then
      out+="$tick_glyph"
    elif [ "$i" -lt "$filled" ]; then
      out+="█"
    else
      out+="░"
    fi
  done
  printf "%s" "$out"
}
```

with:

```bash
# Usage bar shaded across up to three regions instead of a flat fill: solid █
# for cells used within pace, a gap shade for the delta between actual usage
# and the pace point (▓ denser when usage has run past pace - overspend - ▒
# lighter when pace is ahead of usage - unused slack), and ░ for cells beyond
# both. Zero-width gap (pct == elapsed_pct) renders as plain solid-then-empty.
pace_bar() {
  local pct="$1" elapsed_pct="$2" width="$STATUSLINE_BAR_WIDTH"
  local filled=$(( pct * width / 100 ))
  [ "$filled" -gt "$width" ] && filled="$width"
  [ "$filled" -lt 0 ] && filled=0
  local paced=$(( elapsed_pct * width / 100 ))
  [ "$paced" -gt "$width" ] && paced="$width"
  [ "$paced" -lt 0 ] && paced=0
  local lo="$filled" hi="$paced"
  [ "$paced" -lt "$filled" ] && lo="$paced" && hi="$filled"
  local gap_glyph="▒"
  [ "$filled" -gt "$paced" ] && gap_glyph="▓"
  local out="" i
  for (( i = 0; i < width; i++ )); do
    if [ "$i" -lt "$lo" ]; then
      out+="█"
    elif [ "$i" -lt "$hi" ]; then
      out+="$gap_glyph"
    else
      out+="░"
    fi
  done
  printf "%s" "$out"
}
```

- [ ] **Step 6: Run the affected tests again to confirm they now pass**

Run: `./test/vendor/bats-core/bin/bats test/unit.bats test/config.bats`
Expected: PASS, all tests.

- [ ] **Step 7: Run the full suite (other e2e goldens are expected to fail here — that's Task 3's job)**

Run: `./run-tests.sh`
Expected: `test/unit.bats` and `test/config.bats` all PASS; `test/e2e.bats` and `test/git.bats`/`test/segments.bats` unaffected files pass; any `test/e2e.bats` cases against `five-hour-ahead.out`, `email.out`, or `full.out` FAIL (expected — those goldens still have the old `▮`/`▯` output and get regenerated in Task 3). shellcheck: zero findings (no new shellcheck issues from this rewrite).

- [ ] **Step 8: Commit**

```bash
git add lib/helpers.sh test/unit.bats test/config.bats
git commit -m "Shade pace_bar with 4 glyphs instead of a single direction tick"
```

---

### Task 2: Update `CLAUDE.md` documentation

**Files:**
- Modify: `CLAUDE.md:63`, `CLAUDE.md:67`, `CLAUDE.md:69`

**Interfaces:**
- Consumes: nothing (documentation only).
- Produces: nothing consumed by later tasks; this is a leaf/doc-only change.

- [ ] **Step 1: Update the "Two bar renderers" description**

In `CLAUDE.md`, replace line 63:

```
- `pace_bar(pct, elapsed_pct)` — same bar, but overlays a pace tick at the position usage "should" be if spent evenly across the elapsed portion of the rate-limit window. The tick's shape encodes pace: solid `▮` when usage is at or ahead of pace (`pct >= elapsed_pct`), hollow `▯` when behind. Bar color is chosen by the caller (`usage_segment`/`seven_day_segment`), not by `pace_bar` itself.
```

with:

```
- `pace_bar(pct, elapsed_pct)` — same bar, but shades up to three regions instead of a flat fill: solid `█` for cells used within pace, a gap shade for the delta between actual usage and the pace point (`▓` denser when usage has run past pace — overspend — `▒` lighter when pace is ahead of usage — unused slack), and `░` for cells beyond both. Bar color is chosen by the caller (`usage_segment`/`seven_day_segment`), not by `pace_bar` itself.
```

- [ ] **Step 2: Update the 5h segment paragraph's tick reference**

In `CLAUDE.md:67`, replace:

```
The reset timestamp positions the pace tick and (via `reset_countdown`, computed in the segment wrapper before calling `usage_segment`) drives the label.
```

with:

```
The reset timestamp positions the pace boundary within the bar and (via `reset_countdown`, computed in the segment wrapper before calling `usage_segment`) drives the label.
```

- [ ] **Step 3: Update the 7d segment paragraph's tick reference**

In `CLAUDE.md:69`, replace the trailing parenthetical:

```
(Because 7d only expands when over pace, its `pace_bar` tick is always the solid `▮` form.)
```

with:

```
(Because 7d only expands when over pace, its `pace_bar` gap region is always the denser overspend shade `▓`.)
```

- [ ] **Step 4: Commit**

```bash
git add CLAUDE.md
git commit -m "Update pace_bar docs for the 4-glyph shading scheme"
```

---

### Task 3: Regenerate affected goldens and do a full-suite verification pass

**Files:**
- Modify (generated): `test/golden/five-hour-ahead.out`, `test/golden/email.out`, `test/golden/full.out`

**Interfaces:**
- Consumes: `pace_bar()` from Task 1 (via the full `statusline-command.sh` render pipeline).
- Produces: nothing consumed by later tasks — this is the final verification task.

- [ ] **Step 1: Confirm which goldens currently contain the old tick glyphs**

Run: `grep -l '▮\|▯' test/golden/*.out`
Expected output: exactly `test/golden/five-hour-ahead.out`, `test/golden/email.out`, `test/golden/full.out` (these are the only fixtures that render a 5h bar with a reset present, or a 7d bar expanded over pace).

- [ ] **Step 2: Regenerate goldens**

Run: `./test/regen-golden.sh`
Expected: prints `regenerated golden/<name>.out` once per fixture in `test/fixtures/`.

- [ ] **Step 3: Review the diff — confirm only the three expected files changed, and only in the bar glyphs**

Run: `git diff --stat test/golden/`
Expected: exactly `five-hour-ahead.out`, `email.out`, `full.out` listed as changed; no other golden file touched.

Run: `git diff test/golden/five-hour-ahead.out test/golden/email.out test/golden/full.out`
Expected: only `▮`/`▯` characters replaced by `█`/`▓`/`▒`/`░` sequences (bar shape changes consistent with Task 1's `pace_bar` rewrite); no label, color escape, or unrelated text changes.

- [ ] **Step 4: Run the full test suite**

Run: `./run-tests.sh`
Expected: all bats suites pass (0 failures), shellcheck reports zero findings on both `shellcheck -x statusline-command.sh` and `shellcheck segments/*.sh`.

- [ ] **Step 5: Commit**

```bash
git add test/golden/five-hour-ahead.out test/golden/email.out test/golden/full.out
git commit -m "Regenerate goldens for the 4-glyph pace_bar shading"
```
