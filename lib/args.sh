#!/usr/bin/env bash
# Shared argument parser for gtr commands
# Depends on: ui.sh (log_error, show_command_help)
#
# Usage:
#   parse_args "<spec>" "$@"
#
# Spec format (one flag per line):
#   --force                    # boolean flag → _arg_force=1
#   --from: value              # value flag → _arg_from="<val>"
#   --dry-run|-n               # aliases → _arg_dry_run=1
#   --editor|-e                # short alias → _arg_editor=1
#
# Output variables:
#   _pa_positional[]   — positional arguments (array)
#   _pa_passthrough[]  — arguments after -- (array)
#   _arg_<name>        — one per declared flag (hyphens → underscores)
declare -a _pa_positional _pa_passthrough

# Try to match a flag against the spec. Sets _arg_<name> and _pa_shift_count.
# Returns 0 if matched, 1 if no match.
_pa_match_flag() {
  local spec="$1" flag="$2" next_val="${3:-}"

  _pa_shift_count=0

  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue

    # Check if spec line ends with ": value"
    local has_value=0
    case "$line" in
      *": value")
        has_value=1
        line="${line%: value}"
        ;;
    esac

    # Check if $flag matches any alternative in the pattern
    local alt matched=0
    local IFS_save="$IFS"
    IFS="|"
    for alt in $line; do
      if [ "$flag" = "$alt" ]; then
        matched=1
        break
      fi
    done
    IFS="$IFS_save"

    if [ "$matched" = "1" ]; then
      # Derive variable name from the first (canonical) pattern
      local canonical="${line%%|*}"
      canonical="${canonical#--}"
      canonical="${canonical#-}"
      canonical="${canonical//-/_}"

      if [ "$has_value" = "1" ]; then
        if [ -z "$next_val" ]; then
          log_error "$flag requires a value"
          exit 1
        fi
        eval "_arg_${canonical}=\"\$next_val\""
        _pa_shift_count=2
      else
        eval "_arg_${canonical}=1"
        _pa_shift_count=1
      fi
      return 0
    fi
  done <<EOF
$spec
EOF

  return 1
}

# Main parser. Call from command functions as: parse_args "<spec>" "$@"
parse_args() {
  local _pa_spec="$1"
  shift

  _pa_positional=()
  _pa_passthrough=()

  # Reset all _arg_ variables from the spec to empty
  local _pa_line
  while IFS= read -r _pa_line; do
    [ -z "$_pa_line" ] && continue
    local _pa_clean="${_pa_line%: value}"
    local _pa_canonical="${_pa_clean%%|*}"
    _pa_canonical="${_pa_canonical#--}"
    _pa_canonical="${_pa_canonical#-}"
    _pa_canonical="${_pa_canonical//-/_}"
    eval "_arg_${_pa_canonical}=''"
  done <<EOF
$_pa_spec
EOF

  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        show_command_help
        ;;
      --)
        shift
        _pa_passthrough=("$@")
        break
        ;;
      -*)
        if _pa_match_flag "$_pa_spec" "$@"; then
          shift "$_pa_shift_count"
        else
          log_error "Unknown flag: $1"
          exit 1
        fi
        ;;
      *)
        _pa_positional+=("$1")
        shift
        ;;
    esac
  done
}
