#!/bin/bash
# Regenerates the golden expected-output files in test/golden/ from the
# fixtures in test/fixtures/, pinning the clock so pace math is deterministic.
#
# Run this ONLY when an output change is intentional; the e2e suite treats
# these files as the byte-exact definition of correct output.
set -u
cd "$(dirname "$0")" || exit 1

# Must match STATUSLINE_EPOCH in e2e.bats.
export STATUSLINE_NOW=1750000000
# Goldens are defined at default config; ignore any real user config file.
export STATUSLINE_CONFIG=/nonexistent/statusline.conf
# Ignore any real logged-in account so goldens don't capture your own email.
export CLAUDE_CONFIG_DIR=/nonexistent/claude-config-dir

for fixture in fixtures/*.json; do
  name=$(basename "$fixture" .json)
  ../statusline-command.sh < "$fixture" > "golden/$name.out"
  printf 'regenerated golden/%s.out\n' "$name"
done
