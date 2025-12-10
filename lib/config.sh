#!/usr/bin/env bash
# Configuration management via git config and .gtrconfig file
# Default values are defined where they're used in lib/core.sh
#
# Configuration precedence (highest to lowest):
# 1. git config --local (.git/config)
# 2. .gtrconfig file (repo root) - team defaults
# 3. git config --global (~/.gitconfig)
# 4. git config --system (/etc/gitconfig)
# 5. Environment variables
# 6. Fallback values

# Get the path to .gtrconfig file in main repo root
# Usage: _gtrconfig_path
# Returns: path to .gtrconfig or empty if not in a repo
# Note: Uses --git-common-dir to find main repo even from worktrees
_gtrconfig_path() {
  local git_common_dir repo_root
  git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null) || return 0

  # git-common-dir returns:
  # - ".git" when in main repo (relative)
  # - "/absolute/path/to/repo/.git" when in worktree (absolute)
  if [ "$git_common_dir" = ".git" ]; then
    # In main repo - use show-toplevel
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
  else
    # In worktree - strip /.git suffix from absolute path
    repo_root="${git_common_dir%/.git}"
  fi

  printf "%s/.gtrconfig" "$repo_root"
}

# Get a single config value from .gtrconfig file
# Usage: cfg_get_file key
# Returns: value or empty string
cfg_get_file() {
  local key="$1"
  local config_file
  config_file=$(_gtrconfig_path)

  if [ -n "$config_file" ] && [ -f "$config_file" ]; then
    git config -f "$config_file" --get "$key" 2>/dev/null || true
  fi
}

# Get all values for a multi-valued key from .gtrconfig file
# Usage: cfg_get_all_file key
# Returns: newline-separated values or empty string
cfg_get_all_file() {
  local key="$1"
  local config_file
  config_file=$(_gtrconfig_path)

  if [ -n "$config_file" ] && [ -f "$config_file" ]; then
    git config -f "$config_file" --get-all "$key" 2>/dev/null || true
  fi
}

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
# Usage: cfg_get_all key [file_key] [scope]
# file_key: optional key name in .gtrconfig (e.g., "copy.include" for gtr.copy.include)
# scope: auto (default), local, global, or system
# auto merges local + .gtrconfig + global + system and deduplicates
cfg_get_all() {
  local key="$1"
  local file_key="${2:-}"
  local scope="${3:-auto}"

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
      # Precedence: local > .gtrconfig > global > system
      {
        git config --local  --get-all "$key" 2>/dev/null || true
        if [ -n "$file_key" ]; then
          cfg_get_all_file "$file_key"
        fi
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
# Usage: cfg_default key env_name fallback_value [file_key]
# file_key: optional key name in .gtrconfig (e.g., "defaults.editor" for gtr.editor.default)
# Precedence: local config > .gtrconfig > global/system config > env var > fallback
cfg_default() {
  local key="$1"
  local env_name="$2"
  local fallback="$3"
  local file_key="${4:-}"
  local value

  # 1. Try local git config first (highest priority)
  value=$(git config --local --get "$key" 2>/dev/null || true)

  # 2. Try .gtrconfig file
  if [ -z "$value" ] && [ -n "$file_key" ]; then
    value=$(cfg_get_file "$file_key")
  fi

  # 3. Try global/system git config
  if [ -z "$value" ]; then
    value=$(git config --get "$key" 2>/dev/null || true)
  fi

  # 4. Fall back to environment variable (POSIX-compliant indirect reference)
  if [ -z "$value" ] && [ -n "$env_name" ]; then
    eval "value=\${${env_name}:-}"
  fi

  # 5. Use fallback if still empty
  printf "%s" "${value:-$fallback}"
}
