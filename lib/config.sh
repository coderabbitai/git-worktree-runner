#!/usr/bin/env bash
# Configuration management via git config
# Default values are defined where they're used in lib/core.sh

# Get a single config value
# Usage: cfg_get key [scope]
# scope: auto (default), local, global, or system
# auto uses git's built-in precedence: local > global > system
cfg_get() {
  local key="$1"
  local scope="${2:-auto}"
  local flag=""

  case "$scope" in
    local)  flag="--local" ;;
    global) flag="--global" ;;
    system) flag="--system" ;;
    auto|*) flag="" ;;
  esac

  git config $flag --get "$key" 2>/dev/null || true
}

# Get all values for a multi-valued config key
# Usage: cfg_get_all key [scope]
# scope: auto (default), local, global, or system
# auto merges local + global + system and deduplicates
cfg_get_all() {
  local key="$1"
  local scope="${2:-auto}"

  case "$scope" in
    local)
      git config --local --get-all "$key" 2>/dev/null || true
      ;;
    global)
      git config --global --get-all "$key" 2>/dev/null || true
      ;;
    system)
      git config --system --get-all "$key" 2>/dev/null || true
      ;;
    auto|*)
      # Merge all levels and deduplicate while preserving order
      {
        git config --local  --get-all "$key" 2>/dev/null || true
        git config --global --get-all "$key" 2>/dev/null || true
        git config --system --get-all "$key" 2>/dev/null || true
      } | awk '!seen[$0]++'
      ;;
  esac
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

  git config $flag --unset-all "$key" 2>/dev/null || true
}

# Get config value with environment variable fallback
# Usage: cfg_default key env_name fallback_value
# Now uses auto scope by default (checks local, global, system)
cfg_default() {
  local key="$1"
  local env_name="$2"
  local fallback="$3"
  local value

  # Try git config first (auto scope - checks local > global > system)
  value=$(cfg_get "$key" auto)

  # Fall back to environment variable (POSIX-compliant indirect reference)
  if [ -z "$value" ] && [ -n "$env_name" ]; then
    eval "value=\${${env_name}:-}"
  fi

  # Use fallback if still empty
  printf "%s" "${value:-$fallback}"
}
