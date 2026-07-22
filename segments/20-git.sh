# shellcheck shell=bash
# Line 1: git branch with dirty/clean indicator and staged/modified/untracked
# file counts. Skipped entirely outside a git repo (git_segment_text fails
# closed).

segment_git() {
  [ -n "$PAYLOAD_CWD" ] || return
  git_segment_text "$PAYLOAD_CWD"
}
register_segment 1 git segment_git STATUSLINE_SHOW_GIT
