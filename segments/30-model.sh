# shellcheck shell=bash
# Line 2: model name, colored by model family.

segment_model() {
  printf '%s%s%s' "$(model_color "$PAYLOAD_MODEL")" "$PAYLOAD_MODEL" "$RESET"
}
register_segment 2 model segment_model STATUSLINE_SHOW_MODEL
