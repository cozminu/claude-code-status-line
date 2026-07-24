# Quarter-glyph countdown labels + wider 7d expanded bar

## Problem

Two related readability gaps in the 5h/7d rate-limit segments:

1. `reset_countdown()` (`lib/helpers.sh`) ceils remaining time to the next
   *whole* unit (`3h`, `4d`) and collapses anything under one whole unit to
   `<1`. That's coarse — a countdown showing `4d` could mean anywhere from
   just over 3 days to exactly 4 days remaining, and `<1` is a dead zone for
   most of the 5h window's last hour.
2. The 7d segment's expanded `pace_bar` shares `STATUSLINE_BAR_WIDTH` (10
   cells) with the 5h bar. Ten cells doesn't map cleanly onto a 7-day window;
   14 cells (one per half-day) would let each glyph position mean something
   concrete.

## Design

### 1. Quarter-unit countdown labels

`reset_countdown(reset, unit_seconds)` changes from ceiling-to-whole-unit to
ceiling-to-whole-*quarter*-unit, formatted as a mixed number using Unicode
fraction glyphs (`¼ ½ ¾`):

- Compute `quarter_seconds = unit_seconds / 4` (900 for hours, 21600 for
  days — both exact, no remainder).
- `quarters = ceil(remaining / quarter_seconds)`, same ceiling-clamped-to-0
  approach as today's `units` calculation.
- `whole = quarters / 4`, `frac = quarters % 4`.
- Render (checked in this order):
  - `quarters == 0` (remaining is exactly 0 — reset already passed or is
    now) → `"<1"`, unchanged. This is now a rarer case: any remaining time
    above zero rounds up to at least `¼`, so `<1` only fires at exactly 0.
  - `frac == 0` (and `quarters > 0`) → `"%d" % whole` (unchanged from
    today, e.g. `"3"`, `"1"`)
  - `frac != 0 && whole == 0` → just the glyph: `"¼"`, `"½"`, or `"¾"`
  - `frac != 0 && whole > 0` → `"%d%s" % (whole, glyph)`, e.g. `"2¾"`,
    `"1½"`

The unit suffix (`h`/`d`) is still appended by the segment wrappers
(`segments/60-five-hour.sh`, `segments/70-seven-day.sh`), unchanged — only
`reset_countdown`'s internals and output format change. Both 5h and 7d
labels get quarter precision automatically since they share this function.

Rounding direction stays ceiling (never round down), preserving today's
"never underestimate time remaining" property, just at finer granularity.

### 2. Independent 7d expanded-bar width

New config var `STATUSLINE_SEVEN_DAY_BAR_WIDTH`, default `14` (one cell per
half-day across the 7-day window). `STATUSLINE_BAR_WIDTH` (default `10`,
unchanged) now governs the 5h bar exclusively.

`bar()` and `pace_bar()` (`lib/helpers.sh`) currently read
`$STATUSLINE_BAR_WIDTH` directly from the global, the one place they weren't
following the file's stated "explicit arguments in, text out" convention.
Both gain an explicit `width` parameter instead:

- `bar(pct, width)`
- `pace_bar(pct, elapsed_pct, width)`

Callers pass their own width:

- `usage_segment()` (5h): `bar "$pct_int" "$STATUSLINE_BAR_WIDTH"` /
  `pace_bar "$pct_int" "$elapsed_pct" "$STATUSLINE_BAR_WIDTH"`
- `seven_day_segment()` (7d, expanded case only):
  `pace_bar "$pct_int" "$elapsed_pct" "$STATUSLINE_SEVEN_DAY_BAR_WIDTH"`

`gauge_glyph()` (7d compact single-cell marker) is untouched — always one
cell regardless of either width var.

## Out of scope

- No change to the fill/tick glyph vocabulary inside the bars themselves
  (`█ ░ ▮ ▯`) — a similar shaded-bar idea (`▓ ▒`) was tried and reverted in
  the two commits immediately before this one; this design only touches the
  countdown *label* text and the 7d bar's *width*.
- No change to `gauge_glyph()`'s 8-level height ramp or its trigger
  condition for when the 7d segment expands.
- No change to `elapsed_pct_of_window()` or `pace_color()`.

## Blast radius / follow-up work

- `lib/helpers.sh`: rewrite `reset_countdown()` body + docstring; add
  `width` param to `bar()` and `pace_bar()` + docstrings; update
  `usage_segment()`/`seven_day_segment()` call sites.
- `lib/config.sh`: add `STATUSLINE_SEVEN_DAY_BAR_WIDTH` default `14`, add to
  `STATUSLINE_CONFIG_VARS`.
- `test/unit.bats`: update existing `reset_countdown`/`bar`/`pace_bar`
  assertions for the new output format and signatures (e.g. "2.5h away"
  today expects `"3"`, becomes `"2½"` since 2.5h is an exact quarter-unit
  multiple); add cases covering `¼`/`½`/`¾` glyphs and both bar widths.
- `test/config.bats`: add a toggle test proving
  `STATUSLINE_SEVEN_DAY_BAR_WIDTH` changes the rendered 7d bar width.
- `test/golden/*.out`: any fixture with a 7d bar expanded over pace, or a
  reset time that isn't an exact whole-unit boundary, changes byte-for-byte.
  Regenerate via `test/regen-golden.sh` and review the diff per the
  project's golden-update policy (regenerate only for intentional changes).
- `README.md`: update the example status line, clarify
  `STATUSLINE_BAR_WIDTH`'s row is 5h-only, add a
  `STATUSLINE_SEVEN_DAY_BAR_WIDTH` row, and update the pace-tick prose
  paragraph if it references the old countdown format.
- `CLAUDE.md`: update the "Two bar renderers" paragraph (explicit width
  params) and the 7d-segment paragraph (mention
  `STATUSLINE_SEVEN_DAY_BAR_WIDTH`); note the quarter-glyph countdown format
  wherever `reset_countdown` is described.
