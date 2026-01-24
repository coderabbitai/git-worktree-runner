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

# Map a gtr.* config key to its .gtrconfig equivalent
# Usage: cfg_map_to_file_key <key>
# Returns: mapped key for .gtrconfig or empty if no mapping exists
cfg_map_to_file_key() {
  local key="$1"
  case "$key" in
    gtr.copy.include)     echo "copy.include" ;;
    gtr.copy.exclude)     echo "copy.exclude" ;;
    gtr.copy.includeDirs) echo "copy.includeDirs" ;;
    gtr.copy.excludeDirs) echo "copy.excludeDirs" ;;
    gtr.hook.postCreate)  echo "hooks.postCreate" ;;
    gtr.hook.preRemove)   echo "hooks.preRemove" ;;
    gtr.hook.postRemove)  echo "hooks.postRemove" ;;
    gtr.editor.default)   echo "defaults.editor" ;;
    gtr.editor.workspace) echo "editor.workspace" ;;
    gtr.ai.default)       echo "defaults.ai" ;;
    gtr.worktrees.dir)    echo "worktrees.dir" ;;
    gtr.worktrees.prefix) echo "worktrees.prefix" ;;
    gtr.defaultBranch)    echo "defaults.branch" ;;
    *)                    echo "" ;;
  esac
}

# Get all values for a multi-valued config key
# Usage: cfg_get_all key [file_key] [scope]
# file_key: optional key name in .gtrconfig (e.g., "copy.include" for gtr.copy.include)
#           If empty and key starts with "gtr.", auto-maps to .gtrconfig key
# scope: auto (default), local, global, or system
# auto merges local + .gtrconfig + global + system and deduplicates
cfg_get_all() {
  local key="$1"
  local file_key="${2:-}"
  local scope="${3:-auto}"

  # Auto-map file_key if not provided and key is a gtr.* key
  if [ -z "$file_key" ] && [[ "$key" == gtr.* ]]; then
    file_key=$(cfg_map_to_file_key "$key")
  fi

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

# List all gtr.* config values
# Usage: cfg_list [scope]
# scope: auto (default), local, global, system
# auto shows merged config from all sources with origin labels
# Returns formatted key = value output, or message if empty
# Note: Shows ALL values for multi-valued keys (copy patterns, hooks, etc.)
cfg_list() {
  local scope="${1:-auto}"
  local output=""
  local config_file
  config_file=$(_gtrconfig_path)

  case "$scope" in
    local)
      output=$(git config --local --get-regexp '^gtr\.' 2>/dev/null || true)
      ;;
    global)
      output=$(git config --global --get-regexp '^gtr\.' 2>/dev/null || true)
      ;;
    system)
      output=$(git config --system --get-regexp '^gtr\.' 2>/dev/null || true)
      ;;
    auto)
      # Merge all sources with origin labels
      # Deduplicates by key+value combo, preserving all multi-values from highest priority source
      local seen_keys=""
      local result=""
      local key value line

      # Set up cleanup trap for helper function (protects against early exit/return)
      trap 'unset -f _cfg_list_add_entry 2>/dev/null' RETURN

      # Helper function to add entries with origin (inline to avoid Bash 3.2 nameref issues)
      # Uses Unit Separator ($'\x1f') as delimiter to avoid conflicts with any values
      _cfg_list_add_entry() {
        local origin="$1"
        local entry_key="$2"
        local entry_value="$3"

        # For multi-valued keys: check if key+value combo already seen
        # This allows multiple values for the same key from the same source
        # Use Unit Separator as delimiter in seen_keys to avoid collision with any value content
        local id=$'\x1f'"${entry_key}=${entry_value}"$'\x1f'
        # Use [[ ]] for literal string matching (no glob interpretation)
        if [[ "$seen_keys" == *"$id"* ]]; then
          return 0
        fi

        seen_keys="${seen_keys}${id}"
        # Use Unit Separator ($'\x1f') as delimiter - won't appear in normal values
        result="${result}${entry_key}"$'\x1f'"${entry_value}"$'\x1f'"${origin}"$'\n'
      }

      # Process in priority order: local > .gtrconfig > global > system
      local local_entries global_entries system_entries

      # 1. Local git config (highest priority)
      local_entries=$(git config --local --get-regexp '^gtr\.' 2>/dev/null || true)
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        key="${line%% *}"
        # Handle empty values (no space in line means value is empty)
        if [[ "$line" == *" "* ]]; then
          value="${line#* }"
        else
          value=""
        fi
        _cfg_list_add_entry "local" "$key" "$value"
      done <<< "$local_entries"

      # 2. .gtrconfig file (team defaults)
      if [ -n "$config_file" ] && [ -f "$config_file" ]; then
        while IFS= read -r line; do
          [ -z "$line" ] && continue
          local fkey fvalue mapped_key
          fkey="${line%% *}"
          # Handle empty values (no space in line means value is empty)
          if [[ "$line" == *" "* ]]; then
            fvalue="${line#* }"
          else
            fvalue=""
          fi
          # Map .gtrconfig keys to gtr.* format
          case "$fkey" in
            copy.include)     mapped_key="gtr.copy.include" ;;
            copy.exclude)     mapped_key="gtr.copy.exclude" ;;
            copy.includeDirs) mapped_key="gtr.copy.includeDirs" ;;
            copy.excludeDirs) mapped_key="gtr.copy.excludeDirs" ;;
            hooks.postCreate) mapped_key="gtr.hook.postCreate" ;;
            hooks.preRemove)  mapped_key="gtr.hook.preRemove" ;;
            hooks.postRemove) mapped_key="gtr.hook.postRemove" ;;
            defaults.editor)  mapped_key="gtr.editor.default" ;;
            editor.workspace) mapped_key="gtr.editor.workspace" ;;
            defaults.ai)      mapped_key="gtr.ai.default" ;;
            defaults.branch)  mapped_key="gtr.defaultBranch" ;;
            worktrees.dir)    mapped_key="gtr.worktrees.dir" ;;
            worktrees.prefix) mapped_key="gtr.worktrees.prefix" ;;
            gtr.*)            mapped_key="$fkey" ;;
            *)                continue ;;  # Skip unmapped keys
          esac
          _cfg_list_add_entry ".gtrconfig" "$mapped_key" "$fvalue"
        done < <(git config -f "$config_file" --get-regexp '.' 2>/dev/null || true)
      fi

      # 3. Global git config
      global_entries=$(git config --global --get-regexp '^gtr\.' 2>/dev/null || true)
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        key="${line%% *}"
        # Handle empty values (no space in line means value is empty)
        if [[ "$line" == *" "* ]]; then
          value="${line#* }"
        else
          value=""
        fi
        _cfg_list_add_entry "global" "$key" "$value"
      done <<< "$global_entries"

      # 4. System git config (lowest priority)
      system_entries=$(git config --system --get-regexp '^gtr\.' 2>/dev/null || true)
      while IFS= read -r line; do
        [ -z "$line" ] && continue
        key="${line%% *}"
        # Handle empty values (no space in line means value is empty)
        if [[ "$line" == *" "* ]]; then
          value="${line#* }"
        else
          value=""
        fi
        _cfg_list_add_entry "system" "$key" "$value"
      done <<< "$system_entries"

      # Clean up helper function and clear trap (trap handles early exit cases)
      unset -f _cfg_list_add_entry
      trap - RETURN

      output="$result"
      ;;
    *)
      # Unknown scope - warn and fall back to auto
      log_warn "Unknown scope '$scope', using 'auto'"
      cfg_list "auto"
      return $?
      ;;
  esac

  # Format and display output
  if [ -z "$output" ]; then
    echo "No gtr configuration found"
    return 0
  fi

  # Format output with alignment
  # Use printf '%s\n' instead of echo for safety with special characters
  printf '%s\n' "$output" | while IFS= read -r line; do
    [ -z "$line" ] && continue

    local key value origin rest
    # Check if line uses Unit Separator delimiter (auto mode with origin)
    if [[ "$line" == *$'\x1f'* ]]; then
      # Format: key<US>value<US>origin
      key="${line%%$'\x1f'*}"
      rest="${line#*$'\x1f'}"
      value="${rest%%$'\x1f'*}"
      origin="${rest#*$'\x1f'}"
      printf "%-35s = %-25s [%s]\n" "$key" "$value" "$origin"
    else
      # Format: key value (no origin, for scoped queries)
      key="${line%% *}"
      # Handle empty values (no space in line means value is empty)
      if [[ "$line" == *" "* ]]; then
        value="${line#* }"
      else
        value=""
      fi
      printf "%-35s = %s\n" "$key" "$value"
    fi
  done
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

  # Auto-map file_key if not provided and key is a gtr.* key
  if [ -z "$file_key" ] && [[ "$key" == gtr.* ]]; then
    file_key=$(cfg_map_to_file_key "$key")
  fi

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
