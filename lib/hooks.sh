#!/usr/bin/env bash
# Hook execution system

# Hook dispatch can enter a different linked worktree after CLI startup.
# shellcheck source=lib/config_safety.sh
. "${BASH_SOURCE[0]%/*}/config_safety.sh"
# shellcheck source=lib/trust_history.sh
. "${BASH_SOURCE[0]%/*}/trust_history.sh"

# ── Hook trust model ────────────────────────────────────────────────────
# Hooks and executable defaults from .gtrconfig files (committed to
# repositories) require explicit user approval before use. This prevents
# malicious contributors from injecting arbitrary commands via shared config
# files.
#
# Trust state is stored in ~/.config/gtr/trusted/<key>
# where <key> binds the canonical repo root, Git/object directory identities and trusted
# content hash. The marker also records an approved commit: unrelated history
# requires new approval even if the common Git directory itself is preserved.
# Trust approves command definitions, including any code they delegate to; it
# does not pin script contents, dependencies or repository snapshot state.

_GTR_TRUST_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/gtr/trusted"

# Read ownership and permission bits on both GNU and BSD systems.
_hooks_storage_stat() {
  local metadata
  # BSD %Lp drops special bits such as sticky; callers mask the full mode.
  metadata=$(stat -c '%u:%a' "$1" 2>/dev/null) ||
    metadata=$(stat -f '%u:%p' "$1" 2>/dev/null) || return 1
  case "$metadata" in
    *[!0-9:]*|:*|*:) return 1 ;;
  esac
  case "${metadata#*:}" in *[!0-7]*) return 1 ;; esac
  printf '%s\n' "$metadata"
}

# Validate every ancestor before traversing or creating it. Safe config-home
# symlinks and system aliases (/tmp and /var on macOS) remain supported: check
# the link's owner and its target's full path, with a bounded symlink walk.
# Sticky system temp directories are safe ancestors, but never trust stores.
# Usage: _hooks_trust_directory <directory> [create]
# Prints the physical directory; new components are private even with umask 000.
_hooks_trust_directory() {
  local remaining="$1" action="${2:-}" current="/" component candidate metadata owner mode
  local link_target links=0 current_uid current_os
  current_uid=$(id -u) || return 1
  current_os=$(uname -s) || return 1
  _config_safety_acl_check / "$current_os" >/dev/null || return 1
  case "$remaining" in
    /*) ;;
    *) remaining="$(pwd -P)/$remaining" ;;
  esac
  while [ -n "$remaining" ]; do
    component="${remaining%%/*}"
    if [ "$component" = "$remaining" ]; then remaining=""; else remaining="${remaining#*/}"; fi
    case "$component" in
      ''|.) continue ;;
      ..) current="${current%/*}"; [ -n "$current" ] || current="/"; continue ;;
    esac
    candidate="${current%/}/$component"
    if [ -L "$candidate" ]; then
      # The trust directory itself must be a real directory.
      [ -n "$remaining" ] || return 1
      links=$((links + 1))
      [ "$links" -le 40 ] || return 1
      metadata=$(_hooks_storage_stat "$candidate") || return 1
      owner="${metadata%%:*}"
      [ "$owner" = "$current_uid" ] || [ "$owner" = 0 ] || return 1
      link_target=$(readlink "$candidate") || return 1
      case "$link_target" in /*) current="/" ;; esac
      remaining="$link_target/$remaining"
      continue
    fi
    if [ ! -e "$candidate" ] && [ "$action" = create ]; then
      (umask 077; mkdir -- "$candidate") || return 1
    fi
    [ -d "$candidate" ] && [ ! -L "$candidate" ] || return 1
    metadata=$(_hooks_storage_stat "$candidate") || return 1
    owner="${metadata%%:*}"
    mode="${metadata#*:}"
    [ "$owner" = "$current_uid" ] || [ "$owner" = 0 ] || return 1
    if [ "$((8#$mode & 8#22))" -ne 0 ]; then
      [ "$((8#$mode & 8#1000))" -ne 0 ] || return 1
    fi
    _config_safety_acl_check "$candidate" "$current_os" >/dev/null || return 1
    current="$candidate"
  done
  # Even a sticky or root-owned trust store cannot hold this user's approvals.
  metadata=$(_hooks_storage_stat "$current") || return 1
  [ "${metadata%%:*}" = "$current_uid" ] || return 1
  mode="${metadata#*:}"
  [ "$((8#$mode & 8#22))" -eq 0 ] || return 1
  _config_safety_acl_check "$current" "$current_os" >/dev/null || return 1
  printf '%s\n' "$current"
}

# Only accept regular, user-owned, non-writable-by-others marker files. Resolve
# the validated directory once so subsequent operations use its physical path.
# In create mode a missing marker is allowed, but an unsafe existing one is not.
_hooks_safe_trust_path() {
  local trust_path="$1" action="${2:-}" directory name metadata mode current_uid current_os
  name="${trust_path##*/}"
  case "$name" in ''|*[!0-9a-f]*) return 1 ;; esac
  [ "${#name}" -eq 64 ] || return 1
  directory=$(_hooks_trust_directory "${trust_path%/*}" "$action") || return 1
  trust_path="$directory/$name"
  [ ! -L "$trust_path" ] || return 1
  if [ -e "$trust_path" ]; then
    [ -f "$trust_path" ] || return 1
    metadata=$(_hooks_storage_stat "$trust_path") || return 1
    current_uid=$(id -u) || return 1
    [ "${metadata%%:*}" = "$current_uid" ] || return 1
    mode="${metadata#*:}"
    [ "$((8#$mode & 8#22))" -eq 0 ] || return 1
    current_os=$(uname -s) || return 1
    _config_safety_acl_check "$trust_path" "$current_os" >/dev/null || return 1
  else
    [ "$action" = create ] || return 1
  fi
  printf '%s\n' "$trust_path"
}

# Read all trusted command definitions from a .gtrconfig file.
# Usage: _hooks_read_definitions <config_file>
_hooks_read_definitions() {
  local config_file="$1"
  # Hex keeps NUL record boundaries and trailing value newlines in shell variables.
  # Git emits key<LF>value<NUL>; unlike line records this encoding is injective.
  local hook_content
  hook_content=$(git config -z -f "$config_file" --get-regexp '^hooks\.|^defaults\.editor$|^defaults\.ai$' 2>/dev/null | od -An -v -tx1 | tr -d ' \n')
  [ -n "$hook_content" ] || return 1
  printf '%s\n' "$hook_content"
}

# Select values only from the captured definitions, never from the pathname.
# An empty key displays every record for the trust confirmation.
# Mode null emits NUL-terminated values for execution; all/last retain their
# text output for existing display/default callers and generated shell helpers.
_hooks_definitions_get() {
  local definitions="$1" key="${2:-}" mode="${3:-all}" record record_key value last_value=""
  key=$(printf '%s' "$key" | tr '[:upper:]' '[:lower:]')
  while IFS= read -r -d '' record; do
    record_key="${record%%$'\n'*}"
    value=""
    case "$record" in *$'\n'*) value="${record#*$'\n'}" ;; esac
    if [ -z "$key" ]; then
      printf '%s = %q\n' "$record_key" "$value"
    elif [ "$record_key" = "$key" ]; then
      if [ "$mode" = last ]; then
        last_value="$value"
      elif [ "$mode" = null ]; then
        printf '%s\0' "$value"
      else
        printf '%s\n' "$value"
      fi
    fi
  done < <(printf '%b' "$(printf '%s' "$definitions" | sed 's/../\\x&/g')")
  if [ "$mode" = last ]; then printf '%s\n' "$last_value"; fi
}

# Decode hex records to a stream, never to a shell variable (which cannot hold
# NUL bytes). Consumers use read -d '' so trailing value newlines also survive.
_hooks_decode_records() {
  printf '%b' "$(printf '%s' "$1" | sed 's/../\\x&/g')"
}

# Validate a captured snapshot against its repository-scoped marker.
_hooks_snapshot_is_trusted() {
  local config_file="$1" definitions="$2" trust_path
  [ -n "$definitions" ] || return 0
  trust_path=$(_hooks_reviewed_trust_path "$config_file" "$definitions") || return 1
  _hooks_marker_matches_config "$trust_path" "$config_file"
}

# Print the SHA-256 hex digest of stdin.
# Falls back to sha256sum where Perl's shasum is not installed or cannot run
# (for example Alpine or minimal Fedora/RHEL images).
# Usage: printf '%s' "$data" | _hooks_sha256
_hooks_sha256() {
  local input digest
  input=$(cat; printf '.')
  input=${input%.}
  if command -v shasum >/dev/null 2>&1 &&
    digest=$(printf '%s' "$input" | shasum -a 256 2>/dev/null) &&
    [ -n "$digest" ]; then
    printf '%s\n' "${digest%% *}"
    return 0
  fi
  command -v sha256sum >/dev/null 2>&1 || return 1
  digest=$(printf '%s' "$input" | sha256sum) || return 1
  [ -n "$digest" ] || return 1
  printf '%s\n' "${digest%% *}"
}

# Compute a content hash for trusted command definitions.
# Usage: _hooks_content_hash <hook_content>
_hooks_content_hash() {
  local hook_content="$1"
  [ -n "$hook_content" ] || return 1
  printf '%s\n' "$hook_content" | _hooks_sha256
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
# Usage: _hooks_reviewed_trust_key <config_file> <hook_content> [repo_identity]
_hooks_reviewed_trust_key() {
  local config_file="$1"
  local hook_content="$2"
  local repo_identity="${3:-}"
  local hash repo_root
  hash=$(_hooks_content_hash "$hook_content") || return 1
  repo_root=$(_hooks_repo_root "$config_file") || return 1
  if [ -z "$repo_identity" ]; then
    repo_identity=$(_hooks_repo_identity "$repo_root") || return 1
  fi
  printf 'v4\n%s\n%s\n%s\n' "$repo_root" "$repo_identity" "$hash" | _hooks_sha256
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
# Usage: _hooks_reviewed_trust_path <config_file> <hook_content> [repo_identity]
_hooks_reviewed_trust_path() {
  local config_file="$1"
  local hook_content="$2"
  local repo_identity="${3:-}"
  local trust_key
  trust_key=$(_hooks_reviewed_trust_key "$config_file" "$hook_content" "$repo_identity") || return 1
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

# Check the canonical config path and continuity with the approved history.
# Usage: _hooks_marker_matches_config <trust_path> <config_file>
_hooks_marker_matches_config() {
  local trust_path="$1"
  local config_file="$2"
  local marker_content canonical_config_file approved_commit

  trust_path=$(_hooks_safe_trust_path "$trust_path") || return 1
  marker_content="$(cat "$trust_path" 2>/dev/null)" || return 1
  canonical_config_file=$(_hooks_canonical_config_path "$config_file") || return 1
  approved_commit="${marker_content%%$'\n'*}"
  [ "${marker_content#*$'\n'}" = "$canonical_config_file" ] || return 1
  _hooks_history_matches "${canonical_config_file%/*}" "$approved_commit"
}

# Check if .gtrconfig command definitions are trusted for the current repository
# Usage: _hooks_are_trusted <config_file>
# Returns: 0 if trusted (or no trusted command definitions), 1 if untrusted
_hooks_are_trusted() {
  local config_file="$1"
  [ ! -f "$config_file" ] && return 0

  local hook_content trust_path
  hook_content=$(_hooks_read_definitions "$config_file") || return 0
  _hooks_snapshot_is_trusted "$config_file" "$hook_content"
}

# Write a trust marker that matches the reviewed command definitions
# Usage: _hooks_write_trust_marker <trust_path> <config_file> [approved_commit]
_hooks_write_trust_marker() {
  local trust_path="$1"
  local config_file="${2:-}"
  local approved_commit="${3:-}"
  local temp_path=""
  local canonical_config_file=""

  # The caller may only publish a marker directly in the configured trust store.
  [ "${trust_path%/*}" = "$_GTR_TRUST_DIR" ] || return 1
  trust_path=$(_hooks_safe_trust_path "$trust_path" create) || {
    log_error "Unsafe or inaccessible trust storage: $_GTR_TRUST_DIR"
    return 1
  }
  canonical_config_file=$(_hooks_canonical_config_path "$config_file") || return 1
  if [ -z "$approved_commit" ]; then
    approved_commit=$(git -C "${canonical_config_file%/*}" rev-parse --verify 'HEAD^{commit}' 2>/dev/null) || return 1
  fi
  temp_path="$(umask 077; mktemp "${trust_path%/*}/.trust.XXXXXX")" || return 1

  if ! printf '%s\n%s\n' "$approved_commit" "$canonical_config_file" > "$temp_path"; then
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
  local hook_content trust_path repo_root approved_commit
  repo_root=$(_hooks_repo_root "$config_file") || return 1
  approved_commit=$(git -C "$repo_root" rev-parse --verify 'HEAD^{commit}' 2>/dev/null) || true
  hook_content=$(_hooks_read_definitions "$config_file") || return 0
  [ -n "$approved_commit" ] || return 1
  trust_path=$(_hooks_reviewed_trust_path "$config_file" "$hook_content") || return 1

  _hooks_write_trust_marker "$trust_path" "$config_file" "$approved_commit"
}

# Get hooks, filtering out untrusted .gtrconfig hooks with a warning
# Usage: _hooks_get_trusted <phase>
# Returns hex-encoded, NUL-terminated complete values, in first-seen order.
# This internal execution interface must not be consumed as lines of shell code.
_hooks_get_trusted() {
  local phase="$1"
  _gtr_config_check || return 1

  # Always include hooks from git config (user controls their own .git/config)
  local git_hooks
  git_hooks=$(git config -z --get-all "gtr.hook.$phase" 2>/dev/null |
    od -An -v -tx1 | tr -d ' \n' || true)

  # Check .gtrconfig trust before including its hooks
  local config_file
  config_file=$(_gtrconfig_path)
  local file_hooks=""

  if [ -n "$config_file" ] && [ -f "$config_file" ]; then
    local definitions
    definitions=$(_hooks_read_definitions "$config_file") || true
    file_hooks=$(_hooks_definitions_get "$definitions" "hooks.$phase" null |
      od -An -v -tx1 | tr -d ' \n')
    if ! _hooks_snapshot_is_trusted "$config_file" "$definitions"; then
      if [ -n "$file_hooks" ]; then
        log_warn "Untrusted .gtrconfig hooks for '$phase' phase — skipping"
        log_warn "Review hooks in $config_file, then run: git gtr trust"
      fi
      file_hooks=""
    fi
  fi

  # Deduplicate complete values, not their physical lines. Indexed arrays work
  # in Bash 3.2; no delimiter can collide with text inside a hook value.
  local seen=()
  local hook previous duplicate
  while IFS= read -r -d '' hook; do
    [ -n "$hook" ] || continue
    duplicate=0
    for previous in "${seen[@]}"; do
      if [ "$hook" = "$previous" ]; then
        duplicate=1
        break
      fi
    done
    [ "$duplicate" -eq 0 ] || continue
    seen+=("$hook")
    printf '%s\0' "$hook"
  done < <(_hooks_decode_records "$git_hooks$file_hooks") |
    od -An -v -tx1 | tr -d ' \n'
}

# Report the outcome a successful hook phase will have without executing it.
# Usage: _hooks_phase_status <phase>
# Prints one of: none, ran, skipped-untrusted, partial
_hooks_phase_status() {
  local phase="$1"
  local git_hooks="" config_file="" file_hooks=""
  local has_runnable=0 has_untrusted=0

  git_hooks=$(git config --get-all "gtr.hook.$phase" 2>/dev/null || true)
  [ -n "$git_hooks" ] && has_runnable=1

  config_file=$(_gtrconfig_path) || true
  if [ -n "$config_file" ] && [ -f "$config_file" ]; then
    file_hooks=$(git config -f "$config_file" --get-all "hooks.$phase" 2>/dev/null || true)
    if [ -n "$file_hooks" ]; then
      if _hooks_are_trusted "$config_file"; then
        has_runnable=1
      else
        has_untrusted=1
      fi
    fi
  fi

  if [ "$has_runnable" -eq 1 ] && [ "$has_untrusted" -eq 1 ]; then
    printf "partial"
  elif [ "$has_runnable" -eq 1 ]; then
    printf "ran"
  elif [ "$has_untrusted" -eq 1 ]; then
    printf "skipped-untrusted"
  else
    printf "none"
  fi
}

# Run hooks for a specific phase
# Usage: run_hooks phase [env_vars...]
# Example: run_hooks postCreate REPO_ROOT="$root" WORKTREE_PATH="$path"
run_hooks() {
  local phase="$1"
  shift

  # Get hooks, filtering untrusted .gtrconfig hooks
  local hooks
  hooks=$(_hooks_get_trusted "$phase") || return 1

  if [ -z "$hooks" ]; then
    # No hooks configured for this phase
    return 0
  fi

  log_step "Running $phase hooks..."

  local hook hook_count=0
  local failed=0

  # Capture environment variable assignments in array to preserve quoting
  local envs=("$@")

  # Execute each hook in a subshell to isolate side effects
  while IFS= read -r -d '' hook; do
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
  done < <(_hooks_decode_records "$hooks")

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
  hooks=$(_hooks_get_trusted "$phase") || return 1

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

  local hook hook_count=0
  while IFS= read -r -d '' hook; do
    [ -z "$hook" ] && continue

    hook_count=$((hook_count + 1))
    log_info "Hook $hook_count: $hook"

    # eval directly (no subshell) so exports persist
    eval "$hook" </dev/null || log_warn "Hook $hook_count failed (continuing)"
  done < <(_hooks_decode_records "$hooks")
}
