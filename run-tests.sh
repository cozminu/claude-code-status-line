#!/bin/bash
# Runs the full bats suite (vendored, no dependencies beyond bash+jq+git),
# plus shellcheck as an optional lint step when it's installed.
set -u
cd "$(dirname "$0")" || exit 1

fail=0
./test/vendor/bats-core/bin/bats test || fail=1

if command -v shellcheck >/dev/null 2>&1; then
  echo "# shellcheck statusline-command.sh"
  shellcheck statusline-command.sh || fail=1
else
  echo "# shellcheck not installed - lint step skipped"
fi

exit "$fail"
