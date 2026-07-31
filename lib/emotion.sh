# shellcheck shell=bash

# Reads the cache file written by the separately-installed emotion-statusline
# plugin (bencium/bencium-marketplace) and returns the classified emotion for
# this session, or "" if unavailable/stale/malformed. This repo never
# classifies emotion or writes this cache — only renders it, the same
# "external state, not the stdin payload" pattern account_email() uses for
# line 3. Fails closed on every error path, matching account_email/
# git_segment_text.
emotion_state() {
  local session="${PAYLOAD_SESSION_ID:-}"
  local cache_dir="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/cache"
  local file="$cache_dir/claude-emotion.json"
  if [ -n "$session" ] && [ -f "$cache_dir/claude-emotion-$session.json" ]; then
    file="$cache_dir/claude-emotion-$session.json"
  fi
  [ -f "$file" ] || return 0

  local mtime now age
  # stat's mtime flag differs between BSD (macOS) and GNU: try BSD's -f %m
  # first, then fall back to GNU's -c %Y so this works on both.
  mtime=$(stat -f %m "$file" 2>/dev/null || stat -c %Y "$file" 2>/dev/null) || return 0
  now="${STATUSLINE_NOW:-$(date +%s)}"
  age=$(( now - mtime ))
  [ "$age" -le 600 ] || return 0

  jq -r '.emotion // ""' "$file" 2>/dev/null
}
