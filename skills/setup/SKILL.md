---
name: setup
description: Wire claude-statusline into Claude Code's statusLine setting. Use when the user has just installed the claude-statusline plugin and needs it registered, or when a SessionStart nudge reports the statusLine setting is missing or stale.
---

Run `"${CLAUDE_PLUGIN_ROOT}"/scripts/setup.sh` and relay its output to the user verbatim.

Do not hand-edit `settings.json` yourself under any circumstances --
`scripts/setup.sh` is the only thing in this plugin allowed to write it. If
the script exits 1 because it found a `statusLine` value it doesn't
recognize and there's no terminal to prompt in, it prints the exact JSON
block to paste plus instructions for re-running it interactively or with
`--force`. Relay that block and those instructions to the user instead of
writing the file yourself.

If the script exits 0, tell the user their status line is wired up and that
a new session will pick it up.
