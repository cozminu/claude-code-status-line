#!/bin/bash
# Claude Code statusLine script
# Line 1: project title | git branch (dirty indicator + staged/modified counts)
# Line 2: model name | effort level | context tokens used | 5h + 7d subscription usage | session cost
#
# Thin entrypoint: sources lib/ (colors, config, registry, helpers, payload
# parsing, git, account) and every built-in segments/*.sh, then defines
# main(). Execution is source-guarded: running the script calls main (which
# reads the JSON payload from stdin and loads any user segment plugins from
# STATUSLINE_SEGMENTS_DIR), while `source`-ing it only defines functions and
# constants so tests can call each helper directly — sourcing never touches
# stdin or the plugin directory.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=lib/colors.sh
. "$DIR/lib/colors.sh"
# shellcheck source=lib/config.sh
. "$DIR/lib/config.sh"
# shellcheck source=lib/registry.sh
. "$DIR/lib/registry.sh"
# shellcheck source=lib/helpers.sh
. "$DIR/lib/helpers.sh"
# shellcheck source=lib/payload.sh
. "$DIR/lib/payload.sh"
# shellcheck source=lib/git.sh
. "$DIR/lib/git.sh"
# shellcheck source=lib/account.sh
. "$DIR/lib/account.sh"

# Built-in segments: shipped, trusted files, safe to source unconditionally
# (unlike the user plugin dir, which is only sourced inside main() — see
# lib/main.sh).
for f in "$DIR"/segments/*.sh; do
  [ -e "$f" ] || continue
  # shellcheck disable=SC1090
  . "$f"
done

# shellcheck source=lib/main.sh
. "$DIR/lib/main.sh"

# Run only when executed, not when sourced (tests source this file to reach
# the helpers directly, and set their own shell options).
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  # -e is deliberately absent: missing payload fields are expected and handled
  # by fail-closed [ -n ... ] guards, not by aborting the render.
  set -u -o pipefail
  main
fi
