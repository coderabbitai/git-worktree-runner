#!/usr/bin/env bash

# Config command
cmd_config() {
  local scope="auto"
  local action="" key="" value=""
  local extra_args=""

  # Parse args flexibly: action, key, value, and --global/--local anywhere
  while [ $# -gt 0 ]; do
    case "$1" in
      --global|global)
        scope="global"
        shift
        ;;
      --local|local)
        scope="local"
        shift
        ;;
      --system|system)
        scope="system"
        shift
        ;;
      get|set|unset|add|list)
        action="$1"
        shift
        ;;
      *)
        if [ -z "$key" ]; then
          key="$1"
          shift
        elif [ -z "$value" ] && { [ "$action" = "set" ] || [ "$action" = "add" ]; }; then
          value="$1"
          shift
        else
          # Track extra tokens for validation (add space only if not first)
          extra_args="${extra_args:+$extra_args }$1"
          shift
        fi
        ;;
    esac
  done

  # Default action: list if no action and no key, otherwise get
  if [ -z "$action" ]; then
    if [ -z "$key" ]; then
      action="list"
    else
      action="get"
    fi
  fi

  # Resolve "auto" scope to "local" for set/add/unset operations (they need explicit scope)
  # This ensures log messages show the actual scope being used
  local resolved_scope="$scope"
  if [ "$scope" = "auto" ] && [ "$action" != "list" ] && [ "$action" != "get" ]; then
    resolved_scope="local"
  fi

  # Reject --system for write operations (requires root, not commonly useful)
  if [ "$scope" = "system" ]; then
    case "$action" in
      set|add|unset)
        log_error "--system is not supported for write operations (requires root privileges)"
        log_error "Use --local or --global instead"
        exit 1
        ;;
    esac
  fi

  case "$action" in
    get)
      if [ -z "$key" ]; then
        log_error "Usage: git gtr config get <key> [--local|--global|--system]"
        exit 1
      fi
      # Warn on unexpected extra arguments
      if [ -n "$extra_args" ]; then
        log_warn "get action: ignoring extra arguments: $extra_args"
      fi
      cfg_get_all "$key" "" "$scope"
      ;;
    set)
      if [ -z "$key" ] || [ -z "$value" ]; then
        log_error "Usage: git gtr config set <key> <value> [--local|--global]"
        exit 1
      fi
      # Warn on unexpected extra arguments
      if [ -n "$extra_args" ]; then
        log_warn "set action: ignoring extra arguments: $extra_args"
      fi
      if ! _cfg_is_known_key "$key"; then
        log_warn "Unknown config key: $key (not a recognized gtr.* key)"
      fi
      cfg_set "$key" "$value" "$resolved_scope"
      log_info "Config set: $key = $value ($resolved_scope)"
      ;;
    add)
      if [ -z "$key" ] || [ -z "$value" ]; then
        log_error "Usage: git gtr config add <key> <value> [--local|--global]"
        exit 1
      fi
      # Warn on unexpected extra arguments
      if [ -n "$extra_args" ]; then
        log_warn "add action: ignoring extra arguments: $extra_args"
      fi
      if ! _cfg_is_known_key "$key"; then
        log_warn "Unknown config key: $key (not a recognized gtr.* key)"
      fi
      cfg_add "$key" "$value" "$resolved_scope"
      log_info "Config added: $key = $value ($resolved_scope)"
      ;;
    unset)
      if [ -z "$key" ]; then
        log_error "Usage: git gtr config unset <key> [--local|--global]"
        exit 1
      fi
      # Warn on unexpected extra arguments (including value which unset doesn't use)
      if [ -n "$value" ] || [ -n "$extra_args" ]; then
        log_warn "unset action: ignoring extra arguments: ${value}${value:+ }${extra_args}"
      fi
      if ! _cfg_is_known_key "$key"; then
        log_warn "Unknown config key: $key (not a recognized gtr.* key)"
      fi
      cfg_unset "$key" "$resolved_scope"
      log_info "Config unset: $key ($resolved_scope)"
      ;;
    list)
      # Warn on unexpected extra arguments
      if [ -n "$key" ] || [ -n "$extra_args" ]; then
        log_warn "list action doesn't accept additional arguments (ignoring: ${key}${key:+ }${extra_args})"
      fi
      # Use cfg_list for proper formatting and .gtrconfig support
      cfg_list "$scope"
      ;;
    *)
      log_error "Unknown config action: $action"
      log_error "Usage: git gtr config [list] [--local|--global|--system]"
      log_error "       git gtr config {get|set|add|unset} <key> [value] [--local|--global]"
      exit 1
      ;;
  esac
}