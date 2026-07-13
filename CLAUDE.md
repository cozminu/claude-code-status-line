# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A single bash script, `statusline-command.sh`, that Claude Code invokes as its `statusLine` command. Claude Code pipes a JSON payload (model info, git workspace info, context-window usage, rate-limit usage, session cost) to the script's stdin on every render, and the script prints an up-to-3-line colored status line to stdout. `README.md` covers install and the user-facing configuration reference; `STDIN_PAYLOAD.md` documents the full input payload.

Claude Code is configured to run the script from `~/statusline-command.sh`. That path is a symlink to `statusline-command.sh` in this repo — edit the file here, not the symlink target directly.

The script must stay **bash 3.2 compatible** (macOS system bash): no `mapfile`, no associative arrays, no `${var,,}`; empty-array expansion under `set -u` needs the `${arr[@]+"${arr[@]}"}` idiom already used in `main`.

## Testing changes

Run `./run-tests.sh` after every change — it runs the vendored bats suites (`test/*.bats`, nothing to install) plus shellcheck when available. The e2e suite compares fixture payloads (`test/fixtures/*.json`) against `test/golden/*.out` **byte-for-byte** with the clock pinned via `STATUSLINE_NOW=1750000000`; a golden failure means output behavior changed. If the change is intentional, regenerate with `test/regen-golden.sh` and review the golden diff; never regenerate to silence an accidental regression. Keep `shellcheck statusline-command.sh` at zero findings.

For one-off manual checks, pipe a synthetic payload:

```bash
echo '{"model":{"display_name":"Sonnet 5"},"workspace":{"current_dir":"'"$PWD"'"},"cost":{"total_cost_usd":1.23}}' | ./statusline-command.sh
```

New behavior needs a test in the matching suite: pure helpers → `test/unit.bats` (the script is `source`d, helpers called directly), full renders → a fixture + golden in `test/e2e.bats`, config handling → `test/config.bats`, git segment → `test/git.bats` (builds throwaway repos). Tests set `STATUSLINE_CONFIG` to a nonexistent path so a real user config can't leak in, and `CLAUDE_CONFIG_DIR` to a nonexistent path so a real logged-in account email can't leak in either — new suites must do both.

## Architecture

Layout: color constants → `load_config` → pure helpers → segment builders (`usage_segment`, `seven_day_segment`) → `main`, with execution source-guarded at the bottom of the file (`main` runs only when the script is executed; sourcing just defines functions, which is how unit tests reach them). `set -u -o pipefail` is applied only in the executed path, deliberately without `-e`: any field missing from the input JSON silently drops that segment via `[ -n ... ]` guards rather than breaking the render. New segments should follow this same guarded-append pattern.

`main` parses all payload fields in a **single jq pass** (one field per line, `// ""` for absent ones, consumed by ordered `read`s) — the status line renders on every prompt, so process count is the latency budget. Add new fields to that one filter, keeping the filter lines and the `read` block in the same order.

Configuration is resolved by `load_config` with precedence environment > optional config file (`${XDG_CONFIG_HOME:-~/.config}/claude-statusline.conf`, path overridable via `STATUSLINE_CONFIG`) > built-in defaults. Tunables: `STATUSLINE_BAR_WIDTH`, `STATUSLINE_PCT_WARN`/`STATUSLINE_PCT_CRIT` (usage-severity color thresholds), `STATUSLINE_PACE_TOL`; every segment has a `STATUSLINE_SHOW_*` toggle. Defaults must reproduce the golden output exactly — a new knob's default is the previous hard-coded value. Register any new variable in `STATUSLINE_CONFIG_VARS` (the list `load_config` snapshots so env wins over the file) and document it in README.md.

The script builds three `segments`/`line2`/`line3` bash arrays and joins each with `" | "` (via `join_line`), printing line 1, then line 2, then line 3. A line whose array is empty prints nothing (so line 3 can be absent without leaving a blank line, and line 3 shifts up to print as line 2 if line 2 is itself empty); the script ends with `exit 0` so an empty trailing line doesn't leak a non-zero status.

**Line 1** (left to right): project title (repo name, falling back to directory basename) → git branch with dirty/clean indicator, plus staged/modified/untracked file counts (`+N`/`~N`/`?N`) when dirty.

**Line 2**: model name (colored by family — opus/sonnet/haiku/fable) → reasoning effort level (colored low→max on a green→yellow→teal→red→magenta scale) → context-window usage tokens → 5-hour subscription rate-limit usage bar → 7-day usage marker (a compact single-cell pace gauge that expands into a full bar only when weekly usage is over pace) → session cost. The rate-limit segments are bracket-free; their labels are a live reset countdown (`3h`, `4d`, ...) rather than a fixed period name — see `reset_countdown` below.

Two bar renderers:
- `bar(pct)` — plain filled/empty progress bar (█/░), `STATUSLINE_BAR_WIDTH` cells.
- `pace_bar(pct, elapsed_pct)` — same bar, but overlays a pace tick at the position usage "should" be if spent evenly across the elapsed portion of the rate-limit window. The tick's shape encodes pace: solid `▮` when usage is at or ahead of pace (`pct >= elapsed_pct`), hollow `▯` when behind. Bar color is always driven by usage percentage (severity scale), never by pace.

`elapsed_pct_of_window(reset, window_seconds)` computes how much of a rate-limit window has elapsed (clamped 0–100); the clock is injectable via `STATUSLINE_NOW`, which is what makes the pace goldens deterministic. `reset_countdown(reset, unit_seconds)` is the other clock-reading helper (same `STATUSLINE_NOW` injection): it ceils the time remaining until reset into whole units (3600 for hours, 86400 for days), printing `<1` once less than a whole unit remains — this is what turns `5h`/`7d` into live countdown labels in `main`. When a window's reset timestamp is absent from the payload, `main` falls back to the static `5h`/`7d` label.

The 5h window renders through `usage_segment(label, pct, reset, window_seconds)` — dim label, bar colored by usage severity (`pct_color`: green < `STATUSLINE_PCT_WARN`, yellow < `STATUSLINE_PCT_CRIT`, red above), `pace_bar` when a reset time is present, plain `bar` otherwise. The reset timestamp positions the pace tick and (via `reset_countdown`, computed in `main` before calling `usage_segment`) drives the label.

The 7d window has its own `seven_day_segment(label, pct, reset, window_seconds)` helper because it renders two ways. By default it's a **compact single-cell pace marker** — one partial-block glyph (`▁▂▃▄▅▆▇█`, via `gauge_glyph`, mapping usage % to 8 levels) whose height encodes usage. It **expands into a full `pace_bar`** only when weekly usage runs genuinely over pace — when `used_percentage − elapsed_pace > STATUSLINE_PACE_TOL`, the same band where `pace_color` turns orange, so expansion and the orange color trigger together. The entire 7d element is colored on the pace scale throughout via `pace_color`: green below the even-spend pace, yellow on pace (within ±`STATUSLINE_PACE_TOL` points), orange over — so the expanded bar is always orange. When no reset time is present pace is unknowable, so it stays a compact marker colored by `pct_color` usage severity and never expands. 7d is the only place using the pace-based color scale and `$ORANGE`; the 5h bar stays on the usage-severity scale. (Because 7d only expands when over pace, its `pace_bar` tick is always the solid `▮` form.)

Branch, dirty state, and staged/modified/untracked counts are all derived from a single `git -C "$cwd" --no-optional-locks status --porcelain=v2 --branch` call, parsed once. The whole segment is skipped when that call returns empty (not inside a git repo) — there's no error path, checks just fail closed via `[ -n ... ]` guards.

**Line 3** (optional, on by default via `STATUSLINE_SHOW_EMAIL`): the logged-in Claude account's email. This is the one segment that ignores the stdin payload entirely — `STDIN_PAYLOAD.md` documents no account/user field — and instead reads `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.claude.json` → `.oauthAccount.emailAddress` via `account_email()`, which fails closed to `""` (missing dir/file/field, malformed JSON) exactly like the other guarded segments. It only renders when `using_default_claude_profile()` is false, i.e. `CLAUDE_CONFIG_DIR` is explicitly set to something other than `$HOME/.claude` — the point is to flag when you're on a non-default profile, so it stays silent on the common case. Both checks gate independently in `main` (`STATUSLINE_SHOW_EMAIL=1 AND non-default profile`).
