# Claude Code statusLine — stdin payload reference

Claude Code pipes a JSON object to the `statusLine` command's **stdin** on every
render. This documents the full payload so we know what's available beyond the
subset `statusline-command.sh` currently consumes.

- **Confirmed against:** Claude Code CLI `v2.1.206` (field names extracted from the binary)
- **Script currently uses:** ~11 fields (marked ✅ below)
- Fields can be added across versions — capture a live sample (see bottom) to see the exact current shape.

## Top-level fields

| Field | Used by script? | What it is |
|---|---|---|
| `hook_event_name` | no | Event type, e.g. `"Status"` |
| `session_id` | no | Current session UUID |
| `transcript_path` | no | Path to the session's `.jsonl` transcript |
| `cwd` | ✅ | Current working directory |
| `version` | no | Claude Code version string |
| `exceeds_200k_tokens` | no | Boolean — context has passed the 200k threshold |

## `model`

| Field | Used? | What it is |
|---|---|---|
| `model.display_name` | ✅ | e.g. "Opus 4.8" |
| `model.id` | no | Exact model id (`claude-opus-4-8`) |

## `workspace`

| Field | Used? | What it is |
|---|---|---|
| `workspace.current_dir` | ✅ | Active dir |
| `workspace.project_dir` | no | Project root (may differ from cwd) |
| `workspace.repo.name` | ✅ | Repo name; `repo` object holds more git metadata |

## `effort` / `output_style`

| Field | Used? | What it is |
|---|---|---|
| `effort.level` | ✅ | `low`…`max` reasoning level |
| `output_style.name` (+ `is_default`) | no | Active output style |

## `context_window` (script uses 3 of these)

| Field | Used? | What it is |
|---|---|---|
| `context_window.used_percentage` | ✅ | % of context window used |
| `context_window.total_input_tokens` | ✅ | |
| `context_window.total_output_tokens` | ✅ | |
| `context_window.cache_read_input_tokens` | no | Tokens served from cache |
| `context_window.cache_creation_input_tokens` | no | Tokens written to cache |
| `context_window.total_tokens` | no | |
| `context_window.max_output_tokens` | no | |

## `rate_limits` (script uses only the 5-hour window)

| Field | Used? | What it is |
|---|---|---|
| `rate_limits.five_hour.used_percentage` | ✅ | |
| `rate_limits.five_hour.resets_at` | ✅ | Unix timestamp of window reset |
| `rate_limits.five_hour.remaining` | no | |
| `rate_limits.seven_day.*` | no | The weekly window (same shape) |
| `rate_limits.weekly` / opus weekly cap | no | Opus-specific weekly limit |
| `rate_limits.billing_type` / `subscription` | no | Sub vs. API-key billing indicator |

## `cost` (script uses only the first)

| Field | Used? | What it is |
|---|---|---|
| `cost.total_cost_usd` | ✅ | Session cost in USD (the `$cost` segment) |
| `cost.total_duration_ms` | no | Wall-clock session time |
| `cost.total_api_duration_ms` | no | Time spent in API calls |
| `cost.total_lines_added` | no | Lines added this session |
| `cost.total_lines_removed` | no | Lines removed this session |

> Note: `total_cost_usd` is computed by Claude Code (token usage × per-model
> pricing, incl. cache discounts) and handed to the script pre-calculated. The
> status line does no cost arithmetic — it only formats the number.

## Unused data worth surfacing later

- **Cache token counts** (`cache_read/creation_input_tokens`) — cache efficiency indicator.
- **`seven_day` rate limit** — the weekly cap, often the binding one on Max plans; script only shows the 5h window.
- **`cost.total_lines_added/removed`** — quick churn indicator.
- **`total_duration_ms` vs `total_api_duration_ms`** — thinking/tool time vs. API time.
- **`exceeds_200k_tokens`** — flag to warn past 200k context.

## Capturing a live sample

To see the exact current payload, temporarily add this as the first line of
`main()` in `statusline-command.sh` (tee copies stdin to a file and passes it
through), trigger a render, then inspect and remove the line:

```bash
exec < <(tee /tmp/statusline-payload.json)
```
