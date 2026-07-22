# shellcheck shell=bash
# Generic segment registry: lets built-in segments (segments/*.sh) and
# user plugins (STATUSLINE_SEGMENTS_DIR/*.sh) register themselves instead of
# being hardcoded into main(). Bash 3.2 has no associative arrays, so segment
# metadata lives in plain globals named by convention and reached via
# single-level ${!name} indirection (available since bash 2.x, unlike
# namerefs/declare -n which are bash-4.3+).

STATUSLINE_LINE1_DEFAULT_ORDER=""
STATUSLINE_LINE2_DEFAULT_ORDER=""
STATUSLINE_LINE3_DEFAULT_ORDER=""

# register_segment <line 1|2|3> <name> <builder-fn> [show-var]
#
# <name>        must match [A-Za-z0-9_]+ (used to build the indirection
#               variable names below).
# <builder-fn>  called with no arguments; must print the fully rendered,
#               color-coded segment text with no trailing newline, or print
#               nothing to omit the segment for this render.
# [show-var]    an env/config var name gating the segment: hidden when that
#               var is set to something other than "1". Omit for an
#               always-on segment (no toggle).
#
# Re-registering an existing <name> overrides its builder/show-var (lets a
# plugin deliberately replace a built-in segment by reusing its name) and
# warns to stderr, but is only added to the default order once.
register_segment() {
  local line="$1" name="$2" builder="$3" show_var="${4:-}"
  case "$name" in
    ""|*[!A-Za-z0-9_]*)
      printf 'register_segment: invalid segment name "%s"\n' "$name" >&2
      return 1
      ;;
  esac

  local builder_var="STATUSLINE_SEGMENT_BUILDER_${name}"
  if [ -n "${!builder_var:-}" ]; then
    printf 'register_segment: "%s" already registered, overriding builder\n' "$name" >&2
  else
    case "$line" in
      1) STATUSLINE_LINE1_DEFAULT_ORDER="${STATUSLINE_LINE1_DEFAULT_ORDER:+$STATUSLINE_LINE1_DEFAULT_ORDER }$name" ;;
      2) STATUSLINE_LINE2_DEFAULT_ORDER="${STATUSLINE_LINE2_DEFAULT_ORDER:+$STATUSLINE_LINE2_DEFAULT_ORDER }$name" ;;
      3) STATUSLINE_LINE3_DEFAULT_ORDER="${STATUSLINE_LINE3_DEFAULT_ORDER:+$STATUSLINE_LINE3_DEFAULT_ORDER }$name" ;;
      *)
        printf 'register_segment: invalid line "%s" for "%s"\n' "$line" "$name" >&2
        return 1
        ;;
    esac
  fi
  printf -v "$builder_var" '%s' "$builder"
  printf -v "STATUSLINE_SEGMENT_SHOWVAR_${name}" '%s' "$show_var"
}

# render_line <segments-list-var-name>
# Prints each visible, non-empty segment named in the space-separated list
# held by the given variable (e.g. STATUSLINE_LINE2_SEGMENTS), one per line.
render_line() {
  local segments_var="$1"
  local seg builder_var showvar_var builder show_var text
  for seg in ${!segments_var:-}; do
    builder_var="STATUSLINE_SEGMENT_BUILDER_${seg}"
    builder="${!builder_var:-}"
    [ -n "$builder" ] || continue          # unknown name in an order override: skip, don't error
    showvar_var="STATUSLINE_SEGMENT_SHOWVAR_${seg}"
    show_var="${!showvar_var:-}"
    if [ -n "$show_var" ] && [ "${!show_var:-1}" != "1" ]; then
      continue
    fi
    text=$("$builder")
    [ -n "$text" ] && printf '%s\n' "$text"
  done
}
