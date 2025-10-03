#!/bin/sh
# Configuration management via git config
# Default values are defined where they're used in lib/core.sh

# Get a single config value
# Usage: cfg_get key [scope]
# scope: local (default), global, or system
cfg_get() {
  local key="$1"
  local scope="${2:-local}"
  local flag=""

  case "$scope" in
    global) flag="--global" ;;
    system) flag="--system" ;;
    local|*) flag="--local" ;;
  esac

  git config $flag "$key" 2>/dev/null || true
}

# Get all values for a multi-valued config key
# Usage: cfg_get_all key [scope]
cfg_get_all() {
  local key="$1"
  local scope="${2:-local}"
  local flag=""

  case "$scope" in
    global) flag="--global" ;;
    system) flag="--system" ;;
    local|*) flag="--local" ;;
  esac

  git config $flag --get-all "$key" 2>/dev/null || true
}

# Get a boolean config value
# Usage: cfg_bool key [default]
# Returns: 0 for true, 1 for false
cfg_bool() {
  local key="$1"
  local default="${2:-false}"
  local value

  value=$(cfg_get "$key")

  if [ -z "$value" ]; then
    value="$default"
  fi

  case "$value" in
    true|yes|1|on)
      return 0
      ;;
    false|no|0|off|*)
      return 1
      ;;
  esac
}

# Set a config value
# Usage: cfg_set key value [--global]
cfg_set() {
  local key="$1"
  local value="$2"
  local scope="${3:-local}"
  local flag=""

  case "$scope" in
    --global|global) flag="--global" ;;
    --system|system) flag="--system" ;;
    --local|local|*) flag="--local" ;;
  esac

  git config $flag "$key" "$value"
}

# Add a value to a multi-valued config key
# Usage: cfg_add key value [--global]
cfg_add() {
  local key="$1"
  local value="$2"
  local scope="${3:-local}"
  local flag=""

  case "$scope" in
    --global|global) flag="--global" ;;
    --system|system) flag="--system" ;;
    --local|local|*) flag="--local" ;;
  esac

  git config $flag --add "$key" "$value"
}

# Unset a config value
# Usage: cfg_unset key [--global]
cfg_unset() {
  local key="$1"
  local scope="${2:-local}"
  local flag=""

  case "$scope" in
    --global|global) flag="--global" ;;
    --system|system) flag="--system" ;;
    --local|local|*) flag="--local" ;;
  esac

  git config $flag --unset "$key" 2>/dev/null || true
}

# Get config value with environment variable fallback
# Usage: cfg_default key env_name fallback_value
cfg_default() {
  local key="$1"
  local env_name="$2"
  local fallback="$3"
  local value

  # Try git config first
  value=$(cfg_get "$key")

  # Fall back to environment variable
  if [ -z "$value" ] && [ -n "$env_name" ]; then
    value=$(eval echo "\$$env_name")
  fi

  # Use fallback if still empty
  if [ -z "$value" ]; then
    value="$fallback"
  fi

  printf "%s" "$value"
}
