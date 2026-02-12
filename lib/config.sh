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

# Single source of truth for gtr.* <-> .gtrconfig key mapping
# Format: "gtr_key|file_key" — add new config keys here only
_CFG_KEY_MAP=(
  "gtr.copy.include|copy.include"
  "gtr.copy.exclude|copy.exclude"
  "gtr.copy.includeDirs|copy.includeDirs"
  "gtr.copy.excludeDirs|copy.excludeDirs"
  "gtr.hook.postCreate|hooks.postCreate"
  "gtr.hook.preRemove|hooks.preRemove"
  "gtr.hook.postRemove|hooks.postRemove"
  "gtr.hook.postCd|hooks.postCd"
  "gtr.editor.default|defaults.editor"
  "gtr.editor.workspace|editor.workspace"
  "gtr.ai.default|defaults.ai"
  "gtr.worktrees.dir|worktrees.dir"
  "gtr.worktrees.prefix|worktrees.prefix"
  "gtr.defaultBranch|defaults.branch"
  "gtr.provider|defaults.provider"
)

# Map a gtr.* config key to its .gtrconfig equivalent
# Usage: cfg_map_to_file_key <key>
# Returns: mapped key for .gtrconfig or empty if no mapping exists
cfg_map_to_file_key() {
  local pair
  for pair in "${_CFG_KEY_MAP[@]}"; do
    if [ "${pair%%|*}" = "$1" ]; then
      echo "${pair#*|}"
      return
    fi
  done
}

# Map a .gtrconfig key to its gtr.* config equivalent (reverse of cfg_map_to_file_key)
# Usage: cfg_map_from_file_key <file_key>
# Returns: mapped gtr.* key, or empty if no mapping exists
cfg_map_from_file_key() {
  local pair
  for pair in "${_CFG_KEY_MAP[@]}"; do
    if [ "${pair#*|}" = "$1" ]; then
      echo "${pair%%|*}"
      return
    fi
  done
  # Passthrough for gtr.* keys already in canonical form
  case "$1" in gtr.*) echo "$1" ;; esac
}

# Check if a key is a recognized gtr.* config key
# Usage: _cfg_is_known_key <key>
# Returns: 0 if known, 1 if not
_cfg_is_known_key() {
  local pair
  for pair in "${_CFG_KEY_MAP[@]}"; do
    [ "${pair%%|*}" = "$1" ] && return 0
  done
  return 1
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

# Convert scope name to git config flag
# Usage: _cfg_scope_flag <scope>
# Returns: --local, --global, or --system
_cfg_scope_flag() {
  case "${1:-local}" in
    --global|global) echo "--global" ;;
    --system|system) echo "--system" ;;
    *)               echo "--local" ;;
  esac
}

# Set a config value
# Usage: cfg_set key value [scope]
cfg_set() {
  local flag
  flag=$(_cfg_scope_flag "${3:-local}")
  # shellcheck disable=SC2086
  git config $flag "$1" "$2"
}

# Add a value to a multi-valued config key
# Usage: cfg_add key value [scope]
cfg_add() {
  local flag
  flag=$(_cfg_scope_flag "${3:-local}")
  # shellcheck disable=SC2086
  git config $flag --add "$1" "$2"
}

# Unset a config value
# Usage: cfg_unset key [scope]
cfg_unset() {
  local flag
  flag=$(_cfg_scope_flag "${2:-local}")
  # shellcheck disable=SC2086
  git config $flag --unset-all "$1" 2>/dev/null || true
}

# ── cfg_list helpers ──────────────────────────────────────────────────
# Module-level state for cfg_list auto-mode deduplication.
# Reset by cfg_list() at the start of each "auto" invocation.
_cfg_list_seen=""
_cfg_list_result=""

# Add a config entry, deduplicating by key+value combo.
# Uses Unit Separator ($'\x1f') as delimiter to avoid collision with any value content.
# Usage: _cfg_list_add_entry <origin> <key> <value>
_cfg_list_add_entry() {
  local origin="$1" entry_key="$2" entry_value="$3"
  local id=$'\x1f'"${entry_key}=${entry_value}"$'\x1f'

  # Use [[ ]] for literal string matching (no glob interpretation)
  if [[ "$_cfg_list_seen" == *"$id"* ]]; then
    return 0
  fi

  _cfg_list_seen="${_cfg_list_seen}${id}"
  _cfg_list_result="${_cfg_list_result}${entry_key}"$'\x1f'"${entry_value}"$'\x1f'"${origin}"$'\n'
}

# Parse git config --get-regexp output and add each entry with an origin label.
# Usage: _cfg_list_parse_entries <origin> <get-regexp-output>
_cfg_list_parse_entries() {
  local origin="$1" entries="$2"
  local line key value
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    key="${line%% *}"
    if [[ "$line" == *" "* ]]; then
      value="${line#* }"
    else
      value=""
    fi
    _cfg_list_add_entry "$origin" "$key" "$value"
  done <<< "$entries"
}

# Format cfg_list output with alignment.
# Detects auto-mode (Unit Separator delimited with origin) vs scoped (space delimited).
# Usage: _cfg_list_format <output>
_cfg_list_format() {
  local output="$1"
  if [ -z "$output" ]; then
    echo "No gtr configuration found"
    return 0
  fi

  printf '%s\n' "$output" | while IFS= read -r line; do
    [ -z "$line" ] && continue

    local key value origin rest
    if [[ "$line" == *$'\x1f'* ]]; then
      # Auto-mode format: key<US>value<US>origin
      key="${line%%$'\x1f'*}"
      rest="${line#*$'\x1f'}"
      value="${rest%%$'\x1f'*}"
      origin="${rest#*$'\x1f'}"
      printf "%-35s = %-25s [%s]\n" "$key" "$value" "$origin"
    else
      # Scoped format: key value (no origin)
      key="${line%% *}"
      if [[ "$line" == *" "* ]]; then
        value="${line#* }"
      else
        value=""
      fi
      printf "%-35s = %s\n" "$key" "$value"
    fi
  done
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
      # Reset module-level state for this invocation
      _cfg_list_seen=""
      _cfg_list_result=""
      local key value line

      # Process in priority order: local > .gtrconfig > global > system
      _cfg_list_parse_entries "local" \
        "$(git config --local --get-regexp '^gtr\.' 2>/dev/null || true)"

      # .gtrconfig needs key remapping from file format to gtr.* format
      if [ -n "$config_file" ] && [ -f "$config_file" ]; then
        while IFS= read -r line; do
          [ -z "$line" ] && continue
          local fkey mapped_key
          fkey="${line%% *}"
          if [[ "$line" == *" "* ]]; then
            value="${line#* }"
          else
            value=""
          fi
          mapped_key=$(cfg_map_from_file_key "$fkey")
          [ -z "$mapped_key" ] && continue
          _cfg_list_add_entry ".gtrconfig" "$mapped_key" "$value"
        done < <(git config -f "$config_file" --get-regexp '.' 2>/dev/null || true)
      fi

      _cfg_list_parse_entries "global" \
        "$(git config --global --get-regexp '^gtr\.' 2>/dev/null || true)"
      _cfg_list_parse_entries "system" \
        "$(git config --system --get-regexp '^gtr\.' 2>/dev/null || true)"

      output="$_cfg_list_result"
      ;;
    *)
      log_warn "Unknown scope '$scope', using 'auto'"
      cfg_list "auto"
      return $?
      ;;
  esac

  _cfg_list_format "$output"
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
