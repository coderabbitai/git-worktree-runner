#!/usr/bin/env bash
# Trust management for executable .gtrconfig commands

cmd_trust() {
  local config_file
  config_file=$(_gtrconfig_path)

  if [ -z "$config_file" ] || [ ! -f "$config_file" ]; then
    log_info "No .gtrconfig file found in this repository"
    return 0
  fi

  # Show all trusted command entries from .gtrconfig
  local hook_content
  hook_content=$(_hooks_read_definitions "$config_file") || true

  if [ -z "$hook_content" ]; then
    log_info "No hooks or executable defaults defined in $config_file"
    return 0
  fi

  if _hooks_are_trusted "$config_file"; then
    log_info "Executable commands in $config_file are already trusted"
    log_info "Current trusted commands:"
    printf '%s\n' "$hook_content" >&2
    return 0
  fi

  local trust_path
  trust_path=$(_hooks_reviewed_trust_path "$config_file" "$hook_content") || {
    log_error "Failed to compute trust marker for $config_file"
    return 1
  }

  log_warn "The following executable commands are defined in $config_file:"
  echo "" >&2
  printf '%s\n' "$hook_content" >&2
  echo "" >&2
  log_warn "These commands will execute on your machine during gtr operations."

  if prompt_yes_no "Trust these commands?"; then
    if _hooks_write_trust_marker "$trust_path" "$config_file"; then
      local current_trust_path
      current_trust_path=$(_hooks_current_trust_path "$config_file") || true
      if [ -n "$current_trust_path" ] && [ "$current_trust_path" != "$trust_path" ]; then
        log_warn "Executable commands changed during review; current commands remain untrusted"
        return 1
      fi
      log_info "Executable commands marked as trusted"
    else
      log_error "Failed to mark executable commands as trusted"
      return 1
    fi
  else
    log_info "Executable commands remain untrusted and will not run from .gtrconfig"
  fi
}
