#!/usr/bin/env bash
# UI utilities for logging and prompting

# ── Color support ────────────────────────────────────────────────────────────
# Color variables — empty when disabled, ANSI codes when enabled.
# Pre-computed once at source time; zero per-call overhead.
_UI_GREEN="" _UI_YELLOW="" _UI_RED="" _UI_CYAN=""
_UI_BOLD="" _UI_RESET=""
_UI_BOLD_STDOUT="" _UI_RESET_STDOUT=""

# Check if color output should be enabled for a file descriptor
# Respects: NO_COLOR (no-color.org), GTR_COLOR env, TTY detection
# Usage: _ui_should_color <fd>
_ui_should_color() {
  [ -n "${NO_COLOR:-}" ] && return 1
  case "${GTR_COLOR:-auto}" in
    always) return 0 ;;
    never)  return 1 ;;
  esac
  [ -t "$1" ]
}

_ui_enable_color() {
  _UI_GREEN=$(printf '\033[0;32m')
  _UI_YELLOW=$(printf '\033[0;33m')
  _UI_RED=$(printf '\033[0;31m')
  _UI_CYAN=$(printf '\033[0;36m')
  _UI_BOLD=$(printf '\033[1m')
  _UI_RESET=$(printf '\033[0m')
  _UI_BOLD_STDOUT="$_UI_BOLD"
  _UI_RESET_STDOUT="$_UI_RESET"
}

_ui_disable_color() {
  _UI_GREEN="" _UI_YELLOW="" _UI_RED="" _UI_CYAN=""
  _UI_BOLD="" _UI_RESET=""
  _UI_BOLD_STDOUT="" _UI_RESET_STDOUT=""
}

# Phase 1: auto-detect color at source time (before config.sh is available)
if _ui_should_color 2; then
  _UI_GREEN=$(printf '\033[0;32m')
  _UI_YELLOW=$(printf '\033[0;33m')
  _UI_RED=$(printf '\033[0;31m')
  _UI_CYAN=$(printf '\033[0;36m')
  _UI_BOLD=$(printf '\033[1m')
  _UI_RESET=$(printf '\033[0m')
fi
if _ui_should_color 1; then
  _UI_BOLD_STDOUT=$(printf '\033[1m')
  _UI_RESET_STDOUT=$(printf '\033[0m')
fi

# Phase 2: re-evaluate after config.sh is available
# Called from bin/gtr after config.sh is sourced
_ui_apply_color_config() {
  # NO_COLOR always wins, regardless of config
  if [ -n "${NO_COLOR:-}" ]; then
    _ui_disable_color
    return 0
  fi
  local color_mode
  color_mode=$(cfg_get "gtr.ui.color") || true
  [ -z "$color_mode" ] && return 0
  case "$color_mode" in
    always) _ui_enable_color ;;
    never)  _ui_disable_color ;;
  esac
}

# ── Logging functions ────────────────────────────────────────────────────────

log_info() {
  printf "%s[OK]%s %s\n" "$_UI_GREEN" "$_UI_RESET" "$*" >&2
}

log_warn() {
  printf "%s[!]%s %s\n" "$_UI_YELLOW" "$_UI_RESET" "$*" >&2
}

log_error() {
  printf "%s[x]%s %s\n" "$_UI_RED" "$_UI_RESET" "$*" >&2
}

log_step() {
  printf "%s==>%s %s\n" "${_UI_BOLD}${_UI_CYAN}" "$_UI_RESET" "$*" >&2
}

log_question() {
  printf "%s[?]%s %s" "$_UI_BOLD_STDOUT" "$_UI_RESET_STDOUT" "$*"
}

# ── Help and prompts ─────────────────────────────────────────────────────────

# Show help for the current command and exit (called by parse_args on --help)
show_command_help() {
  cmd_help "${_GTR_CURRENT_COMMAND:-}"
  exit 0
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
