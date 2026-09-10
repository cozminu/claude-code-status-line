# Plugin Packaging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make this repo installable as a Claude Code plugin (`/plugin marketplace add` → `/plugin install` → `/claude-statusline:setup`) without touching the existing from-a-clone install path.

**Architecture:** The repo becomes both a single-plugin marketplace and the plugin itself — nothing existing moves. New, purely additive files: `.claude-plugin/{plugin.json,marketplace.json}` (manifests), `scripts/setup.sh` (the sole writer of `settings.json`, jq+temp-file+mv, with a full decision table for what it finds at `.statusLine.command`), `skills/setup/SKILL.md` (thin wrapper invoked as `/claude-statusline:setup`), and `hooks/hooks.json` + `scripts/check-wiring.sh` (a read-only, silent-when-healthy `SessionStart` nudge for when `/plugin update` moves the install to a new version-pinned cache path).

**Tech Stack:** bash 3.2 (macOS system bash), `jq` (1.7.1 confirmed installed), bats-core (vendored under `test/vendor/`), shellcheck.

**Spec:** `docs/superpowers/specs/2026-08-04-plugin-packaging-design.md`

## Global Constraints

- Must stay bash 3.2 compatible: no `mapfile`, no associative arrays, no `${var,,}` (from `CLAUDE.md`).
- `shellcheck -x statusline-command.sh`, `shellcheck segments/*.sh`, and (new, this plan) `shellcheck scripts/*.sh` must all stay at zero findings.
- Golden e2e output (`test/golden/*.out`) is byte-exact. Nothing in this plan touches `statusline-command.sh`, `lib/*.sh`, or `segments/*.sh`, so no task in this plan should ever produce a golden diff — verify this explicitly whenever a task runs `./run-tests.sh`.
- Every new test suite must stay hermetic: set `STATUSLINE_CONFIG`, `CLAUDE_CONFIG_DIR`, and `STATUSLINE_SEGMENTS_DIR` to nonexistent paths (from `CLAUDE.md`), even in suites that don't invoke `statusline-command.sh` directly.
- `scripts/setup.sh` is the **only** thing in this repo allowed to write `settings.json`. `scripts/check-wiring.sh` and `skills/setup/SKILL.md` must never write it themselves — the skill relays `setup.sh`'s own output instead of hand-editing JSON.
- The plugin name is `claude-statusline`, the marketplace name is `cozminu` (matches `origin` = `github.com/cozminu/claude-code-status-line`), so install reads `claude-statusline@cozminu`.
- `${CLAUDE_PLUGIN_ROOT}` is confirmed (via `https://code.claude.com/docs/en/plugins-reference.md`) to expand inside both skill content and hook/monitor commands — the hook in this plan can rely on it directly.
- Full design detail lives in the spec above; this plan implements it task-by-task.

---

### Task 1: Plugin manifests

**Files:**
- Create: `.claude-plugin/plugin.json`
- Create: `.claude-plugin/marketplace.json`
- Test: `test/manifest.bats`

**Interfaces:**
- Produces: nothing consumed by later tasks — the manifests are read only by Claude Code's own `/plugin` commands, never by this repo's scripts.

- [ ] **Step 1: Write the failing tests**

Create `test/manifest.bats`:

```bash
# shellcheck shell=bash
# Manifest sanity: a broken .claude-plugin/*.json should fail CI immediately
# rather than surface as a cryptic /plugin install failure later.

setup() {
  # Hermetic per CLAUDE.md -- these tests never invoke statusline-command.sh,
  # but new suites set all three regardless.
  export STATUSLINE_CONFIG="$BATS_TEST_TMPDIR/no-such.conf"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/no-such-claude-dir"
  export STATUSLINE_SEGMENTS_DIR="$BATS_TEST_TMPDIR/no-such-segments-dir"
}

@test "plugin.json is valid JSON naming the claude-statusline plugin" {
  [ "$(jq -r '.name' "$BATS_TEST_DIRNAME/../.claude-plugin/plugin.json")" = "claude-statusline" ]
}

@test "marketplace.json is valid JSON with one plugin entry sourced from the repo root" {
  local f="$BATS_TEST_DIRNAME/../.claude-plugin/marketplace.json"
  [ "$(jq '.plugins | length' "$f")" = "1" ]
  [ "$(jq -r '.plugins[0].name' "$f")" = "claude-statusline" ]
  [ "$(jq -r '.plugins[0].source' "$f")" = "./" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./test/vendor/bats-core/bin/bats test/manifest.bats`
Expected: both tests FAIL — `jq` reports "No such file or directory" for both manifest paths.

- [ ] **Step 3: Implement — create the manifests**

Create `.claude-plugin/plugin.json`:

```json
{
  "name": "claude-statusline",
  "description": "Bash-rendered, configurable Claude Code status line: git branch/dirty state, model, context usage, 5h/7d rate-limit bars with pace tracking, session cost.",
  "version": "1.0.0",
  "author": {
    "name": "Cozmin Ungureanu",
    "email": "ucozmin@gmail.com"
  },
  "homepage": "https://github.com/cozminu/claude-code-status-line",
  "repository": "https://github.com/cozminu/claude-code-status-line",
  "license": "MIT"
}
```

Create `.claude-plugin/marketplace.json`:

```json
{
  "name": "cozminu",
  "owner": {
    "name": "Cozmin Ungureanu",
    "email": "ucozmin@gmail.com"
  },
  "plugins": [
    {
      "name": "claude-statusline",
      "source": "./",
      "description": "Bash-rendered, configurable Claude Code status line."
    }
  ]
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./test/vendor/bats-core/bin/bats test/manifest.bats`
Expected: PASS, both tests.

- [ ] **Step 5: Run the full suite to confirm no golden regressions**

Run: `./run-tests.sh`
Expected: PASS. No `test/golden/*.out` diffs — these are static manifest files nothing else reads yet.

- [ ] **Step 6: Commit**

```bash
git add .claude-plugin/plugin.json .claude-plugin/marketplace.json test/manifest.bats
git commit -m "Add plugin.json and marketplace.json manifests"
```

---

### Task 2: `scripts/setup.sh` — the only writer of `settings.json`

**Files:**
- Create: `scripts/setup.sh`
- Modify: `run-tests.sh`
- Test: `test/setup.bats`

**Interfaces:**
- Consumes: `CLAUDE_CONFIG_DIR`/`HOME` env (default settings path), `STATUSLINE_SETUP_TTY` env (test-only override of the real `[ -t 0 ]` check).
- Produces: the executable `scripts/setup.sh` with flags `--force`, `--settings PATH`, `--help`; exit 0 on success/already-configured, exit 1 on refusal/error. Task 3's `skills/setup/SKILL.md` invokes this directly and relays its stdout/stderr and exit code — it does not reimplement any of this logic.

- [ ] **Step 1: Write the failing tests**

Create `test/setup.bats`:

```bash
# shellcheck shell=bash
# scripts/setup.sh: the only thing in this repo allowed to write
# settings.json. Covers every row of the decision table in the plugin
# packaging spec, plus --force and the non-interactive refusal.

SETUP="$BATS_TEST_DIRNAME/../scripts/setup.sh"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
COMMAND_PATH="$REPO_ROOT/statusline-command.sh"

setup() {
  export STATUSLINE_CONFIG="$BATS_TEST_TMPDIR/no-such.conf"
  export STATUSLINE_SEGMENTS_DIR="$BATS_TEST_TMPDIR/no-such-segments-dir"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  SETTINGS="$BATS_TEST_TMPDIR/settings.json"
}

@test "no settings file: creates it with just the statusLine key" {
  run "$SETUP" --settings "$SETTINGS"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.command' "$SETTINGS")" = "$COMMAND_PATH" ]
  [ "$(jq -r '.statusLine.type' "$SETTINGS")" = "command" ]
  [ "$(jq 'keys | length' "$SETTINGS")" = "1" ]
}

@test "settings path has no parent directory yet: creates it" {
  SETTINGS="$BATS_TEST_TMPDIR/nested/does/not/exist/settings.json"
  run "$SETUP" --settings "$SETTINGS"
  [ "$status" -eq 0 ]
  [ -f "$SETTINGS" ]
}

@test "without --settings, writes to \$CLAUDE_CONFIG_DIR/settings.json" {
  run "$SETUP"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.command' "$CLAUDE_CONFIG_DIR/settings.json")" = "$COMMAND_PATH" ]
}

@test "settings file exists without a statusLine key: adds it without prompting" {
  echo '{"other":"stuff"}' > "$SETTINGS"
  run "$SETUP" --settings "$SETTINGS"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.command' "$SETTINGS")" = "$COMMAND_PATH" ]
  [ "$(jq -r '.other' "$SETTINGS")" = "stuff" ]
}

@test "statusLine already points at our path: reports and writes nothing" {
  jq -n --arg cmd "$COMMAND_PATH" '{statusLine:{type:"command",command:$cmd}}' > "$SETTINGS"
  cp "$SETTINGS" "$SETTINGS.orig"
  run "$SETUP" --settings "$SETTINGS"
  [ "$status" -eq 0 ]
  diff "$SETTINGS.orig" "$SETTINGS"
  [[ "$output" == *"nothing to do"* ]]
}

@test "statusLine points at an older version of this plugin: rewrites without prompting" {
  local old="$BATS_TEST_TMPDIR/plugins/cache/cozminu/claude-statusline/0.9.0/statusline-command.sh"
  jq -n --arg cmd "$old" '{statusLine:{type:"command",command:$cmd}}' > "$SETTINGS"
  run "$SETUP" --settings "$SETTINGS"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.command' "$SETTINGS")" = "$COMMAND_PATH" ]
}

@test "statusLine points somewhere foreign, non-interactive: refuses, exit 1, prints a paste block" {
  jq -n '{statusLine:{type:"command",command:"/usr/local/bin/other-statusline.sh"}}' > "$SETTINGS"
  run "$SETUP" --settings "$SETTINGS"
  [ "$status" -eq 1 ]
  [ "$(jq -r '.statusLine.command' "$SETTINGS")" = "/usr/local/bin/other-statusline.sh" ]
  [[ "$output" == *"--force"* ]]
  [[ "$output" == *"$COMMAND_PATH"* ]]
}

@test "statusLine points somewhere foreign, interactive accept: rewrites" {
  jq -n '{statusLine:{type:"command",command:"/usr/local/bin/other-statusline.sh"}}' > "$SETTINGS"
  run bash -c "STATUSLINE_SETUP_TTY=1 '$SETUP' --settings '$SETTINGS' <<< y"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.command' "$SETTINGS")" = "$COMMAND_PATH" ]
}

@test "statusLine points somewhere foreign, interactive decline: leaves it unchanged, exit 1" {
  jq -n '{statusLine:{type:"command",command:"/usr/local/bin/other-statusline.sh"}}' > "$SETTINGS"
  run bash -c "STATUSLINE_SETUP_TTY=1 '$SETUP' --settings '$SETTINGS' <<< n"
  [ "$status" -eq 1 ]
  [ "$(jq -r '.statusLine.command' "$SETTINGS")" = "/usr/local/bin/other-statusline.sh" ]
}

@test "malformed settings.json: refuses and writes nothing" {
  echo 'not json' > "$SETTINGS"
  run "$SETUP" --settings "$SETTINGS"
  [ "$status" -eq 1 ]
  [ "$(cat "$SETTINGS")" = "not json" ]
}

@test "--force overwrites a foreign value without prompting and backs it up" {
  jq -n '{statusLine:{type:"command",command:"/usr/local/bin/other-statusline.sh"}}' > "$SETTINGS"
  run "$SETUP" --settings "$SETTINGS" --force
  [ "$status" -eq 0 ]
  [ "$(jq -r '.statusLine.command' "$SETTINGS")" = "$COMMAND_PATH" ]
  [ "$(jq -r '.statusLine.command' "$SETTINGS.bak")" = "/usr/local/bin/other-statusline.sh" ]
}

@test "--help prints usage and exits 0" {
  run "$SETUP" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./test/vendor/bats-core/bin/bats test/setup.bats`
Expected: every test FAILs — `scripts/setup.sh` doesn't exist yet, so `run "$SETUP" ...` fails with "No such file or directory" / status 127.

- [ ] **Step 3: Implement — create `scripts/setup.sh`**

```bash
#!/bin/bash
# The only script in this repo allowed to write settings.json. Everything
# else here (statusline-command.sh, segments/*.sh, scripts/check-wiring.sh)
# only ever reads it.
set -u -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMAND_PATH="$DIR/statusline-command.sh"

FORCE=0
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

usage() {
  cat <<'EOF'
Usage: setup.sh [--force] [--settings PATH] [--help]

Wires this plugin's statusline-command.sh into Claude Code's
statusLine.command setting.

  --force          Overwrite an existing foreign statusLine value without
                    prompting (backs up the old settings.json to
                    settings.json.bak first).
  --settings PATH  Write to PATH instead of the default
                    ${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json.
  --help           Show this message.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1; shift ;;
    --settings)
      [ $# -ge 2 ] || { echo "setup.sh: --settings requires a path" >&2; exit 1; }
      SETTINGS="$2"; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "setup.sh: unknown argument: $1" >&2; usage >&2; exit 1 ;;
  esac
done

DESIRED=$(jq -n --arg cmd "$COMMAND_PATH" '{type:"command",command:$cmd}')

# "A different version of this same plugin": the existing value's command
# sits in the plugin cache under this plugin's name but at a different
# version directory than the one we just resolved -- an upgrade in
# progress. Kept in sync with scripts/check-wiring.sh's copy of this same
# function; both must agree on what "stale" means.
is_stale_version() {
  case "$1" in
    */plugins/cache/*/claude-statusline/*/statusline-command.sh)
      [ "$1" != "$COMMAND_PATH" ] ;;
    *) return 1 ;;
  esac
}

# Overridable for tests, which never have a real tty attached to stdin: set
# STATUSLINE_SETUP_TTY=1 to force the interactive prompt path, or leave
# unset to fall back to the real [ -t 0 ] check.
is_tty() {
  if [ -n "${STATUSLINE_SETUP_TTY:-}" ]; then
    [ "$STATUSLINE_SETUP_TTY" = "1" ]
  else
    [ -t 0 ]
  fi
}

write_settings() {
  local tmp
  tmp="$(mktemp "${SETTINGS}.XXXXXX")" || { echo "setup.sh: could not create a temp file" >&2; exit 1; }
  if ! jq --argjson sl "$DESIRED" '.statusLine = $sl' "$SETTINGS" > "$tmp" 2>/dev/null; then
    rm -f "$tmp"
    echo "setup.sh: failed to write $SETTINGS" >&2
    exit 1
  fi
  mv "$tmp" "$SETTINGS"
}

mkdir -p "$(dirname "$SETTINGS")" || { echo "setup.sh: could not create $(dirname "$SETTINGS")" >&2; exit 1; }

[ -f "$SETTINGS" ] || echo '{}' > "$SETTINGS"

if ! jq -e . "$SETTINGS" >/dev/null 2>&1; then
  echo "setup.sh: $SETTINGS is not valid JSON, refusing to touch it" >&2
  exit 1
fi

HAS_KEY=$(jq -r 'has("statusLine")' "$SETTINGS")

if [ "$HAS_KEY" != "true" ]; then
  write_settings
  echo "setup.sh: wrote statusLine -> $COMMAND_PATH"
  exit 0
fi

EXISTING=$(jq -r '.statusLine.command // empty' "$SETTINGS")

if [ "$EXISTING" = "$COMMAND_PATH" ]; then
  echo "setup.sh: statusLine already points at $COMMAND_PATH, nothing to do"
  exit 0
fi

if is_stale_version "$EXISTING"; then
  write_settings
  echo "setup.sh: updated statusLine from an older plugin version ($EXISTING) to $COMMAND_PATH"
  exit 0
fi

# Anything else: a foreign statusLine value, or a statusLine key present
# without a usable command field.
if [ "$FORCE" = "1" ]; then
  cp "$SETTINGS" "$SETTINGS.bak"
  write_settings
  echo "setup.sh: replaced foreign statusLine value (backed up to $SETTINGS.bak)"
  exit 0
fi

if is_tty; then
  echo "setup.sh: statusLine is currently set to:"
  echo "  $EXISTING"
  printf 'Replace it with %s? [y/N] ' "$COMMAND_PATH"
  read -r ans
  case "$ans" in
    [yY]|[yY][eE][sS])
      write_settings
      echo "setup.sh: wrote statusLine -> $COMMAND_PATH"
      exit 0
      ;;
    *)
      echo "setup.sh: left statusLine unchanged"
      exit 1
      ;;
  esac
else
  echo "setup.sh: statusLine is currently set to:"
  echo "  $EXISTING"
  echo "setup.sh: not prompting without a terminal. Either:"
  echo "  - re-run this in a terminal: ! bash \"$0\""
  echo "  - or pass --force to overwrite it"
  echo "setup.sh: paste this block into settings.json yourself if you prefer:"
  jq -n --argjson sl "$DESIRED" '{statusLine:$sl}'
  exit 1
fi
```

Then: `chmod +x scripts/setup.sh`

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./test/vendor/bats-core/bin/bats test/setup.bats`
Expected: PASS, all 12 tests.

- [ ] **Step 5: Add the `scripts/*.sh` shellcheck pass to `run-tests.sh`**

In `run-tests.sh`, replace:

```bash
if command -v shellcheck >/dev/null 2>&1; then
  # -x follows the `# shellcheck source=` directives in statusline-command.sh,
  # merging it with lib/*.sh into one analysis unit (so e.g. colors.sh's
  # constants aren't flagged unused just because they're only read from
  # another sourced file). segments/*.sh is checked separately since it's
  # sourced via a runtime glob that -x can't follow.
  echo "# shellcheck -x statusline-command.sh"
  shellcheck -x statusline-command.sh || fail=1
  echo "# shellcheck segments/*.sh"
  shellcheck segments/*.sh || fail=1
else
  echo "# shellcheck not installed - lint step skipped"
fi
```

with:

```bash
if command -v shellcheck >/dev/null 2>&1; then
  # -x follows the `# shellcheck source=` directives in statusline-command.sh,
  # merging it with lib/*.sh into one analysis unit (so e.g. colors.sh's
  # constants aren't flagged unused just because they're only read from
  # another sourced file). segments/*.sh and scripts/*.sh are checked
  # separately since neither is reachable via a `source=` directive -x can
  # follow (segments/*.sh is sourced via a runtime glob; scripts/*.sh are
  # standalone executables, never sourced).
  echo "# shellcheck -x statusline-command.sh"
  shellcheck -x statusline-command.sh || fail=1
  echo "# shellcheck segments/*.sh"
  shellcheck segments/*.sh || fail=1
  echo "# shellcheck scripts/*.sh"
  shellcheck scripts/*.sh || fail=1
else
  echo "# shellcheck not installed - lint step skipped"
fi
```

- [ ] **Step 6: Run the full suite and confirm zero shellcheck findings, no golden regressions**

Run: `./run-tests.sh`
Expected: PASS, zero shellcheck findings on `scripts/setup.sh`, no `test/golden/*.out` diffs.

- [ ] **Step 7: Commit**

```bash
git add scripts/setup.sh run-tests.sh test/setup.bats
git commit -m "Add scripts/setup.sh: the sole writer of settings.json's statusLine key"
```

---

### Task 3: `skills/setup/SKILL.md` — thin wrapper invoked as `/claude-statusline:setup`

**Files:**
- Create: `skills/setup/SKILL.md`
- Modify: `test/manifest.bats`

**Interfaces:**
- Consumes: `scripts/setup.sh` (Task 2), `${CLAUDE_PLUGIN_ROOT}` (Claude Code's own plugin-root expansion, confirmed available in skill content).
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing test**

Append to `test/manifest.bats`:

```bash
@test "setup skill has frontmatter naming it setup" {
  local f="$BATS_TEST_DIRNAME/../skills/setup/SKILL.md"
  [ -f "$f" ]
  [ "$(sed -n '1p' "$f")" = "---" ]
  grep -q '^name: setup$' "$f"
  grep -q '^description:' "$f"
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `./test/vendor/bats-core/bin/bats test/manifest.bats`
Expected: the new test FAILs — `skills/setup/SKILL.md` doesn't exist yet.

- [ ] **Step 3: Implement — create `skills/setup/SKILL.md`**

```markdown
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
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `./test/vendor/bats-core/bin/bats test/manifest.bats`
Expected: PASS, all tests including the new one.

- [ ] **Step 5: Run the full suite**

Run: `./run-tests.sh`
Expected: PASS, no golden regressions.

- [ ] **Step 6: Commit**

```bash
git add skills/setup/SKILL.md test/manifest.bats
git commit -m "Add skills/setup/SKILL.md: thin wrapper over scripts/setup.sh"
```

---

### Task 4: `hooks/hooks.json` + `scripts/check-wiring.sh` — the SessionStart nudge

**Files:**
- Create: `hooks/hooks.json`
- Create: `scripts/check-wiring.sh`
- Test: `test/hook.bats`

**Interfaces:**
- Consumes: nothing from earlier tasks except the `is_stale_version` matching convention established in `scripts/setup.sh` (Task 2) — this task carries its own copy of that function, kept in sync by comment.
- Produces: nothing consumed by later tasks.

- [ ] **Step 1: Write the failing tests**

Create `test/hook.bats`:

```bash
# shellcheck shell=bash
# scripts/check-wiring.sh: read-only SessionStart nudge. Must never write
# settings.json, and must stay silent whenever wiring is healthy.

HOOK="$BATS_TEST_DIRNAME/../scripts/check-wiring.sh"
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
COMMAND_PATH="$REPO_ROOT/statusline-command.sh"

setup() {
  export STATUSLINE_CONFIG="$BATS_TEST_TMPDIR/no-such.conf"
  export STATUSLINE_SEGMENTS_DIR="$BATS_TEST_TMPDIR/no-such-segments-dir"
  export CLAUDE_CONFIG_DIR="$BATS_TEST_TMPDIR/claude"
  mkdir -p "$CLAUDE_CONFIG_DIR"
  SETTINGS="$CLAUDE_CONFIG_DIR/settings.json"
}

@test "healthy wiring: silent, exit 0" {
  jq -n --arg cmd "$COMMAND_PATH" '{statusLine:{type:"command",command:$cmd}}' > "$SETTINGS"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "no statusLine key: one-line nudge naming the setup skill" {
  echo '{}' > "$SETTINGS"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/claude-statusline:setup"* ]]
}

@test "stale version: nudge names the old and current paths" {
  local old="$BATS_TEST_TMPDIR/plugins/cache/cozminu/claude-statusline/0.9.0/statusline-command.sh"
  jq -n --arg cmd "$old" '{statusLine:{type:"command",command:$cmd}}' > "$SETTINGS"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [[ "$output" == *"$old"* ]]
  [[ "$output" == *"$COMMAND_PATH"* ]]
}

@test "foreign statusLine (someone else's status line): silent, exit 0" {
  jq -n '{statusLine:{type:"command",command:"/usr/local/bin/other-statusline.sh"}}' > "$SETTINGS"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "no settings file at all: silent, exit 0" {
  run "$HOOK"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "malformed settings.json: silent, exit 0" {
  echo 'not json' > "$SETTINGS"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `./test/vendor/bats-core/bin/bats test/hook.bats`
Expected: every test FAILs — `scripts/check-wiring.sh` doesn't exist yet.

- [ ] **Step 3: Implement — create `scripts/check-wiring.sh`**

```bash
#!/bin/bash
# Read-only SessionStart nudge: never writes settings.json (scripts/setup.sh
# is the only writer in this repo). Must stay silent whenever wiring is
# healthy, since SessionStart stdout is injected into Claude's context on
# every new session -- the healthy case has to cost zero tokens.
set -u -o pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMAND_PATH="$DIR/statusline-command.sh"
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"

# Kept in sync with scripts/setup.sh's copy of this same function; both must
# agree on what "an older version of this plugin" looks like.
is_stale_version() {
  case "$1" in
    */plugins/cache/*/claude-statusline/*/statusline-command.sh)
      [ "$1" != "$COMMAND_PATH" ] ;;
    *) return 1 ;;
  esac
}

command -v jq >/dev/null 2>&1 || exit 0
[ -f "$SETTINGS" ] || exit 0

EXISTING=$(jq -r '.statusLine.command // empty' "$SETTINGS" 2>/dev/null) || exit 0

[ "$EXISTING" = "$COMMAND_PATH" ] && exit 0

if [ -z "$EXISTING" ]; then
  echo "claude-statusline is installed but not wired up as your statusLine. Run /claude-statusline:setup to enable it (don't edit settings.json by hand)."
  exit 0
fi

if is_stale_version "$EXISTING"; then
  echo "claude-statusline's statusLine still points at an older install ($EXISTING). Run /claude-statusline:setup to update it to $COMMAND_PATH (don't edit settings.json by hand)."
  exit 0
fi

exit 0
```

Then: `chmod +x scripts/check-wiring.sh`

Create `hooks/hooks.json`:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "\"${CLAUDE_PLUGIN_ROOT}\"/scripts/check-wiring.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `./test/vendor/bats-core/bin/bats test/hook.bats`
Expected: PASS, all 6 tests.

- [ ] **Step 5: Run the full suite**

Run: `./run-tests.sh`
Expected: PASS, zero shellcheck findings (the shellcheck `scripts/*.sh` pass from Task 2 now also covers `check-wiring.sh`), no golden regressions.

- [ ] **Step 6: Commit**

```bash
git add hooks/hooks.json scripts/check-wiring.sh test/hook.bats
git commit -m "Add SessionStart hook: warn when statusLine wiring goes stale"
```

---

### Task 5: Documentation

**Files:**
- Modify: `README.md`
- Modify: `CLAUDE.md`

**Interfaces:**
- Consumes: nothing new — this task only documents Tasks 1-4's finished behavior.
- Produces: nothing consumed by other tasks; this is the last task.

- [ ] **Step 1: Split `README.md`'s Install section**

Replace:

```markdown
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
```

with:

```markdown
## Install

### As a plugin (recommended)

```
/plugin marketplace add cozminu/claude-code-status-line
/plugin install claude-statusline@cozminu
/claude-statusline:setup
```

The first two commands fetch the plugin; the third writes
`statusLine.command` in `~/.claude/settings.json` for you (see
[`scripts/setup.sh`](scripts/setup.sh) — it's the only thing in this repo
allowed to touch that file). A `SessionStart` hook checks that wiring on
every new session and tells you to re-run `/claude-statusline:setup` if it
ever goes stale (for example after `/plugin update`, since installs live in
a version-pinned cache path).

Updating: `/plugin update claude-statusline@cozminu`, then re-run
`/claude-statusline:setup` if the hook nudges you to.

Uninstalling: `/plugin uninstall claude-statusline@cozminu` removes the
plugin's files but leaves the `statusLine` key in `settings.json` behind —
remove it by hand, or run `/statusline` to replace it with something else.

### From a clone

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

### Live countdown labels

The 5h/7d labels (`2½h`, `3½d`, ...) are time-based and, like the rest of
the status line, only re-render on Claude Code's own events (a new message,
git state changing, and so on) — they won't visibly count down while a
session sits idle. Set `refreshInterval` (seconds, minimum `1`) in
`statusLine` to also re-run the script on a timer:

```json
{
  "statusLine": {
    "type": "command",
    "command": "/absolute/path/to/status-line/statusline-command.sh",
    "refreshInterval": 60
  }
}
```

It's a Claude Code `statusLine` setting, not one of this repo's own
`STATUSLINE_*` variables, so it isn't in the Configuration table below.
```

- [ ] **Step 2: Update `README.md`'s Testing section**

Replace:

```markdown
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
```

with:

```markdown
runs eight suites (`shellcheck` is included as a lint step when installed):

- `test/unit.bats` — the pure helpers, called directly on the sourced script.
- `test/e2e.bats` — golden tests: fixture payloads (`test/fixtures/`) piped
  through the script must match `test/golden/` byte-for-byte, clock pinned
  via `STATUSLINE_NOW`.
- `test/config.bats` — config precedence, tunables, segment toggles.
- `test/git.bats` — line 1 against real throwaway repos.
- `test/segments.bats` — the segment registry: default order, config-driven
  reordering, custom plugin segments, and that plugins only run under a real
  render, never when the entrypoint is merely sourced.
- `test/manifest.bats` — `.claude-plugin/plugin.json`/`marketplace.json`
  parse and shape, `skills/setup/SKILL.md` frontmatter.
- `test/setup.bats` — `scripts/setup.sh`'s `settings.json` decision table,
  `--force`, the non-interactive refusal.
- `test/hook.bats` — `scripts/check-wiring.sh`'s SessionStart nudge,
  including the silent-when-healthy case.
```

- [ ] **Step 3: Add a "Plugin packaging" section to `CLAUDE.md`**

Insert the following new section right after "## Adding a built-in segment" and before "## Architecture":

```markdown
## Plugin packaging

The repo is both a single-plugin Claude Code marketplace and the plugin
itself — nothing moves, `statusline-command.sh` still lives at the repo
root and the from-a-clone install keeps working unchanged.

`.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` are the
manifests; the marketplace has exactly one entry, `source: "./"`, pointing
at the repo root. Bump the version only in `plugin.json` — the marketplace
entry omits a version so a release touches one file.

`scripts/setup.sh` is the only thing in this repo allowed to write
`settings.json`. It resolves its own directory the same way
`statusline-command.sh` does (`BASH_SOURCE`-relative, no dependency on
`CLAUDE_PLUGIN_ROOT` being exported), and writes through `jq` into a temp
file followed by `mv` so a crash mid-write can't truncate a real user's
settings file. `skills/setup/SKILL.md` (invoked as `/claude-statusline:setup`)
is a thin wrapper around it — it must never hand-edit `settings.json`
itself, even when `setup.sh` refuses non-interactively; routing around the
single writer defeats the point of having one.

`scripts/check-wiring.sh`, run by a `SessionStart` hook (`hooks/hooks.json`,
matcher `startup`) declared with `${CLAUDE_PLUGIN_ROOT}`, is read-only and
must never write `settings.json`. It must stay silent (empty stdout, exit
0) whenever wiring is healthy — `SessionStart` output is injected into
Claude's context on every new session, so the healthy case has to cost zero
tokens — and only print a one-line nudge when `statusLine` is missing or
points at a stale version of this same plugin (a `/plugin update` moves the
install to a new version-pinned cache path). It stays silent when
`statusLine` points at something else entirely, since that's someone else's
deliberate choice. Both scripts carry their own copy of the "is this a
stale version of this plugin" check (a `case` match on
`*/plugins/cache/*/claude-statusline/*/statusline-command.sh`); keep the
two in sync if that pattern ever changes.

`run-tests.sh`'s shellcheck step also covers `scripts/*.sh` (a third pass
alongside the entrypoint and `segments/*.sh`, since standalone executables
aren't reachable via a `# shellcheck source=` directive either).
```

- [ ] **Step 4: Update `CLAUDE.md`'s Testing changes paragraph**

Replace:

```markdown
Lint runs as `shellcheck -x statusline-command.sh` (follows the `# shellcheck source=lib/*.sh` directives, merging the entrypoint with `lib/*.sh` into one analysis unit) plus `shellcheck segments/*.sh` separately (the entrypoint sources `segments/*.sh` via a runtime glob, which `-x` can't follow) — keep both at zero findings.
```

with:

```markdown
Lint runs as `shellcheck -x statusline-command.sh` (follows the `# shellcheck source=lib/*.sh` directives, merging the entrypoint with `lib/*.sh` into one analysis unit) plus `shellcheck segments/*.sh` (the entrypoint sources `segments/*.sh` via a runtime glob, which `-x` can't follow) and `shellcheck scripts/*.sh` (standalone executables, never sourced) separately — keep all three at zero findings.
```

Also replace:

```markdown
New behavior needs a test in the matching suite: pure helpers → `test/unit.bats` (the script is `source`d, helpers called directly), full renders → a fixture + golden in `test/e2e.bats`, config handling → `test/config.bats`, git segment → `test/git.bats` (builds throwaway repos), segment registry/ordering/plugins → `test/segments.bats`.
```

with:

```markdown
New behavior needs a test in the matching suite: pure helpers → `test/unit.bats` (the script is `source`d, helpers called directly), full renders → a fixture + golden in `test/e2e.bats`, config handling → `test/config.bats`, git segment → `test/git.bats` (builds throwaway repos), segment registry/ordering/plugins → `test/segments.bats`, plugin packaging (manifests, `scripts/setup.sh`, `scripts/check-wiring.sh`) → `test/manifest.bats`, `test/setup.bats`, `test/hook.bats`.
```

- [ ] **Step 5: Run the full suite one last time**

Run: `./run-tests.sh`
Expected: PASS — doc-only changes, but this confirms nothing was accidentally broken while editing adjacent files.

- [ ] **Step 6: Commit**

```bash
git add README.md CLAUDE.md
git commit -m "Document plugin packaging in README.md and CLAUDE.md"
```
