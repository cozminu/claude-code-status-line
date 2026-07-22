# shellcheck shell=bash

# Renders the line-1 git branch segment for `cwd`: dirty/clean indicator plus
# staged/modified/untracked file counts, derived from a single `git status`
# call. Prints nothing outside a git repo (fails closed). Logic extracted
# verbatim from the old inline block in main().
git_segment_text() {
  local cwd="$1"
  local status_output branch oid staged modified untracked line xy git_counts
  status_output=$(git -C "$cwd" --no-optional-locks status --porcelain=v2 --branch 2>/dev/null)
  [ -n "$status_output" ] || return
  branch=$(printf '%s\n' "$status_output" | awk '/^# branch\.head /{print $3}')
  if [ "$branch" = "(detached)" ]; then
    oid=$(printf '%s\n' "$status_output" | awk '/^# branch\.oid /{print $3}')
    branch="detached@${oid:0:7}"
  fi
  staged=0
  modified=0
  untracked=0
  while IFS= read -r line; do
    case "$line" in
      "1 "*|"2 "*)
        xy=$(printf '%s' "$line" | awk '{print $2}')
        [ "${xy:0:1}" != "." ] && staged=$(( staged + 1 ))
        [ "${xy:1:1}" != "." ] && modified=$(( modified + 1 ))
        ;;
      "u "*)
        modified=$(( modified + 1 ))
        ;;
      "? "*)
        untracked=$(( untracked + 1 ))
        ;;
    esac
  done <<< "$status_output"
  [ -n "$branch" ] || return
  if [ "$staged" -gt 0 ] || [ "$modified" -gt 0 ] || [ "$untracked" -gt 0 ]; then
    git_counts=""
    [ "$staged" -gt 0 ] && git_counts="${GREEN}+${staged}${RESET}"
    [ "$modified" -gt 0 ] && git_counts="${git_counts}${YELLOW}~${modified}${RESET}"
    [ "$untracked" -gt 0 ] && git_counts="${git_counts}${DIM}?${untracked}${RESET}"
    printf '%s%s ✗%s %s' "$YELLOW" "$branch" "$RESET" "$git_counts"
  else
    printf '%s%s ✓%s' "$GREEN" "$branch" "$RESET"
  fi
}
