# claude-statusline

A bash renderer for [Claude Code](https://claude.com/claude-code)'s
status line. Claude Code pipes a JSON payload (model, git workspace, context
usage, rate limits, session cost) to `statusline-command.sh`'s stdin on every
prompt render; the script prints up to three ANSI-colored lines:

```
status-line | main ✗ +1~2?1
Fable 5 | high | 84k | 3h ███▒▒░░░░░ | 4d ▄ | $1.23
you@example.com
```

- **Line 1** — project title, git branch with dirty/clean indicator and
  staged (`+N`) / modified (`~N`) / untracked (`?N`) counts.
- **Line 2** — model name (colored by family), reasoning effort, context
  tokens used, 5-hour and 7-day subscription usage, session cost.
- **Line 3** (optional, on by default) — the logged-in Claude account's
  email, read from `$CLAUDE_CONFIG_DIR/.claude.json` rather than the stdin
  payload. Disable with `STATUSLINE_SHOW_EMAIL=0`.

The 5h/7d labels are a live reset countdown — integer hours remaining for
the 5h window, integer days remaining for the 7d window (`3h`, `4d`, ...),
rounded up and shown as `<1h`/`<1d` once less than a whole unit remains.
When the payload has no reset timestamp for a window, the label falls back
to the static period name (`5h`/`7d`).

The 5h bar shades up to three regions based on pace — solid `█` for usage
within pace, a gap shade for the delta (`▓` denser when over pace, `▒` lighter
when under pace), and `░` for untouched — and is colored by that same pace — green under / yellow on / red over — whenever
a reset time is available; without one, pace is unknowable and it falls back
to a plain bar colored by usage severity. The 7d segment is a compact
one-cell gauge (`▁`–`█`) colored by pace (green under / yellow on / orange
over) that expands into a full bar only when weekly usage runs genuinely
over pace. 5h and 7d use the same pace scale but different "over pace"
colors (red vs. orange) so they stay visually distinct. Segments whose data
is missing from the payload (no effort, API-key billing without rate limits,
not a git repo, ...) drop out silently.

## Requirements

`bash` (3.2+, macOS system bash works), `jq`, `git`.

## Install

Clone the repo somewhere stable, then point `statusLine.command` in
`~/.claude/settings.json` directly at the cloned `statusline-command.sh`
(no symlink needed — the script finds its own `lib/`/`segments/` files
relative to wherever it lives):

```json
{
  "statusLine": {
    "type": "command",
    "command": "/absolute/path/to/status-line/statusline-command.sh"
  }
}
```

Moving or renaming the cloned directory later means updating this path.

## File layout

```
statusline-command.sh   # thin entrypoint: resolves its own directory, sources
                         # everything below, then runs main()
lib/
  colors.sh              # color constants
  config.sh              # STATUSLINE_CONFIG_VARS + load_config()
  registry.sh             # register_segment() / render_line() (see Custom segments)
  helpers.sh              # pure formatting helpers + segment builders
  payload.sh              # parse_payload(): one jq pass over stdin -> PAYLOAD_* globals
  git.sh                  # git_segment_text(): line-1 branch/dirty-state rendering
  account.sh              # account_email(): line-3 logged-in account lookup
  main.sh                 # main(): orchestration only
segments/                 # one file per built-in segment, e.g. 60-five-hour.sh
```

Numeric prefixes in `segments/` document the default render order and leave
room to insert a new built-in later without renaming files.

## Configuration

Everything is optional — with no configuration the defaults below apply.
Precedence: **environment variable > config file > default**.

The config file is plain bash assignments at
`${XDG_CONFIG_HOME:-~/.config}/claude-statusline.conf`
(path overridable via `STATUSLINE_CONFIG`):

```bash
STATUSLINE_BAR_WIDTH=20
STATUSLINE_SHOW_COST=0
```

| Variable | Default | Effect |
|---|---|---|
| `STATUSLINE_BAR_WIDTH` | `10` | Width (cells) of the 5h / expanded-7d bars |
| `STATUSLINE_PCT_WARN` | `50` | Usage severity threshold: green → yellow |
| `STATUSLINE_PCT_CRIT` | `80` | Usage severity threshold: yellow → red |
| `STATUSLINE_PACE_TOL` | `5` | ± percentage points that still count as "on pace" for the 5h/7d bars (also the 7d expansion trigger) |
| `STATUSLINE_SHOW_TITLE` | `1` | Project title (set any toggle to `0` to hide) |
| `STATUSLINE_SHOW_GIT` | `1` | Git branch + file counts |
| `STATUSLINE_SHOW_MODEL` | `1` | Model name |
| `STATUSLINE_SHOW_EFFORT` | `1` | Reasoning effort level |
| `STATUSLINE_SHOW_CONTEXT` | `1` | Context tokens used |
| `STATUSLINE_SHOW_FIVE_HOUR` | `1` | 5-hour usage bar |
| `STATUSLINE_SHOW_SEVEN_DAY` | `1` | 7-day pace marker |
| `STATUSLINE_SHOW_COST` | `1` | Session cost |
| `STATUSLINE_SHOW_EMAIL` | `1` | Logged-in account email (line 3) |
| `STATUSLINE_SEGMENTS_DIR` | `${XDG_CONFIG_HOME:-~/.config}/claude-statusline/segments.d` | Directory of custom segment scripts, sourced on every render (see Custom segments) |
| `STATUSLINE_LINE1_SEGMENTS` | `title git` | Line 1 segment names and order |
| `STATUSLINE_LINE2_SEGMENTS` | `model effort context five_hour seven_day cost` | Line 2 segment names and order |
| `STATUSLINE_LINE3_SEGMENTS` | `email` | Line 3 segment names and order |
| `STATUSLINE_NOW` | *(unset)* | Test-only: pin the clock (unix seconds) for deterministic pace math |
| `STATUSLINE_CONFIG` | *(see above)* | Test-only: alternate config file path |

## Custom segments

Segments aren't hardcoded — each one calls `register_segment <line> <name>
<builder-fn> [show-var]` (see `lib/registry.sh`), and `main()` renders
whatever's registered for `STATUSLINE_LINE{1,2,3}_SEGMENTS` in order. You can
reorder or drop built-in segments by setting those variables (space-separated
names, see table above), or add your own by dropping a script in
`STATUSLINE_SEGMENTS_DIR` (sourced fresh on every render — cheap top-level
code only, e.g. just the `register_segment` call itself):

```bash
# ~/.config/claude-statusline/segments.d/10-kubectx.sh
segment_kubectx() {
  local ctx
  ctx=$(kubectl config current-context 2>/dev/null) || return
  printf '%s%s%s' "$CYAN" "$ctx" "$RESET"
}
register_segment 2 kubectx segment_kubectx
```

Then add it to the order, e.g. `STATUSLINE_LINE2_SEGMENTS="model kubectx cost"`.
Your builder function can use the shipped color constants, any pure helper
(`pct_color`, `fmt_tokens`, `bar`, ...), and the parsed payload fields:

| `PAYLOAD_*` variable | Source |
|---|---|
| `PAYLOAD_MODEL` | `.model.display_name` |
| `PAYLOAD_EFFORT` | `.effort.level` |
| `PAYLOAD_CWD` | `.workspace.current_dir` |
| `PAYLOAD_CTX_USED_PCT` | `.context_window.used_percentage` |
| `PAYLOAD_CTX_TOKENS` | `.context_window.total_input_tokens + total_output_tokens` |
| `PAYLOAD_FIVE_H_PCT` / `PAYLOAD_FIVE_H_RESET` | `.rate_limits.five_hour.{used_percentage,resets_at}` |
| `PAYLOAD_SEVEN_D_PCT` / `PAYLOAD_SEVEN_D_RESET` | `.rate_limits.seven_day.{used_percentage,resets_at}` |
| `PAYLOAD_COST_USD` | `.cost.total_cost_usd` |
| `PAYLOAD_REPO_NAME` | `.workspace.repo.name` |

Registering a name that's already taken (built-in or another plugin) replaces
its builder and warns to stderr — this is how a plugin can deliberately
override a built-in segment. Plugin scripts run with full shell privileges,
the same trust model as any other sourced dotfile — only install ones you
trust.

## Testing

The test suite is [bats-core](https://github.com/bats-core/bats-core),
vendored under `test/vendor/` — nothing to install:

```bash
./run-tests.sh
```

runs five suites (`shellcheck` is included as a lint step when installed):

- `test/unit.bats` — the pure helpers, called directly on the sourced script.
- `test/e2e.bats` — golden tests: fixture payloads (`test/fixtures/`) piped
  through the script must match `test/golden/` byte-for-byte, clock pinned
  via `STATUSLINE_NOW`.
- `test/config.bats` — config precedence, tunables, segment toggles.
- `test/git.bats` — line 1 against real throwaway repos.
- `test/segments.bats` — the segment registry: default order, config-driven
  reordering, custom plugin segments, and that plugins only run under a real
  render, never when the entrypoint is merely sourced.

If you change the output *intentionally*, regenerate the goldens with
`test/regen-golden.sh` and review the diff; otherwise a failing golden test
means a refactor changed behavior.

## Payload

See [STDIN_PAYLOAD.md](STDIN_PAYLOAD.md) for the full JSON Claude Code sends,
including fields the script doesn't use yet.
