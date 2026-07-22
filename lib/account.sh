# shellcheck shell=bash

# Email of the currently logged-in Claude account, read from the active
# profile's config file (CLAUDE_CONFIG_DIR, defaulting to ~/.claude like
# Claude Code itself) rather than the stdin payload, which carries no
# account/user field. Missing dir/file/field all fall through to "".
account_email() {
  local conf_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  jq -r '.oauthAccount.emailAddress // ""' "$conf_dir/.claude.json" 2>/dev/null
}
