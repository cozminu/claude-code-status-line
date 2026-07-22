# Triple(quad)-shaded pace bar

## Problem

`pace_bar()` (`lib/helpers.sh`) currently renders a usage bar of `█`/`░` cells
with a single overridden cell — the "tick" — marking where usage *should* be
if spent evenly across the elapsed portion of the rate-limit window. The
tick's shape encodes direction (`▮` solid = at/ahead of pace, `▯` hollow =
behind pace), but it's a single character regardless of how far off pace
usage actually is. There's no visual read on the *magnitude* of the gap
between actual usage and the pace point — only its direction, and only at
one fixed position.

## Design

Replace the single-tick overlay with 4-level shading across the whole bar,
using the classic Unicode block shade ramp (`░ ▒ ▓ █`), where shade
intensity tracks how much a cell matters:

Boundaries are computed the same way as today:
- `filled = pct * width / 100` (cells representing actual usage)
- `paced = elapsed_pct * width / 100` (cells representing the even-spend pace
  point) — this replaces the old single-index `tick` variable; it's now a
  count/boundary, using the same formula `filled` already uses for `pct`.

Each cell `i` in `[0, width)` renders as:

- `i < min(filled, paced)` → `█` — used, and within pace
- `min(filled, paced) <= i < max(filled, paced)` → the **gap** region:
  - `▓` (denser) when `filled > paced` — usage has run *past* the pace
    point (overspend, the "worse" direction, denser/more alarming shade)
  - `▒` (lighter) when `paced > filled` — pace has run ahead of usage
    (unused slack/budget still available, lighter/calmer shade)
- `i >= max(filled, paced)` → `░` — genuinely untouched, no expectation yet

When `pct == elapsed_pct` the gap has zero width, so the bar is just
solid-then-empty — same visual as being exactly on pace today.

The `▮`/`▯` tick glyphs and the old single-index tick-override branch are
removed entirely. Bar color continues to be chosen by the caller via
`pace_color` (green under pace / yellow near / red-or-above-color over
pace) exactly as today — the new `▓`/`▒` split is a second, reinforcing
signal, not a replacement for the color-based direction read.

### Callers unaffected

`usage_segment()` and `seven_day_segment()` (`lib/helpers.sh`) call
`pace_bar(pct, elapsed_pct)` with the same signature and get back a
`STATUSLINE_BAR_WIDTH`-length string, same as today. No caller-side changes
needed — the 4-shade rendering applies automatically wherever `pace_bar` is
used: the 5h segment (always, when a reset is present) and the 7d segment
(only when it expands past pace, per its existing expand condition).

## Out of scope

- No change to `bar()` (the plain, non-pace bar used when no reset time is
  available) — it stays `█`/`░` only, since there's no pace point to shade
  against.
- No change to `gauge_glyph()` (the 7d compact single-cell marker) — it's a
  separate glyph family (height-based `▁`–`█` ramp) and unaffected unless
  the 7d segment expands into `pace_bar`.
- No new config knobs — shading is not user-configurable, matching how the
  existing tick shape wasn't either.

## Blast radius / follow-up work

- `lib/helpers.sh`: rewrite `pace_bar()` body and its docstring comment.
- `CLAUDE.md`: the "Two bar renderers" paragraph and the 7d-segment
  paragraph both describe the `▮`/`▯` tick scheme by name — update both to
  describe the 4-glyph scheme instead.
- `test/unit.bats`: any `pace_bar` assertions with literal `▮`/`▯` in
  expected output need updating to the new shading.
- `test/golden/*.out`: any fixture that renders a 5h bar with a reset
  present, or a 7d bar expanded over pace, will change byte-for-byte.
  Regenerate via `test/regen-golden.sh` and review the diff per the
  project's golden-update policy (regenerate only for intentional changes,
  never to silence a regression).
