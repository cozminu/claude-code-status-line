# Emotion segment (render-only port of emotion-statusline)

## Problem

The `emotion-statusline` Claude Code plugin (installed separately, from
`bencium/bencium-marketplace`) runs a `Stop` hook that classifies each
assistant turn's behavior into one of 14 emotional states via an independent
Haiku pass, and caches the result per session at
`~/.claude/cache/claude-emotion-<session_id>.json` (falling back to a global
`~/.claude/cache/claude-emotion.json`). Its bundled statusline script reads
that cache and appends a colored label to line 2, with a bold-red special
case for `desperate` (the state research ties to reward-hacking risk).

This repo's statusline doesn't show that label. The classifier hook is out of
scope here — it's a separate plugin concern, already running independently
once installed. What's missing is the render side: reading the cache file
this plugin already produces and displaying it, following this repo's
existing conventions for segments that read external state rather than the
stdin payload (`git_segment_text()`, `account_email()`).

## Design

### 1. `PAYLOAD_SESSION_ID`

`lib/payload.sh` gains one more field: `session_id\t\(.session_id // "")`
mapped to `PAYLOAD_SESSION_ID` in the `case` dispatch. Needed to pick the
per-session cache file over the global fallback.

### 2. `lib/emotion.sh` (new, peer to `lib/git.sh`/`lib/account.sh`)

```
emotion_state()
```

Zero-argument, reads `PAYLOAD_SESSION_ID` directly (same pattern as
`git_segment_text`/`account_email` reading globals rather than taking
params). Returns the emotion name on stdout, or `""` on any failure —
fails closed exactly like the other external-state readers:

- Cache root: `${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cache` — same root
  `account_email()` uses for `.claude.json`, one directory level down. Reusing
  this env var (rather than inventing a new one) means every existing test
  suite's `CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/no-such-claude-dir"` setup
  already makes this hermetic — no new isolation var needed anywhere.
- Path selection: if `PAYLOAD_SESSION_ID` is non-empty and
  `.../cache/claude-emotion-<session_id>.json` exists, use it; otherwise fall
  back to `.../cache/claude-emotion.json`. Matches upstream's fallback order.
- Freshness: `age = ${STATUSLINE_NOW:-$(date +%s)} - mtime(file)` (BSD
  `stat -f %m`, consistent with this repo's macOS-only bash-3.2 target).
  `age > 600` → treat as stale → return `""`. Using `STATUSLINE_NOW` (not raw
  `date`) keeps this deterministic for goldens, the same injection point
  `elapsed_pct_of_window`/`reset_countdown` already use.
- Parse: `jq -r '.emotion // ""'` on the chosen file; any missing
  file/unreadable/malformed-JSON/missing-field case falls through to `""` via
  the existing `2>/dev/null` + `// ""` idiom used throughout `lib/account.sh`.

### 3. `segments/25-emotion.sh` (new)

Numbered between `20-git.sh` and `30-model.sh` so it's the first segment on
line 2 by default (per your placement choice), registered as
`register_segment 2 emotion segment_emotion STATUSLINE_SHOW_EMOTION`.

`segment_emotion()`:

1. Calls `emotion_state()`; returns nothing if empty.
2. `desperate` is special-cased: renders `DESPERATE — verify output quality`
   in `$BOLD_RED`, matching upstream's warning text. No audio — this
   renderer has no precedent for side effects like sound, and the render-only
   scope excludes it.
3. Every other recognized emotion renders as the bare word in its mapped
   color (table below), reusing `lib/colors.sh` constants — no new ANSI
   codes introduced.
4. An unrecognized emotion string (e.g. the classifier adds a 15th state
   upstream later) still renders as plain uncolored text rather than being
   dropped — fail open on *rendering* even though the cache-read path fails
   closed on *availability*.

| emotion | color | emotion | color |
|---|---|---|---|
| curious | `$CYAN` | determined | `$WHITE` |
| focused | `$WHITE` | amused | `$MAGENTA` |
| satisfied | `$GREEN` | concerned | `$RED` |
| cautious | `$YELLOW` | relieved | `$GREEN` |
| enthusiastic | `$MAGENTA` | desperate | `$BOLD_RED` (special-cased text) |
| contemplative | `$BRIGHT_BLUE` | calm | `$TEAL` |
| confident | `$GREEN` | unknown | `$DIM` |
| uncertain | `$YELLOW` | *(unrecognized)* | no color, plain text |

### 4. Config

`STATUSLINE_SHOW_EMOTION` added to `lib/config.sh`'s
`STATUSLINE_CONFIG_VARS` and defaulted to `1` (on by default — unlike
`STATUSLINE_SHOW_EMAIL`, since this segment is a safe no-op without the
plugin installed: no cache file means it silently prints nothing). Documented
in README.md alongside the other `STATUSLINE_SHOW_*` toggles.

No new tunable for the 600s staleness window — hardcoded, matching upstream,
consistent with this repo's YAGNI stance on config knobs (add one when
something asks for it, not preemptively).

## Out of scope

- The `Stop` hook / Haiku classifier (`classify-emotion.sh`, `hooks.json`) —
  stays in the `emotion-statusline` plugin. This repo only renders whatever
  cache file already exists.
- The macOS `Basso` error sound upstream plays on `desperate`.
- Any change to `emotion-history.jsonl` or cache-sweeping behavior — both are
  the plugin's concern, not the renderer's.

## Blast radius / follow-up work

- `lib/payload.sh`: add `session_id` jq line + `PAYLOAD_SESSION_ID` case arm.
- `lib/emotion.sh` (new file): `emotion_state()`.
- `segments/25-emotion.sh` (new file): `segment_emotion()` +
  `register_segment` call.
- `statusline-command.sh`: add `# shellcheck source=lib/emotion.sh` directive
  and source the new file alongside the existing `lib/*.sh` sourcing chain.
- `lib/config.sh`: add `STATUSLINE_SHOW_EMOTION` default `1`, add to
  `STATUSLINE_CONFIG_VARS`.
- `test/unit.bats`: `emotion_state()` cases — fresh session cache, fresh
  global-fallback cache, stale cache via `STATUSLINE_NOW`, missing file,
  malformed JSON, missing `.emotion` field, session id set but only the
  global file exists.
- `test/fixtures/`: a fixture payload carrying `session_id`, plus a
  companion cache file under a fixture-local fake `CLAUDE_CONFIG_DIR`
  (pattern already established by `test/fixtures/fake-claude-config/`).
- `test/e2e.bats` + `test/golden/`: new fixture+golden pair for the emotion
  segment rendering (including one `desperate` case for the bold-red
  warning text); existing goldens are unaffected since
  `CLAUDE_CONFIG_DIR`/no `session_id` in existing fixtures means the segment
  renders nothing for them.
- `test/config.bats`: toggle test for `STATUSLINE_SHOW_EMOTION`.
- `README.md`: document the segment, its color table, the `desperate`
  special case, and the `STATUSLINE_SHOW_EMOTION` config row; note the
  dependency on the separately-installed `emotion-statusline` plugin.
- `CLAUDE.md`: add the segment to the Line 2 architecture description and
  the "Adding a built-in segment" file-layout list (`lib/emotion.sh` alongside
  `git.sh`/`account.sh` as an external-state reader).
