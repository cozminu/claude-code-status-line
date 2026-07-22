#!/bin/bash
# Runs the full bats suite (vendored, no dependencies beyond bash+jq+git),
# plus shellcheck as an optional lint step when it's installed.
set -u
cd "$(dirname "$0")" || exit 1

fail=0
./test/vendor/bats-core/bin/bats test || fail=1

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

exit "$fail"
