# Line-1 git segment tests against real throwaway repos (goldens can't cover
# these: they need live `git status` output). Expected strings are built from
# the same ANSI codes the script uses and compared byte-for-byte.

SCRIPT="$BATS_TEST_DIRNAME/../statusline-command.sh"

RESET=$'\033[0m'
DIM=$'\033[2m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'

setup() {
  # Hermetic: a real user config file must not influence expected output.
  export STATUSLINE_CONFIG="$BATS_TEST_TMPDIR/no-such.conf"
  # Isolate from the user's git config so status output is deterministic.
  export GIT_CONFIG_GLOBAL=/dev/null
  export GIT_CONFIG_SYSTEM=/dev/null
  export GIT_AUTHOR_NAME=test GIT_AUTHOR_EMAIL=t@t GIT_AUTHOR_DATE='2026-01-01T00:00:00Z'
  export GIT_COMMITTER_NAME=test GIT_COMMITTER_EMAIL=t@t GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
  repo="$BATS_TEST_TMPDIR/proj"
  git -c init.defaultBranch=main init -q "$repo"
}

git_r() { git -C "$repo" "$@"; }

render() {
  printf '{"workspace":{"current_dir":"%s"}}' "$repo" | "$SCRIPT"
}

# Expected output when the payload has only current_dir: line 1 is
# title | branch-segment, line 2 is the default model name.
expect() {
  local branch_segment="$1"
  printf '%s\n%s\n' \
    "${DIM}proj${RESET}${DIM} | ${RESET}${branch_segment}" \
    "${CYAN}Claude${RESET}"
}

@test "clean repo: green branch with check mark" {
  git_r commit -q --allow-empty -m init
  diff <(expect "${GREEN}main ✓${RESET}") <(render)
}

@test "dirty repo: staged, modified, and untracked counts" {
  echo b > "$repo/tracked.txt" && git_r add tracked.txt && git_r commit -q -m init
  echo bb > "$repo/tracked.txt"
  echo a > "$repo/staged.txt" && git_r add staged.txt
  echo c > "$repo/untracked.txt"
  diff <(expect "${YELLOW}main ✗${RESET} ${GREEN}+1${RESET}${YELLOW}~1${RESET}${DIM}?1${RESET}") <(render)
}

@test "file both staged and modified counts toward both" {
  echo a > "$repo/f.txt" && git_r add f.txt && git_r commit -q -m init
  echo b > "$repo/f.txt" && git_r add f.txt
  echo c > "$repo/f.txt"
  diff <(expect "${YELLOW}main ✗${RESET} ${GREEN}+1${RESET}${YELLOW}~1${RESET}") <(render)
}

@test "fresh repo with no commits still renders a branch" {
  diff <(expect "${GREEN}main ✓${RESET}") <(render)
}

@test "detached HEAD renders detached@<sha7>" {
  git_r commit -q --allow-empty -m init
  git_r checkout -q --detach
  local sha
  sha=$(git_r rev-parse --short=7 HEAD)
  diff <(expect "${GREEN}detached@${sha} ✓${RESET}") <(render)
}

@test "repo name from payload wins over directory basename" {
  git_r commit -q --allow-empty -m init
  run bash -c 'printf "{\"workspace\":{\"current_dir\":\"%s\",\"repo\":{\"name\":\"named\"}}}" "$1" | "$2"' _ "$repo" "$SCRIPT"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == "${DIM}named${RESET}"* ]]
}

@test "non-git directory: git segment skipped, title remains" {
  local dir="$BATS_TEST_TMPDIR/plain"
  mkdir -p "$dir"
  run bash -c 'printf "{\"workspace\":{\"current_dir\":\"%s\"}}" "$1" | "$2"' _ "$dir" "$SCRIPT"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "${DIM}plain${RESET}" ]
}
