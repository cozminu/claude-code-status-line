# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A bash renderer, entrypoint `statusline-command.sh`, that Claude Code invokes as its `statusLine` command. Claude Code pipes a JSON payload (model info, git workspace info, context-window usage, rate-limit usage, session cost) to the script's stdin on every render, and it prints an up-to-3-line colored status line to stdout. `README.md` covers install and the user-facing configuration reference; `STDIN_PAYLOAD.md` documents the full input payload.

Claude Code's `settings.json` points `statusLine.command` directly at the cloned repo's `statusline-command.sh` — no symlink. The entrypoint resolves its own directory via `${BASH_SOURCE[0]}`, so the repo can live anywhere as long as `settings.json` is updated if it moves.

The whole thing must stay **bash 3.2 compatible** (macOS system bash): no `mapfile`, no associative arrays, no `${var,,}`; empty-array expansion under `set -u` needs the `${arr[@]+"${arr[@]}"}` idiom used in `main`. The segment registry (below) relies on single-level `${!name}` indirection instead of associative arrays or namerefs — both are bash-4+-only.

## Testing changes

Run `./run-tests.sh` after every change — it runs the vendored bats suites (`test/*.bats`, nothing to install) plus shellcheck when available. The e2e suite compares fixture payloads (`test/fixtures/*.json`) against `test/golden/*.out` **byte-for-byte** with the clock pinned via `STATUSLINE_NOW=1750000000`; a golden failure means output behavior changed. If the change is intentional, regenerate with `test/regen-golden.sh` and review the golden diff; never regenerate to silence an accidental regression. Lint runs as `shellcheck -x statusline-command.sh` (follows the `# shellcheck source=lib/*.sh` directives, merging the entrypoint with `lib/*.sh` into one analysis unit) plus `shellcheck segments/*.sh` separately (the entrypoint sources `segments/*.sh` via a runtime glob, which `-x` can't follow) — keep both at zero findings.

For one-off manual checks, pipe a synthetic payload:

```bash
echo '{"model":{"display_name":"Sonnet 5"},"workspace":{"current_dir":"'"$PWD"'"},"cost":{"total_cost_usd":1.23}}' | ./statusline-command.sh
```

New behavior needs a test in the matching suite: pure helpers → `test/unit.bats` (the script is `source`d, helpers called directly), full renders → a fixture + golden in `test/e2e.bats`, config handling → `test/config.bats`, git segment → `test/git.bats` (builds throwaway repos), segment registry/ordering/plugins → `test/segments.bats`. Tests set `STATUSLINE_CONFIG` to a nonexistent path so a real user config can't leak in, `CLAUDE_CONFIG_DIR` to a nonexistent path so a real logged-in account email can't leak in, and `STATUSLINE_SEGMENTS_DIR` to a nonexistent path so a real `segments.d` plugin directory can't leak in either — new suites must do all three.

## Adding a built-in segment

Create `segments/NN-name.sh` (the numeric prefix documents default order — pick a gap between existing files, or append), define a zero-argument `segment_name()` that reads `PAYLOAD_*`/`STATUSLINE_*` globals and prints the rendered text (or nothing to omit itself), and call `register_segment <line> <name> segment_name [show-var]` at the file's top level. Add any new pure formatting logic to `lib/helpers.sh` with unit coverage in `test/unit.bats`; add an e2e fixture+golden if it changes default output; add a `test/config.bats` toggle test if it has a `STATUSLINE_SHOW_*` var.

## Architecture

**File layout**:

```
statusline-command.sh   # thin entrypoint
lib/
  colors.sh              # color constants
  config.sh              # STATUSLINE_CONFIG_VARS + load_config()
  registry.sh             # register_segment() / render_line()
  helpers.sh              # pure formatting helpers + segment builders (usage_segment, seven_day_segment, ...)
  payload.sh              # parse_payload(): one jq pass over stdin -> PAYLOAD_* globals
  git.sh                  # git_segment_text(): line-1 branch/dirty-state text
  account.sh              # account_email(): line-3 logged-in account lookup
  main.sh                 # main(): orchestration only
segments/                 # one file per built-in segment (10-title.sh ... 90-email.sh)
```

The entrypoint resolves its own directory (`DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"`), sources `lib/colors.sh` → `config.sh` → `registry.sh` → `helpers.sh` → `payload.sh` → `git.sh` → `account.sh` → every `segments/*.sh` (glob, built-in and trusted, so safe to source unconditionally) → `lib/main.sh`, all unconditionally — this is why `test/unit.bats`'s plain `source statusline-command.sh` still defines every function without running anything. Only the final `main` call is source-guarded (`if [ "${BASH_SOURCE[0]}" = "$0" ]; then set -u -o pipefail; main; fi`). `set -u -o pipefail` is deliberately without `-e`: any field missing from the input JSON silently drops that segment via `[ -n ... ]` guards rather than breaking the render.

**Segment registry** (`lib/registry.sh`): segments aren't hardcoded into `main` — each `segments/*.sh` file (and any user plugin, see below) calls `register_segment <line 1|2|3> <name> <builder-fn> [show-var]` at its top level. Bash 3.2 has no associative arrays, so segment metadata (builder function name, show-var name) lives in plain globals named by convention (`STATUSLINE_SEGMENT_BUILDER_<name>`, `STATUSLINE_SEGMENT_SHOWVAR_<name>`) reached via single-level `${!name}` indirection, written with `printf -v` (never `eval`, and `<name>` is validated against `[A-Za-z0-9_]+` first since it lands in a variable-name position). Re-registering a name overwrites its builder and warns to stderr — this is how a plugin can deliberately replace a built-in segment. `render_line <segments-list-var-name>` iterates the space-separated name list held by that variable, skips unregistered names, honors the show-var (hidden when set and not `"1"`), calls each builder with no arguments, and prints non-empty results one per line.

`main()` (`lib/main.sh`) is: `load_config` → `load_segment_plugins "$STATUSLINE_SEGMENTS_DIR"` (sources every `*.sh` in the plugin directory — **only from inside `main`**, never at plain source time, so sourcing the entrypoint for tests never executes a real user's plugin scripts) → `finalize_segment_order` (defaults `STATUSLINE_LINE{1,2,3}_SEGMENTS` to whatever order `register_segment` built up, unless env/config-file already set them) → `parse_payload` → three `render_line` calls building `line1`/`line2`/`line3` arrays → `join_line`-join each and print. A line whose array is empty prints nothing (so line 3 can be absent without leaving a blank line, and line 3 shifts up to print as line 2 if line 2 is itself empty); ends with `exit 0` so an empty trailing line doesn't leak a non-zero status. See "Adding a built-in segment" above for the mechanics of adding one, and README.md's "Custom segments" for the third-party plugin contract end users see.

`lib/payload.sh`'s `parse_payload()` parses all payload fields in a **single jq pass** — the status line renders on every prompt, so process count is the latency budget — emitting `key<TAB>value` lines consumed by a `while read` + `case` dispatch into named `PAYLOAD_*` globals (e.g. `PAYLOAD_MODEL`, `PAYLOAD_FIVE_H_PCT`). Unlike a positional `read`, the jq filter and the `case` arms don't need to stay in matching order — add a new field by adding one jq line and one `case` arm, in either order. `PAYLOAD_*` is the read-only field surface both built-in segments and third-party plugins consume; treat renaming one with the same care as renaming a `STATUSLINE_SHOW_*` var.

Configuration is resolved by `load_config` (`lib/config.sh`) with precedence environment > optional config file (`${XDG_CONFIG_HOME:-~/.config}/claude-statusline.conf`, path overridable via `STATUSLINE_CONFIG`) > built-in defaults. Tunables: `STATUSLINE_BAR_WIDTH`, `STATUSLINE_PCT_WARN`/`STATUSLINE_PCT_CRIT` (usage-severity color thresholds), `STATUSLINE_PACE_TOL`; every segment has a `STATUSLINE_SHOW_*` toggle; `STATUSLINE_SEGMENTS_DIR` and `STATUSLINE_LINE{1,2,3}_SEGMENTS` control the plugin directory and segment order (the latter three have no default inside `load_config` itself — their default isn't knowable until segments have registered, so it's asserted later by `finalize_segment_order`). Defaults must reproduce the golden output exactly — a new knob's default is the previous hard-coded value. Register any new variable in `STATUSLINE_CONFIG_VARS` (the list `load_config` snapshots so env wins over the file) and document it in README.md.

**Line 1** (default order: `title git`): project title (repo name, falling back to directory basename) → git branch with dirty/clean indicator, plus staged/modified/untracked file counts (`+N`/`~N`/`?N`) when dirty.

**Line 2** (default order: `model effort context five_hour seven_day cost`): model name (colored by family — opus/sonnet/haiku/fable) → reasoning effort level (colored low→max on a green→yellow→teal→red→magenta scale) → context-window usage tokens → 5-hour subscription rate-limit usage bar → 7-day usage marker (a compact single-cell pace gauge that expands into a full bar only when weekly usage is over pace) → session cost. The rate-limit segments are bracket-free; their labels are a live reset countdown (`3h`, `4d`, ...) rather than a fixed period name — see `reset_countdown` below. Order/membership is just the default for `STATUSLINE_LINE2_SEGMENTS` — see the Segment registry section above.

Two bar renderers (`lib/helpers.sh`):
- `bar(pct)` — plain filled/empty progress bar (█/░), `STATUSLINE_BAR_WIDTH` cells.
- `pace_bar(pct, elapsed_pct)` — same bar, but overlays a pace tick at the position usage "should" be if spent evenly across the elapsed portion of the rate-limit window. The tick's shape encodes pace: solid `▮` when usage is at or ahead of pace (`pct >= elapsed_pct`), hollow `▯` when behind. Bar color is chosen by the caller (`usage_segment`/`seven_day_segment`), not by `pace_bar` itself.

`elapsed_pct_of_window(reset, window_seconds)` computes how much of a rate-limit window has elapsed (clamped 0–100); the clock is injectable via `STATUSLINE_NOW`, which is what makes the pace goldens deterministic. `reset_countdown(reset, unit_seconds)` is the other clock-reading helper (same `STATUSLINE_NOW` injection): it ceils the time remaining until reset into whole units (3600 for hours, 86400 for days), printing `<1` once less than a whole unit remains — this is what turns `5h`/`7d` into live countdown labels. When a window's reset timestamp is absent from the payload, the segment wrapper (`segments/60-five-hour.sh`/`70-seven-day.sh`) falls back to the static `5h`/`7d` label.

The 5h window renders through `usage_segment(label, pct, reset, window_seconds)` (`lib/helpers.sh`, called from `segments/60-five-hour.sh`) — dim label, `pace_bar` + pace-scale color (`pace_color(pct, elapsed_pct, $RED)`: green below the even-spend pace, yellow on pace within ±`STATUSLINE_PACE_TOL` points, red over) when a reset time is present; plain `bar` + usage-severity color (`pct_color`: green < `STATUSLINE_PCT_WARN`, yellow < `STATUSLINE_PCT_CRIT`, red above) otherwise, since pace is unknowable without a reset. The reset timestamp positions the pace tick and (via `reset_countdown`, computed in the segment wrapper before calling `usage_segment`) drives the label.

The 7d window has its own `seven_day_segment(label, pct, reset, window_seconds)` helper (`lib/helpers.sh`, called from `segments/70-seven-day.sh`) because it renders two ways. By default it's a **compact single-cell pace marker** — one partial-block glyph (`▁▂▃▄▅▆▇█`, via `gauge_glyph`, mapping usage % to 8 levels) whose height encodes usage. It **expands into a full `pace_bar`** only when weekly usage runs genuinely over pace — when `used_percentage − elapsed_pace > STATUSLINE_PACE_TOL`, the same band where `pace_color` turns to its above-pace color, so expansion and that color trigger together. The entire 7d element is colored on the pace scale throughout via `pace_color(pct, elapsed_pct)` (default `above_color` = `$ORANGE`) — so the expanded bar is always orange. When no reset time is present pace is unknowable, so it stays a compact marker colored by `pct_color` usage severity and never expands. Both 5h and 7d share the `pace_color` scale (green/yellow/above-pace) but pass different `above_color` values — `$RED` for 5h, `$ORANGE` for 7d — so the two segments stay visually distinct. (Because 7d only expands when over pace, its `pace_bar` tick is always the solid `▮` form.)

Branch, dirty state, and staged/modified/untracked counts are all derived from a single `git -C "$cwd" --no-optional-locks status --porcelain=v2 --branch` call, parsed once, in `git_segment_text(cwd)` (`lib/git.sh`, called from `segments/20-git.sh`). The whole segment is skipped when that call returns empty (not inside a git repo) — there's no error path, checks just fail closed via `[ -n ... ]` guards.

**Line 3** (default order: `email`, optional and off by default via `STATUSLINE_SHOW_EMAIL`): the logged-in Claude account's email. This is the one segment that ignores the stdin payload entirely — `STDIN_PAYLOAD.md` documents no account/user field — and instead reads `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.claude.json` → `.oauthAccount.emailAddress` via `account_email()` (`lib/account.sh`, called from `segments/90-email.sh`), which fails closed to `""` (missing dir/file/field, malformed JSON) exactly like the other guarded segments. It renders whenever an email is present and its show-var is `"1"`, regardless of which profile (`CLAUDE_CONFIG_DIR`) is active.
