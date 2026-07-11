# claude-statusline

A single bash script that renders [Claude Code](https://claude.com/claude-code)'s
status line. Claude Code pipes a JSON payload (model, git workspace, context
usage, rate limits, session cost) to the script's stdin on every prompt render;
the script prints two ANSI-colored lines:

```
status-line | main ✗ +1~2?1
Fable 5 | high | 84k | 3h ███░░▯░░░░ | 4d ▄ | $1.23
```

- **Line 1** — project title, git branch with dirty/clean indicator and
  staged (`+N`) / modified (`~N`) / untracked (`?N`) counts.
- **Line 2** — model name (colored by family), reasoning effort, context
  tokens used, 5-hour and 7-day subscription usage, session cost.

The 5h/7d labels are a live reset countdown — integer hours remaining for
the 5h window, integer days remaining for the 7d window (`3h`, `4d`, ...),
rounded up and shown as `<1h`/`<1d` once less than a whole unit remains.
When the payload has no reset timestamp for a window, the label falls back
to the static period name (`5h`/`7d`).

The 5h bar carries a *pace tick* marking where usage "should" be if spent
evenly across the window (solid `▮` at/ahead of pace, hollow `▯` behind).
The 7d segment is a compact one-cell gauge (`▁`–`█`) colored by pace
(green under / yellow on / orange over) that expands into a full bar only
when weekly usage runs genuinely over pace. Segments whose data is missing
from the payload (no effort, API-key billing without rate limits, not a git
repo, ...) drop out silently.

## Requirements

`bash` (3.2+, macOS system bash works), `jq`, `git`.

## Install

```bash
ln -s "$PWD/statusline-command.sh" ~/statusline-command.sh
```

and in `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/statusline-command.sh"
  }
}
```

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
| `STATUSLINE_PACE_TOL` | `5` | ± percentage points that still count as "on pace" (also the 7d expansion trigger) |
| `STATUSLINE_SHOW_TITLE` | `1` | Project title (set any toggle to `0` to hide) |
| `STATUSLINE_SHOW_GIT` | `1` | Git branch + file counts |
| `STATUSLINE_SHOW_MODEL` | `1` | Model name |
| `STATUSLINE_SHOW_EFFORT` | `1` | Reasoning effort level |
| `STATUSLINE_SHOW_CONTEXT` | `1` | Context tokens used |
| `STATUSLINE_SHOW_FIVE_HOUR` | `1` | 5-hour usage bar |
| `STATUSLINE_SHOW_SEVEN_DAY` | `1` | 7-day pace marker |
| `STATUSLINE_SHOW_COST` | `1` | Session cost |
| `STATUSLINE_NOW` | *(unset)* | Test-only: pin the clock (unix seconds) for deterministic pace math |
| `STATUSLINE_CONFIG` | *(see above)* | Test-only: alternate config file path |

## Testing

The test suite is [bats-core](https://github.com/bats-core/bats-core),
vendored under `test/vendor/` — nothing to install:

```bash
./run-tests.sh
```

runs four suites (`shellcheck` is included as a lint step when installed):

- `test/unit.bats` — the pure helpers, called directly on the sourced script.
- `test/e2e.bats` — golden tests: fixture payloads (`test/fixtures/`) piped
  through the script must match `test/golden/` byte-for-byte, clock pinned
  via `STATUSLINE_NOW`.
- `test/config.bats` — config precedence, tunables, segment toggles.
- `test/git.bats` — line 1 against real throwaway repos.

If you change the output *intentionally*, regenerate the goldens with
`test/regen-golden.sh` and review the diff; otherwise a failing golden test
means a refactor changed behavior.

## Payload

See [STDIN_PAYLOAD.md](STDIN_PAYLOAD.md) for the full JSON Claude Code sends,
including fields the script doesn't use yet.
