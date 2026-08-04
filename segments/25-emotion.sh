# shellcheck shell=bash
# Line 2 (first segment): Claude's inferred emotional state for this
# session, read from the separately-installed emotion-statusline plugin's
# cache file via emotion_state() (lib/emotion.sh). This repo never
# classifies emotion itself — only renders whatever that plugin's Stop hook
# already wrote.

segment_emotion() {
  local emotion
  emotion=$(emotion_state)
  [ -n "$emotion" ] || return

  if [ "$emotion" = "desperate" ]; then
    printf '%sDESPERATE%s' "$BOLD_RED" "$RESET"
    return
  fi

  local color
  case "$emotion" in
    curious)       color="$CYAN" ;;
    focused)       color="$WHITE" ;;
    satisfied)     color="$GREEN" ;;
    cautious)      color="$YELLOW" ;;
    enthusiastic)  color="$MAGENTA" ;;
    contemplative) color="$BRIGHT_BLUE" ;;
    confident)     color="$GREEN" ;;
    uncertain)     color="$YELLOW" ;;
    determined)    color="$WHITE" ;;
    amused)        color="$MAGENTA" ;;
    concerned)     color="$RED" ;;
    relieved)      color="$GREEN" ;;
    calm)          color="$TEAL" ;;
    unknown)       color="$DIM" ;;
    *)             color="" ;;
  esac
  if [ -n "$color" ]; then
    printf '%s%s%s' "$color" "$emotion" "$RESET"
  else
    printf '%s' "$emotion"
  fi
}
register_segment 2 emotion segment_emotion STATUSLINE_SHOW_EMOTION
