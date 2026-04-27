#!/usr/bin/env bash
# Hook execution system

# ── Hook trust model ────────────────────────────────────────────────────
# Hooks and executable defaults from .gtrconfig files (committed to
# repositories) require explicit user approval before use. This prevents
# malicious contributors from injecting arbitrary commands via shared config
# files.
#
# Trust state is stored in ~/.config/gtr/trusted/<key>
# where <key> is a SHA-256 of the canonical repo root plus trusted content hash.
# Trust is scoped to repo identity + trusted .gtrconfig definitions, not repo
# snapshot state.

_GTR_TRUST_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/gtr/trusted"

# Read all trusted command definitions from a .gtrconfig file.
# Usage: _hooks_read_definitions <config_file>
_hooks_read_definitions() {
  local config_file="$1"
  local hook_content
  hook_content=$(git config -f "$config_file" --get-regexp '^hooks\.|^defaults\.editor$|^defaults\.ai$' 2>/dev/null) || true
  [ -n "$hook_content" ] || return 1
  printf '%s\n' "$hook_content"
}

# Compute a content hash for trusted command definitions.
# Usage: _hooks_content_hash <hook_content>
_hooks_content_hash() {
  local hook_content="$1"
  [ -n "$hook_content" ] || return 1
  printf '%s\n' "$hook_content" | shasum -a 256 | cut -d' ' -f1
}

# Compute a content hash of all current trusted command entries in a .gtrconfig file.
# Usage: _hooks_current_content_hash <config_file>
_hooks_current_content_hash() {
  local config_file="$1"
  local hook_content
  hook_content=$(_hooks_read_definitions "$config_file") || return 1
  _hooks_content_hash "$hook_content"
}

# Backward-compatible alias used by tests and older call sites.
_hooks_file_hash() {
  _hooks_current_content_hash "$1"
}

# Resolve the canonical repository root for a .gtrconfig file
# Usage: _hooks_repo_root <config_file>
_hooks_repo_root() {
  local config_file="$1"
  (
    cd "$(dirname "$config_file")" 2>/dev/null &&
    pwd -P
  )
}

# Resolve the canonical path for a .gtrconfig file
# Usage: _hooks_canonical_config_path <config_file>
_hooks_canonical_config_path() {
  local config_file="$1"
  local repo_root
  repo_root=$(_hooks_repo_root "$config_file") || return 1
  printf '%s/%s\n' "$repo_root" "$(basename "$config_file")"
}

# Compute the repo-scoped trust key for reviewed trusted command content
# Usage: _hooks_reviewed_trust_key <config_file> <hook_content>
_hooks_reviewed_trust_key() {
  local config_file="$1"
  local hook_content="$2"
  local hash repo_root
  hash=$(_hooks_content_hash "$hook_content") || return 1
  repo_root=$(_hooks_repo_root "$config_file") || return 1
  printf '%s\n%s\n' "$repo_root" "$hash" | shasum -a 256 | cut -d' ' -f1
}

# Compute the repo-scoped trust key for the current trusted command content
# Usage: _hooks_current_trust_key <config_file>
_hooks_current_trust_key() {
  local config_file="$1"
  local hook_content
  hook_content=$(_hooks_read_definitions "$config_file") || return 1
  _hooks_reviewed_trust_key "$config_file" "$hook_content"
}

# Backward-compatible alias used by existing call sites.
_hooks_trust_key() {
  _hooks_current_trust_key "$1"
}

# Resolve the trust marker path for reviewed trusted command content
# Usage: _hooks_reviewed_trust_path <config_file> <hook_content>
_hooks_reviewed_trust_path() {
  local config_file="$1"
  local hook_content="$2"
  local trust_key
  trust_key=$(_hooks_reviewed_trust_key "$config_file" "$hook_content") || return 1
  printf '%s/%s\n' "$_GTR_TRUST_DIR" "$trust_key"
}

# Resolve the trust marker path for a .gtrconfig file
# Usage: _hooks_current_trust_path <config_file>
_hooks_current_trust_path() {
  local config_file="$1"
  local trust_key
  trust_key=$(_hooks_current_trust_key "$config_file") || return 1
  printf '%s/%s\n' "$_GTR_TRUST_DIR" "$trust_key"
}

# Backward-compatible aliases used by existing call sites.
_hooks_trust_path() {
  _hooks_current_trust_path "$1"
}

_hooks_trust_path_for_content() {
  _hooks_reviewed_trust_path "$1" "$2"
}

# Check whether a trust marker matches the canonical config path.
# Usage: _hooks_marker_matches_config <trust_path> <config_file>
_hooks_marker_matches_config() {
  local trust_path="$1"
  local config_file="$2"
  local marker_content canonical_config_file

  [ -f "$trust_path" ] || return 1
  marker_content="$(cat "$trust_path" 2>/dev/null)" || return 1
  canonical_config_file=$(_hooks_canonical_config_path "$config_file") || return 1
  [ "$marker_content" = "$canonical_config_file" ]
}

# Check if .gtrconfig command definitions are trusted for the current repository
# Usage: _hooks_are_trusted <config_file>
# Returns: 0 if trusted (or no trusted command definitions), 1 if untrusted
_hooks_are_trusted() {
  local config_file="$1"
  [ ! -f "$config_file" ] && return 0

  local hook_content trust_path
  hook_content=$(_hooks_read_definitions "$config_file") || return 0
  trust_path=$(_hooks_reviewed_trust_path "$config_file" "$hook_content") || return 1
  _hooks_marker_matches_config "$trust_path" "$config_file"
}

# Write a trust marker that matches the reviewed command definitions
# Usage: _hooks_write_trust_marker <trust_path> [config_file]
_hooks_write_trust_marker() {
  local trust_path="$1"
  local config_file="${2:-}"
  local temp_path=""
  local canonical_config_file=""

  mkdir -p "$_GTR_TRUST_DIR" || return 1
  canonical_config_file=$(_hooks_canonical_config_path "$config_file") || return 1
  temp_path="$(mktemp "$_GTR_TRUST_DIR/.trust.XXXXXX")" || return 1

  if ! printf '%s\n' "$canonical_config_file" > "$temp_path"; then
    rm -f "$temp_path"
    return 1
  fi

  if ! mv -f "$temp_path" "$trust_path"; then
    rm -f "$temp_path"
    return 1
  fi
}

# Mark .gtrconfig command definitions as trusted
# Usage: _hooks_mark_trusted <config_file>
_hooks_mark_trusted() {
  local config_file="$1"
  local hook_content trust_path
  hook_content=$(_hooks_read_definitions "$config_file") || return 0
  trust_path=$(_hooks_reviewed_trust_path "$config_file" "$hook_content") || return 1

  _hooks_write_trust_marker "$trust_path" "$config_file"
}

# Get hooks, filtering out untrusted .gtrconfig hooks with a warning
# Usage: _hooks_get_trusted <phase>
_hooks_get_trusted() {
  local phase="$1"

  # Always include hooks from git config (user controls their own .git/config)
  local git_hooks
  git_hooks=$(git config --get-all "gtr.hook.$phase" 2>/dev/null) || true

  # Check .gtrconfig trust before including its hooks
  local config_file
  config_file=$(_gtrconfig_path)
  local file_hooks=""

  if [ -n "$config_file" ] && [ -f "$config_file" ]; then
    if _hooks_are_trusted "$config_file"; then
      file_hooks=$(git config -f "$config_file" --get-all "hooks.$phase" 2>/dev/null) || true
    else
      local untrusted_hooks
      untrusted_hooks=$(git config -f "$config_file" --get-all "hooks.$phase" 2>/dev/null) || true
      if [ -n "$untrusted_hooks" ]; then
        log_warn "Untrusted .gtrconfig hooks for '$phase' phase — skipping"
        log_warn "Review hooks in $config_file, then run: git gtr trust"
      fi
    fi
  fi

  # Merge and deduplicate
  {
    [ -n "$git_hooks" ] && printf '%s\n' "$git_hooks"
    [ -n "$file_hooks" ] && printf '%s\n' "$file_hooks"
  } | awk '!seen[$0]++'
}

# Run hooks for a specific phase
# Usage: run_hooks phase [env_vars...]
# Example: run_hooks postCreate REPO_ROOT="$root" WORKTREE_PATH="$path"
run_hooks() {
  local phase="$1"
  shift

  # Get hooks, filtering untrusted .gtrconfig hooks
  local hooks
  hooks=$(_hooks_get_trusted "$phase")

  if [ -z "$hooks" ]; then
    # No hooks configured for this phase
    return 0
  fi

  log_step "Running $phase hooks..."

  local hook_count=0
  local failed=0

  # Capture environment variable assignments in array to preserve quoting
  local envs=("$@")

  # Execute each hook in a subshell to isolate side effects
  while IFS= read -r hook; do
    [ -z "$hook" ] && continue

    hook_count=$((hook_count + 1))
    log_info "Hook $hook_count: $hook"

    # Run hook in subshell with properly quoted environment exports
    if (
      # Export each KEY=VALUE exactly as passed, safely quoted
      for kv in "${envs[@]}"; do
        # shellcheck disable=SC2163
        export "$kv"
      done
      # Execute the hook
      eval "$hook"
    ) </dev/null; then
      log_info "Hook $hook_count completed successfully"
    else
      local rc=$?
      log_error "Hook $hook_count failed with exit code $rc"
      failed=$((failed + 1))
    fi
  done <<EOF
$hooks
EOF

  if [ "$failed" -gt 0 ]; then
    log_warn "$failed hook(s) failed"
    return 1
  fi

  return 0
}

# Run hooks in a specific directory
# Usage: run_hooks_in phase directory [env_vars...]
run_hooks_in() {
  local phase="$1"
  local directory="$2"
  shift 2

  local old_pwd
  old_pwd=$(pwd)

  if [ ! -d "$directory" ]; then
    log_error "Directory does not exist: $directory"
    return 1
  fi

  cd "$directory" || return 1

  run_hooks "$phase" "$@"
  local result=$?

  cd "$old_pwd" || return 1

  return $result
}

# Run hooks in current shell without subshell isolation
# Env vars set by hooks (e.g., source ./vars.sh) persist in the calling shell.
# IMPORTANT: Call from within a subshell to avoid polluting the main script.
# Usage: run_hooks_export phase [env_vars...]
# Example: ( cd "$dir" && run_hooks_export postCd REPO_ROOT="$root" )
run_hooks_export() {
  local phase="$1"
  shift

  local hooks
  hooks=$(_hooks_get_trusted "$phase")

  if [ -z "$hooks" ]; then
    return 0
  fi

  log_step "Running $phase hooks..."

  # Export env vars so hooks and child processes can see them
  local kv
  for kv in "$@"; do
    # shellcheck disable=SC2163
    export "$kv"
  done

  local hook_count=0
  while IFS= read -r hook; do
    [ -z "$hook" ] && continue

    hook_count=$((hook_count + 1))
    log_info "Hook $hook_count: $hook"

    # eval directly (no subshell) so exports persist
    eval "$hook" </dev/null || log_warn "Hook $hook_count failed (continuing)"
  done <<EOF
$hooks
EOF
}
