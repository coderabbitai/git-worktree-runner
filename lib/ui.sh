#!/usr/bin/env bash
# UI utilities for logging and prompting

log_info() {
  printf "[OK] %s\n" "$*" >&2
}

log_warn() {
  printf "[!] %s\n" "$*" >&2
}

log_error() {
  printf "[x] %s\n" "$*" >&2
}

log_step() {
  printf "==> %s\n" "$*" >&2
}

log_question() {
  printf "[?] %s" "$*"
}

# Prompt for yes/no confirmation
# Usage: prompt_yes_no "Question text" [default]
# Returns: 0 for yes, 1 for no
prompt_yes_no() {
  local question="$1"
  local default="${2:-n}"
  local prompt_suffix="[y/N]"

  if [ "$default" = "y" ]; then
    prompt_suffix="[Y/n]"
  fi

  log_question "$question $prompt_suffix "
  read -r reply

  case "$reply" in
    [yY]|[yY][eE][sS])
      return 0
      ;;
    [nN]|[nN][oO])
      return 1
      ;;
    "")
      [ "$default" = "y" ] && return 0 || return 1
      ;;
    *)
      [ "$default" = "y" ] && return 0 || return 1
      ;;
  esac
}

# Prompt for text input
# Usage: prompt_input "Question text" [variable_name]
# If variable_name provided, sets it, otherwise echoes result
prompt_input() {
  local question="$1"
  local var_name="$2"

  log_question "$question "
  read -r input

  if [ -n "$var_name" ]; then
    eval "$var_name=\"\$input\""
  else
    printf "%s" "$input"
  fi
}
