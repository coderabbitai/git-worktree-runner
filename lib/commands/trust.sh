#!/usr/bin/env bash
# Trust management for .gtrconfig hooks

cmd_trust() {
  local config_file
  config_file=$(_gtrconfig_path)

  if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
    log_info "No .gtrconfig file found in this repository"
    return 0
  fi

  # Show all hook entries from .gtrconfig
  local hook_content
  hook_content=$(git config -f "$config_file" --get-regexp '^hooks\.' 2>/dev/null) || true

  if [ -z "$hook_content" ]; then
    log_info "No hooks defined in $config_file"
    return 0
  fi

  if _hooks_are_trusted "$config_file"; then
    log_info "Hooks in $config_file are already trusted"
    log_info "Current hooks:"
    printf '%s\n' "$hook_content" >&2
    return 0
  fi

  log_warn "The following hooks are defined in $config_file:"
  echo "" >&2
  printf '%s\n' "$hook_content" >&2
  echo "" >&2
  log_warn "These commands will execute on your machine during gtr operations."

  if prompt_yes_no "Trust these hooks?"; then
    if _hooks_mark_trusted "$config_file"; then
      log_info "Hooks marked as trusted"
    else
      log_error "Failed to mark hooks as trusted"
      return 1
    fi
  else
    log_info "Hooks remain untrusted and will not execute"
  fi
}
