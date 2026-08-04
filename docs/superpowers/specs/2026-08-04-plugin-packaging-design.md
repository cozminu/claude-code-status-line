# Plugin packaging design

Make this repo installable as a Claude Code plugin, so a new user gets a
working status line from three commands instead of a manual clone plus a
hand-edited `settings.json`.

## The constraint that shapes everything

A plugin cannot register the main status line. Per the plugins reference, a
plugin's `settings.json` supports only the `agent` and `subagentStatusLine`
keys; `statusLine` stays a user-owned setting in `~/.claude/settings.json`.

So the plugin system can deliver the code and register hooks and skills, but
something still has to write that one settings key. This design puts that
work in a bundled script, invoked by a bundled skill.

A second constraint follows from it: `/plugin install` copies the plugin into
a version-pinned cache path
(`~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/`), so a
`statusLine.command` written today goes stale on the next `/plugin update`.
The old directory survives roughly two weeks after an update before cleanup,
so a stale path keeps working for a while rather than breaking instantly.
That grace period is what makes a warn-only approach viable.

## Layout

The repo becomes both a single-plugin marketplace and the plugin itself.
Nothing existing moves. `statusline-command.sh` stays at the repo root, so
the current clone-and-point install keeps working unchanged, and the plugin
root is the repo root.

New files, all additive:

```
.claude-plugin/
  plugin.json          # name: claude-statusline, version, author, repository, MIT
  marketplace.json     # name: cozminu, one entry, source: "./"
hooks/hooks.json       # SessionStart[startup] -> scripts/check-wiring.sh
scripts/
  setup.sh             # the only writer of settings.json in this repo
  check-wiring.sh      # read-only staleness check for the hook
skills/setup/SKILL.md  # /claude-statusline:setup, thin wrapper over setup.sh
```

None of the plugin auto-discovery locations (`skills/`, `commands/`,
`agents/`, `bin/`, `settings.json`, `.mcp.json`, `workflows/`, `themes/`,
`output-styles/`, `monitors/`) collide with anything already in the repo.

Install becomes:

```
/plugin marketplace add cozminu/claude-code-status-line
/plugin install claude-statusline@cozminu
/claude-statusline:setup
```

Naming: the marketplace is `cozminu` and the plugin is `claude-statusline`,
so the install line reads `claude-statusline@cozminu` rather than the
awkward `claude-statusline@claude-statusline`. The version lives only in
`plugin.json`; the marketplace entry omits it, so a release bumps one file.

## scripts/setup.sh

The only thing in the repo that writes `settings.json`.

It resolves its own directory via `BASH_SOURCE` the way
`statusline-command.sh` does, so it derives the plugin root itself and never
depends on `${CLAUDE_PLUGIN_ROOT}` being exported. Target settings file is
`${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json`, matching how
`lib/account.sh` and `lib/emotion.sh` already resolve config.

Flags: `--force`, `--settings PATH` (tests point this at a temp file),
`--help`.

Behavior, by what it finds at `.statusLine.command`:

| Found | Action |
|---|---|
| No settings file | Create it (with parent dirs) holding just the `statusLine` key |
| No `statusLine` key | Add it, no prompt |
| Already our exact path | Report it, write nothing, exit 0 |
| A different version of this same plugin | Rewrite without prompting, it is an upgrade |
| Anything else | Prompt, see below |
| Malformed JSON | Refuse, exit 1, write nothing |

It writes `{"type": "command", "command": "<plugin root>/statusline-command.sh"}`
and nothing else. No `padding`, no `refreshInterval`.

"A different version of this same plugin" means the existing value matches
`*/plugins/cache/*/claude-statusline/*/statusline-command.sh`, that is, it
points into the plugin cache at this plugin's name but not at the directory
we resolved. Anything else that is not our exact path counts as foreign.
`check-wiring.sh` uses the same match, so the two agree on what "stale"
means.

Writes go through `jq` (already a hard dependency of the renderer) into a
temp file followed by `mv`, so the rest of `settings.json` survives intact
and a crash mid-write cannot leave a truncated file.

**The foreign-value case.** When `statusLine` points at something that is
not this plugin, the script asks before overwriting. The main invocation
path is Claude running it through the skill, where there is no TTY to read
an answer from, so it branches on `[ -t 0 ]`:

- With a TTY: prompt y/n.
- Without one: do not prompt. Print the existing value and the exact JSON
  block to paste, then exit 1 with instructions to either re-run it in the
  terminal (`! bash .../setup.sh`) or pass `--force`.

`--force` skips the prompt and backs up to `settings.json.bak` before
replacing.

Exit codes: 0 for success or already-configured, 1 for refused or error.

## skills/setup/SKILL.md

Thin. Run the script, relay its output, and explicitly do not hand-edit
`settings.json`. That last instruction is load-bearing: without it Claude
routes around the script and edits the JSON directly the first time it hits
the non-interactive refusal, which defeats the point of having a single
writer.

## scripts/check-wiring.sh and the hook

`hooks/hooks.json` registers one `SessionStart` hook, matcher `startup` so
it does not re-fire on clear, compact, or fork, running
`"${CLAUDE_PLUGIN_ROOT}"/scripts/check-wiring.sh` with a 5 second timeout.

The script reads `.statusLine.command` and does nothing else. It never
writes.

- **Points at our current plugin root**: silent, exit 0. Silence is the
  point. `SessionStart` stdout is injected into Claude's context on every
  new session, so the healthy case has to cost zero tokens.
- **No `statusLine` key at all**: one line on stdout saying the plugin is
  installed but not wired up, that Claude should tell the user to run
  `/claude-statusline:setup`, and that Claude should not edit
  `settings.json` itself.
- **Points at an older version of this same plugin**: same shape, naming
  the old path and the current one.
- **Points at something else entirely**: silent. That is a deliberate
  choice by someone running another status line, and a nudge there would
  repeat every session forever with no way to dismiss it.
- **Any error** (no `jq`, unreadable file, malformed JSON): silent, exit 0.
  Same fail-closed style as every other guarded path in the repo.

No "seen it N times, stop nagging" marker. The nudge only fires in a state
the user can fix with one command, and it stops the moment they do.

## Docs

**README.md**: split Install into "As a plugin" (the three commands,
presented as the recommended path) and "From a clone" (the current content,
kept for development and for anyone who prefers it). Add a short subsection
on `refreshInterval` as an optional Claude Code setting worth turning on,
since the countdown labels (`2½h`, `3½d`) are time-based and otherwise only
update on Claude Code events. It stays out of the `STATUSLINE_*` config
table because it is not one of our variables. Also cover updating, and
uninstalling: `/plugin uninstall` leaves the `statusLine` key behind and it
has to be removed by hand or via `/statusline`.

**CLAUDE.md**: a section on the packaging. What lives in `.claude-plugin/`,
that `scripts/setup.sh` is the only thing in the repo allowed to write
`settings.json`, that `check-wiring.sh` must stay silent when healthy and
must never write, and that the version is bumped in `plugin.json` only.

## Tests

`test/setup.bats` covers every row of the decision table above, plus
`--force` and the non-TTY refusal. `test/hook.bats` covers the four
`check-wiring.sh` cases. Both are picked up by the existing `bats test`
glob. Both set `STATUSLINE_CONFIG`, `CLAUDE_CONFIG_DIR`, and
`STATUSLINE_SEGMENTS_DIR` to nonexistent paths per CLAUDE.md, and point
`--settings` at a temp file so a real `settings.json` is never touched.

A jq parse assertion over `plugin.json` and `marketplace.json` so a broken
manifest fails CI.

`run-tests.sh` gains `shellcheck scripts/*.sh` alongside the two existing
runs, kept at zero findings like the rest.

## Out of scope

- `subagentStatusLine`. A plugin can ship one, and this renderer could
  plausibly feed it, but it is a different output format and a different
  problem.
- Submitting to a third-party marketplace. This repo hosts its own.
- Any auto-repair of `settings.json` from the hook. Warn only, by choice.
