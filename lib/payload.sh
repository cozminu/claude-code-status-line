# shellcheck shell=bash

# Parses the stdin JSON payload in a single jq pass (the status line renders
# on every prompt, so process count is the latency budget) into PAYLOAD_*
# globals. Each jq line is "key<TAB>value", dispatched into a named global by
# the case statement below — unlike the old strict-positional read block,
# adding a field means adding one jq line + one case arm, in any order, since
# they're no longer coupled by position. Values are assumed tab/newline-free
# (names, paths, numbers), same assumption the previous version relied on.
# PAYLOAD_* is the read-only field surface both built-in segments and
# third-party plugins consume.
parse_payload() {
  PAYLOAD_MODEL="Claude"
  PAYLOAD_EFFORT=""
  PAYLOAD_CWD=""
  PAYLOAD_CTX_USED_PCT=""
  PAYLOAD_CTX_TOKENS=""
  PAYLOAD_FIVE_H_PCT=""
  PAYLOAD_FIVE_H_RESET=""
  PAYLOAD_SEVEN_D_PCT=""
  PAYLOAD_SEVEN_D_RESET=""
  PAYLOAD_COST_USD=""
  PAYLOAD_REPO_NAME=""

  local key value
  while IFS=$'\t' read -r key value; do
    case "$key" in
      model)         PAYLOAD_MODEL="$value" ;;
      effort)        PAYLOAD_EFFORT="$value" ;;
      cwd)           PAYLOAD_CWD="$value" ;;
      ctx_used_pct)  PAYLOAD_CTX_USED_PCT="$value" ;;
      ctx_tokens)    PAYLOAD_CTX_TOKENS="$value" ;;
      five_h_pct)    PAYLOAD_FIVE_H_PCT="$value" ;;
      five_h_reset)  PAYLOAD_FIVE_H_RESET="$value" ;;
      seven_d_pct)   PAYLOAD_SEVEN_D_PCT="$value" ;;
      seven_d_reset) PAYLOAD_SEVEN_D_RESET="$value" ;;
      cost_usd)      PAYLOAD_COST_USD="$value" ;;
      repo_name)     PAYLOAD_REPO_NAME="$value" ;;
      *) : ;;  # unknown key: ignore, forward-compatible with future fields
    esac
  done < <(jq -r '
    "model\t\(.model.display_name // "Claude")",
    "effort\t\(.effort.level // "")",
    "cwd\t\(.workspace.current_dir // .cwd // "")",
    "ctx_used_pct\t\(.context_window.used_percentage // "")",
    "ctx_tokens\t\(((.context_window.total_input_tokens // 0) + (.context_window.total_output_tokens // 0)))",
    "five_h_pct\t\(.rate_limits.five_hour.used_percentage // "")",
    "five_h_reset\t\(.rate_limits.five_hour.resets_at // "")",
    "seven_d_pct\t\(.rate_limits.seven_day.used_percentage // "")",
    "seven_d_reset\t\(.rate_limits.seven_day.resets_at // "")",
    "cost_usd\t\(.cost.total_cost_usd // "")",
    "repo_name\t\(.workspace.repo.name // "")"
  ')
}
