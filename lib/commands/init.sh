#!/usr/bin/env bash

# The generators are also sourced directly, independently of the CLI loader.
if ! command -v _gtr_config_check >/dev/null 2>&1; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    # shellcheck disable=SC2296,SC2298,SC1091
    . "${${(%):-%x}:h}/../config_safety.sh"
  else
    # shellcheck source=lib/config_safety.sh
    . "${BASH_SOURCE[0]%/*}/../config_safety.sh"
  fi
fi

if ! command -v _hooks_history_matches >/dev/null 2>&1; then
  if [ -n "${ZSH_VERSION:-}" ]; then
    # shellcheck disable=SC2296,SC2298,SC1091
    . "${${(%):-%x}:h}/../trust_history.sh"
  else
    # shellcheck source=lib/trust_history.sh
    . "${BASH_SOURCE[0]%/*}/../trust_history.sh"
  fi
fi

# Cache contents are executable code. Reuse the config validator's component
# walk so safe XDG symlinks work without hiding writable link parents/targets.
_init_cache_path_is_safe() {
  local _config_safety_uid _config_safety_os _config_safety_sticky=0
  local _config_safety_checked=()
  _config_safety_uid=$(id -u) || return 1
  _config_safety_os=$(uname -s) || return 1
  _config_safety_path "$1" || return 1
  # Sticky ancestors can protect existing owned entries (e.g. under /tmp),
  # but the cache directory itself must not be writable by other users.
  [ "$_config_safety_sticky" -eq 0 ] || return 1
  if [ "$#" -gt 1 ]; then
    # Retain checked components only within this validation, not across I/O.
    _config_safety_path "$2" || return 1
  fi
  return 0
}

_init_cache_is_safe() {
  local cache_dir="$1" cache_file="$2"
  [ ! -L "$cache_dir" ] && [ -d "$cache_dir" ] && [ -O "$cache_dir" ] || return 1
  [ ! -L "$cache_file" ] || return 1
  if [ -e "$cache_file" ]; then
    [ -f "$cache_file" ] && [ -O "$cache_file" ] || return 1
  fi
  _init_cache_path_is_safe "$cache_dir" "$cache_file"
}

# Create one missing component at a time after checking its parent. In
# particular, mkdir -p could traverse unchecked paths after a missing/.. pair.
_init_cache_mkdir() {
  local dir="$1" parent
  if [ -d "$dir" ]; then
    _init_cache_path_is_safe "$dir"
    return $?
  fi
  [ ! -e "$dir" ] && [ ! -L "$dir" ] || return 1
  parent="${dir%/*}"
  _init_cache_mkdir "${parent:-/}" || return 1
  _init_cache_path_is_safe "$dir" || return 1
  mkdir -m 700 -- "$dir" || return 1
  _init_cache_path_is_safe "$dir"
}

_init_cache_write() {
  local cache_dir="$1" cache_file="$2" stamp="$3" output="$4" temp_file
  [ ! -L "$cache_dir" ] || return 1
  if [ ! -d "$cache_dir" ]; then
    _init_cache_mkdir "$cache_dir" || return 1
  fi
  _init_cache_is_safe "$cache_dir" "$cache_file" || return 1
  # mktemp creates a new 0600 file even under umask 000. Atomic replacement
  # avoids following a cache-file link or exposing a partially written cache.
  temp_file=$(mktemp "$cache_dir/.init.XXXXXX") || return 1
  if _init_cache_is_safe "$cache_dir" "$temp_file" &&
    printf '%s\n%s\n' "$stamp" "$output" > "$temp_file" &&
    _init_cache_is_safe "$cache_dir" "$cache_file" &&
    mv -f -- "$temp_file" "$cache_file"; then
    return 0
  fi
  rm -f -- "$temp_file" || true
  return 1
}

# Init command (generate shell integration for cd support)
cmd_init() {
  local shell="" func_name="gtr"

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      -h|--help)
        show_command_help
        ;;
      --as)
        if [ -z "${2:-}" ]; then
          log_error "--as requires a function name"
          return 1
        fi
        func_name="$2"
        shift 2
        ;;
      -*)
        log_error "Unknown flag: $1"
        log_info "Run 'git gtr init --help' for usage"
        return 1
        ;;
      *)
        if [ -n "$shell" ]; then
          log_error "Unexpected argument: $1"
          return 1
        fi
        shell="$1"
        shift
        ;;
    esac
  done

  # Validate function name is a legal shell identifier
  case "$func_name" in
    [a-zA-Z_]*) ;;
    *)
      log_error "Invalid function name: $func_name (must start with a letter or underscore)"
      return 1
      ;;
  esac
  # Check remaining characters (Bash 3.2 compatible — no regex operator)
  local _stripped
  _stripped="$(printf '%s' "$func_name" | tr -d 'a-zA-Z0-9_')"
  if [ -n "$_stripped" ]; then
    log_error "Invalid function name: $func_name (only letters, digits, and underscores allowed)"
    return 1
  fi

  # Resolve generator function
  local generator
  case "$shell" in
    bash) generator="_init_bash" ;;
    zsh)  generator="_init_zsh" ;;
    fish) generator="_init_fish" ;;
    "")   show_command_help; return 0 ;;
    *)
      log_error "Unknown shell: $shell"
      log_error "Supported shells: bash, zsh, fish"
      log_info "Run 'git gtr init --help' for usage"
      return 1
      ;;
  esac

  # Generate output (cached to ~/.cache/gtr/, auto-invalidates on shell integration changes)
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/gtr"
  case "$cache_dir" in /*) ;; *) cache_dir="$(pwd -P)/$cache_dir" ;; esac
  local cache_file="$cache_dir/init-${func_name}.${shell}"
  # Bump when generated helpers change, even if GTR_VERSION is unchanged.
  # Schema 18 hashes trusted hooks with sha256sum when shasum is not installed.
  local cache_schema="${GTR_INIT_CACHE_VERSION:-18}"
  local cache_stamp="# gtr-cache: version=${GTR_VERSION:-unknown} init=${cache_schema} func=$func_name shell=$shell"

  # A matching public stamp alone does not make executable cache data trusted.
  local first_line cached_output
  if _init_cache_is_safe "$cache_dir" "$cache_file" 2>/dev/null &&
    [ -f "$cache_file" ] &&
    first_line="$(head -1 "$cache_file" 2>/dev/null)" &&
    [ "$first_line" = "$cache_stamp" ] &&
    cached_output="$(tail -n +2 "$cache_file" 2>/dev/null)"; then
    printf '%s\n' "$cached_output"
    return 0
  fi

  # Generate, output, and cache (output first so set -e cache failures don't swallow it)
  local output
  output="$("$generator" | sed "s/__FUNC__/$func_name/g")"
  printf '%s\n' "$output"
  _init_cache_write "$cache_dir" "$cache_file" "$cache_stamp" "$output" 2>/dev/null || true
}

# Run the exact CLI validator in Bash for every generated shell. Embedding the
# functions keeps cached integration independent of the installation pathname.
_init_emit_config_safety_helper() {
  local shell_name="$1" validator
  validator=$(typeset -f _config_safety_error _config_safety_acl_check _config_safety_node _config_safety_path _gtr_config_check)
  validator="$validator"$'\n_gtr_config_check'
  if [ "$shell_name" = fish ]; then
    validator=$(printf '%s' "$validator" | sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")
    printf "function __FUNC___check_git_config\n  command bash -c '%s'\nend\n" "$validator"
  else
    printf '__FUNC___check_git_config() {\n  command bash -c %q\n}\n' "$validator"
  fi
}

# This template is exercised against the CLI's snapshot helpers in tests.
_init_emit_snapshot_helpers() {
  cat <<'SNAPSHOT'
__FUNC___hooks_read_definitions() {
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
# The nul mode streams complete hook values without storing NULs in variables.
__FUNC___hooks_definitions_get() {
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
      elif [ "$mode" = nul ]; then
        printf '%s\0' "$value"
      else
        printf '%s\n' "$value"
      fi
    fi
  done < <(printf '%b' "$(printf '%s' "$definitions" | sed 's/../\\x&/g')")
  if [ "$mode" = last ]; then printf '%s\n' "$last_value"; fi
}

SNAPSHOT
}

# Keep this template identical to the storage helpers in lib/hooks.sh; tests
# compare them so the CLI and generated shells enforce the same trust boundary.
_init_emit_trust_storage_helpers() {
  typeset -f _config_safety_acl_check
  cat <<'STORAGE'
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
STORAGE
}

# Emit Bash/Zsh trust helpers with the requested per-function shell setup.
# Usage: _init_emit_posix_trust_helpers <shell_prelude>
# Prints definitions with __FUNC__ placeholders for cmd_init to substitute.
_init_emit_posix_trust_helpers() {
  local shell_prelude="$1"
  local template

  # Keep the snapshot encoding and extraction identical to the CLI.
  _init_emit_snapshot_helpers
  typeset -f _hooks_repo_identity | sed 's/_hooks_repo_identity/__FUNC___hooks_repo_identity/g'
  typeset -f _hooks_history_matches | sed 's/_hooks_history_matches/__FUNC___hooks_history_matches/g'
  _init_emit_trust_storage_helpers |
    sed -e 's/_hooks_/__FUNC___hooks_/g' -e 's/_config_safety_acl_check/__FUNC___check_storage_acl/g'

  # Keep case patterns balanced inside this substitution for Bash 3.2's parser.
  template=$(cat <<'EOF'
__FUNC___sha256() {
__SHELL_PRELUDE__
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 | cut -d' ' -f1
  elif command -v sha256sum >/dev/null 2>&1; then
    sha256sum | cut -d' ' -f1
  else
    return 1
  fi
}

__FUNC___gtrconfig_path() {
__SHELL_PRELUDE__
  local _gtr_git_common_dir _gtr_repo_root
  _gtr_git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null)" || return 1

  if [ "$_gtr_git_common_dir" = ".git" ]; then
    _gtr_repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 1
  else
    _gtr_repo_root="${_gtr_git_common_dir%/.git}"
  fi

  printf '%s/.gtrconfig\n' "$_gtr_repo_root"
}

__FUNC___hooks_current_content_hash() {
__SHELL_PRELUDE__
  local _gtr_config_file="$1"
  local _gtr_hook_defs="${2:-}"
  if [ "$#" -lt 2 ]; then
    _gtr_hook_defs="$(__FUNC___hooks_read_definitions "$_gtr_config_file")" || return 1
  fi
  [ -n "$_gtr_hook_defs" ] || return 1
  printf '%s\n' "$_gtr_hook_defs" | __FUNC___sha256
}

__FUNC___hooks_repo_root() {
__SHELL_PRELUDE__
  local _gtr_config_file="$1"
  cd "$(dirname "$_gtr_config_file")" 2>/dev/null && pwd -P
}

__FUNC___hooks_canonical_config_path() {
__SHELL_PRELUDE__
  local _gtr_config_file="$1"
  local _gtr_repo_root
  _gtr_repo_root="$(__FUNC___hooks_repo_root "$_gtr_config_file" 2>/dev/null)" || return 1
  printf '%s/%s\n' "$_gtr_repo_root" "$(basename "$_gtr_config_file")"
}

__FUNC___hooks_current_trust_key() {
__SHELL_PRELUDE__
  local _gtr_config_file="$1"
  local _gtr_hook_hash _gtr_repo_root _gtr_repo_identity
  local _gtr_definitions="${2:-}"
  if [ "$#" -lt 2 ]; then
    _gtr_definitions="$(__FUNC___hooks_read_definitions "$_gtr_config_file")" || return 1
  fi
  _gtr_hook_hash="$(__FUNC___hooks_current_content_hash "$_gtr_config_file" "$_gtr_definitions" 2>/dev/null)" || return 1
  _gtr_repo_root="$(__FUNC___hooks_repo_root "$_gtr_config_file" 2>/dev/null)" || return 1
  _gtr_repo_identity="$(__FUNC___hooks_repo_identity "$_gtr_repo_root" 2>/dev/null)" || return 1
  printf 'v4\n%s\n%s\n%s\n' "$_gtr_repo_root" "$_gtr_repo_identity" "$_gtr_hook_hash" | __FUNC___sha256
}

__FUNC___hooks_marker_matches_config() {
__SHELL_PRELUDE__
  local _gtr_trust_path="$1"
  local _gtr_config_file="$2"
  local _gtr_marker _gtr_canonical_config _gtr_approved_commit
  _gtr_trust_path="$(__FUNC___hooks_safe_trust_path "$_gtr_trust_path")" || return 1
  _gtr_marker="$(cat "$_gtr_trust_path" 2>/dev/null)" || return 1
  _gtr_canonical_config="$(__FUNC___hooks_canonical_config_path "$_gtr_config_file" 2>/dev/null)" || return 1
  _gtr_approved_commit="${_gtr_marker%%$'\n'*}"
  [ "${_gtr_marker#*$'\n'}" = "$_gtr_canonical_config" ] || return 1
  __FUNC___hooks_history_matches "${_gtr_canonical_config%/*}" "$_gtr_approved_commit"
}

__FUNC___hooks_are_trusted() {
__SHELL_PRELUDE__
  local _gtr_config_file="$1"
  local _gtr_trust_dir="$2"
  local _gtr_trust_key
  _gtr_trust_key="$(__FUNC___hooks_current_trust_key "$_gtr_config_file" "${3:-}" 2>/dev/null)" || return 1
  __FUNC___hooks_marker_matches_config "$_gtr_trust_dir/$_gtr_trust_key" "$_gtr_config_file"
}
EOF
)

  printf '%s\n' "${template//__SHELL_PRELUDE__/$shell_prelude}"
}

# Emit Fish trust helpers, embedding the shared Bash snapshot/storage logic.
# Usage: _init_emit_fish_trust_helpers
# Prints self-contained definitions with __FUNC__ placeholders; runs no hooks.
_init_emit_fish_trust_helpers() {
  local snapshot_helpers storage_helpers history_helper identity_helper
  # Quote for a Fish single-quoted string. Bash 3.2's parameter substitution
  # over-escapes single quotes here, so use sed for consistent generated code.
  snapshot_helpers=$(_init_emit_snapshot_helpers |
    sed -e 's/__FUNC___hooks_/_hooks_/g; s/\\/\\\\/g' -e "s/'/\\\\'/g")
  printf "function __FUNC___hooks_read_definitions\n  command bash -c '%s\n_hooks_read_definitions \"\$1\"' bash \"\$argv[1]\"\nend\n" "$snapshot_helpers"
  printf "function __FUNC___hooks_definitions_get\n  command bash -c '%s\n_hooks_definitions_get \"\$1\" \"\$2\" \"\$3\"' bash \"\$argv[1]\" \"\$argv[2]\" \"\$argv[3]\"\nend\n" "$snapshot_helpers"
  storage_helpers=$(_init_emit_trust_storage_helpers |
    sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")
  printf "function __FUNC___hooks_safe_trust_path\n  command bash -c '%s\n_hooks_safe_trust_path \"\$1\"' bash \"\$argv[1]\"\nend\n" "$storage_helpers"
  history_helper=$(typeset -f _hooks_history_matches |
    sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")
  printf "function __FUNC___hooks_history_matches\n  command bash -c '%s\n_hooks_history_matches \"\$1\" \"\$2\"' bash \"\$argv[1]\" \"\$argv[2]\"\nend\n" "$history_helper"
  identity_helper=$(typeset -f _hooks_repo_identity |
    sed -e 's/\\/\\\\/g' -e "s/'/\\\\'/g")
  printf "function __FUNC___hooks_repo_identity\n  command bash -c '%s\n_hooks_repo_identity \"\$1\"' bash \"\$argv[1]\"\nend\n" "$identity_helper"
  cat <<'FISH'
function __FUNC___sha256
  if command -q shasum
    shasum -a 256 | cut -d' ' -f1
  else if command -q sha256sum
    sha256sum | cut -d' ' -f1
  else
    return 1
  end
end

function __FUNC___gtrconfig_path
  set -l _gtr_git_common_dir (git rev-parse --git-common-dir 2>/dev/null)
  test -n "$_gtr_git_common_dir"; or return 1

  if test "$_gtr_git_common_dir" = ".git"
    set -l _gtr_repo_root (git rev-parse --show-toplevel 2>/dev/null)
    test -n "$_gtr_repo_root"; or return 1
    printf '%s/.gtrconfig\n' "$_gtr_repo_root"
  else
    printf '%s/.gtrconfig\n' (string replace -r '/\.git$' '' -- "$_gtr_git_common_dir")
  end
end

function __FUNC___hooks_current_content_hash
  set -l _gtr_config_file "$argv[1]"
  set -l _gtr_hook_defs "$argv[2]"
  if test (count $argv) -lt 2
    set _gtr_hook_defs (__FUNC___hooks_read_definitions "$_gtr_config_file")
  end
  test -n "$_gtr_hook_defs"; or return 1
  printf '%s\n' "$_gtr_hook_defs" | __FUNC___sha256
end

function __FUNC___hooks_repo_root
  set -l _gtr_config_file "$argv[1]"
  command sh -c 'cd "$1" 2>/dev/null && pwd -P' sh (dirname "$_gtr_config_file")
end

function __FUNC___hooks_canonical_config_path
  set -l _gtr_config_file "$argv[1]"
  set -l _gtr_repo_root (__FUNC___hooks_repo_root "$_gtr_config_file" 2>/dev/null)
  test -n "$_gtr_repo_root"; or return 1
  printf '%s/%s\n' "$_gtr_repo_root" (basename "$_gtr_config_file")
end

function __FUNC___hooks_current_trust_key
  set -l _gtr_config_file "$argv[1]"
  set -l _gtr_definitions "$argv[2]"
  if test (count $argv) -lt 2
    set _gtr_definitions (__FUNC___hooks_read_definitions "$_gtr_config_file")
  end
  set -l _gtr_hook_hash (__FUNC___hooks_current_content_hash "$_gtr_config_file" "$_gtr_definitions" 2>/dev/null)
  test -n "$_gtr_hook_hash"; or return 1
  set -l _gtr_repo_root (__FUNC___hooks_repo_root "$_gtr_config_file" 2>/dev/null)
  test -n "$_gtr_repo_root"; or return 1
  set -l _gtr_repo_identity (__FUNC___hooks_repo_identity "$_gtr_repo_root" 2>/dev/null | string collect)
  test $pipestatus[1] -eq 0; or return 1
  test -n "$_gtr_repo_identity"; or return 1
  printf 'v4\n%s\n%s\n%s\n' "$_gtr_repo_root" "$_gtr_repo_identity" "$_gtr_hook_hash" | __FUNC___sha256
end

function __FUNC___hooks_marker_matches_config
  set -l _gtr_trust_path "$argv[1]"
  set -l _gtr_config_file "$argv[2]"
  set _gtr_trust_path (__FUNC___hooks_safe_trust_path "$_gtr_trust_path")
  or return 1
  set -l _gtr_marker (cat "$_gtr_trust_path" 2>/dev/null)
  test (count $_gtr_marker) -eq 2; or return 1
  set -l _gtr_canonical_config (__FUNC___hooks_canonical_config_path "$_gtr_config_file" 2>/dev/null)
  test "$_gtr_marker[2]" = "$_gtr_canonical_config"; or return 1
  __FUNC___hooks_history_matches (dirname "$_gtr_canonical_config") "$_gtr_marker[1]"
end

function __FUNC___hooks_are_trusted
  set -l _gtr_config_file "$argv[1]"
  set -l _gtr_trust_dir "$argv[2]"
  set -l _gtr_trust_key (__FUNC___hooks_current_trust_key "$_gtr_config_file" "$argv[3]" 2>/dev/null)
  test -n "$_gtr_trust_key"; or return 1
  __FUNC___hooks_marker_matches_config "$_gtr_trust_dir/$_gtr_trust_key" "$_gtr_config_file"
end
FISH
}

# Emit self-contained Bash navigation, hook helpers, and wrapper completion.
_init_bash() {
  cat <<'BASH'
# git-gtr shell integration (cached to ~/.cache/gtr/)
# Setup: see git gtr help init
BASH
  _init_emit_posix_trust_helpers ""
  _init_emit_config_safety_helper bash
  # Embed the same quoting helper as the standalone completion, under the wrapper's
  # name. cd completion must also work when the completion asset is not loaded.
  local completion_helper
  if [ -n "${ZSH_VERSION:-}" ]; then
    # shellcheck disable=SC2296,SC2298
    completion_helper="${${(%):-%x}:h}/../bash_completion.sh"
  else
    completion_helper="${BASH_SOURCE[0]%/*}/../bash_completion.sh"
  fi
  sed -e '1d' -e 's/_git_gtr_quote_targets/___FUNC___quote_targets/g' "$completion_helper"
  cat <<'BASH'
__FUNC___run_post_cd_hooks() {
  local dir="$1"
  local _gtr_trust_dir="${XDG_CONFIG_HOME:-$HOME/.config}/gtr/trusted"

  cd "$dir" && {
    __FUNC___check_git_config || return 1
    local _gtr_hook _gtr_previous _gtr_duplicate _gtr_config_file
    local -a _gtr_hooks=() _gtr_seen=()
    # Read from git config (local > global > system)
    # NULs stay in the stream; each array element holds one complete value.
    while IFS= read -r -d '' _gtr_hook; do
      [ -z "$_gtr_hook" ] || _gtr_hooks+=("$_gtr_hook")
    done < <(git config -z --get-all gtr.hook.postCd 2>/dev/null || true)
    # Read from .gtrconfig if it exists — only if trusted
    _gtr_config_file="$(__FUNC___gtrconfig_path 2>/dev/null)" || true
    if [ -f "$_gtr_config_file" ]; then
      local -a _gtr_file_hooks=()
      local _gtr_definitions
      _gtr_definitions="$(__FUNC___hooks_read_definitions "$_gtr_config_file")" || true
      while IFS= read -r -d '' _gtr_hook; do
        [ -z "$_gtr_hook" ] || _gtr_file_hooks+=("$_gtr_hook")
      done < <(__FUNC___hooks_definitions_get "$_gtr_definitions" hooks.postCd nul)
      if [ "${#_gtr_file_hooks[@]}" -gt 0 ]; then
        # Verify trust before including .gtrconfig hooks
        if __FUNC___hooks_are_trusted "$_gtr_config_file" "$_gtr_trust_dir" "$_gtr_definitions"; then
          _gtr_hooks+=("${_gtr_file_hooks[@]}")
        else
          echo "__FUNC__: Untrusted .gtrconfig hooks skipped — run 'git gtr trust' to approve" >&2
        fi
      fi
    fi
    if [ "${#_gtr_hooks[@]}" -gt 0 ]; then
      # Deduplicate whole values while preserving their original order.
      export WORKTREE_PATH="$dir"
      export REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
      export BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
      for _gtr_hook in "${_gtr_hooks[@]}"; do
        _gtr_duplicate=0
        # Bash 3.2 treats an empty array as unset under nounset.
        for _gtr_previous in ${_gtr_seen[@]+"${_gtr_seen[@]}"}; do
          if [ "$_gtr_hook" = "$_gtr_previous" ]; then
            _gtr_duplicate=1
            break
          fi
        done
        [ "$_gtr_duplicate" -eq 0 ] || continue
        _gtr_seen+=("$_gtr_hook")
        eval "$_gtr_hook" </dev/null || echo "__FUNC__: postCd hook failed: $_gtr_hook" >&2
      done
      unset WORKTREE_PATH REPO_ROOT BRANCH
    fi
  }
}

__FUNC__() {
  if [ "$#" -gt 0 ] && [ "$1" = "cd" ]; then
    shift
    local dir
    if [ "$#" -eq 0 ] && command -v fzf >/dev/null 2>&1; then
      local _gtr_porcelain
      _gtr_porcelain="$(command git gtr list --ids)"
      if [ "$(printf '%s\n' "$_gtr_porcelain" | wc -l)" -le 1 ]; then
        echo "No worktrees to pick from. Create one with: git gtr new <branch>" >&2
        return 0
      fi
      local _gtr_selection _gtr_key _gtr_line _gtr_branch
      _gtr_selection="$(printf '%s\n' "$_gtr_porcelain" | fzf \
        --delimiter=$'\t' \
        --with-nth=2,1 \
        --no-ansi \
        --layout=reverse \
        --border \
        --prompt='Worktree> ' \
        --header='enter:cd │ ctrl-n:new │ ctrl-e:editor │ ctrl-a:ai │ ctrl-d:delete │ ctrl-y:copy │ ctrl-r:refresh' \
        --expect=ctrl-n,ctrl-a,ctrl-e \
        --preview='git gtr run {s1} git log --oneline --graph --color=always -15 2>/dev/null; echo "---"; git gtr run {s1} git status --short 2>/dev/null' \
        --preview-window=right:50% \
        --bind='ctrl-d:execute(git gtr rm {s1} > /dev/tty 2>&1 < /dev/tty)+reload(git gtr list --ids)' \
        --bind='ctrl-y:execute(git gtr copy {s1} > /dev/tty 2>&1 < /dev/tty)' \
        --bind='ctrl-r:reload(git gtr list --ids)')" || return 0
      [ -z "$_gtr_selection" ] && return 0
      _gtr_key="$(head -1 <<< "$_gtr_selection")"
      _gtr_line="$(sed -n '2p' <<< "$_gtr_selection")"
      if [ "$_gtr_key" = "ctrl-n" ]; then
        printf "Branch name: " >&2
        read -r _gtr_branch
        [ -z "$_gtr_branch" ] && return 0
        command git gtr new "$_gtr_branch"
        return $?
      fi
      [ -z "$_gtr_line" ] && return 0
      # ctrl-a/ctrl-e: run after fzf exits (needs full terminal for TUI apps)
      if [ "$_gtr_key" = "ctrl-a" ]; then
        command git gtr ai "$(printf '%s' "$_gtr_line" | cut -f1)"
        return $?
      elif [ "$_gtr_key" = "ctrl-e" ]; then
        command git gtr editor "$(printf '%s' "$_gtr_line" | cut -f1)"
        return $?
      fi
      # Resolve the identity again; preserve path newlines with a sentinel.
      dir="$(command git gtr go "$(printf '%s' "$_gtr_line" | cut -f1)" && printf '.')" || return $?
      dir="${dir%.}"
      dir="${dir%$'\n'}"
    elif [ "$#" -eq 0 ]; then
      echo "Usage: __FUNC__ cd <branch>" >&2
      echo "Tip: Install fzf for an interactive picker (https://github.com/junegunn/fzf)" >&2
      return 1
    else
      dir="$(command git gtr go "$@")" || return $?
    fi
    __FUNC___run_post_cd_hooks "$dir"
  elif [ "$#" -gt 0 ] && { [ "$1" = "new" ] || [ "$1" = "pr" ]; }; then
    local -a _gtr_original_args=("$@") _gtr_command_args=()
    local _gtr_command="$1" _gtr_arg _gtr_cd=0 _gtr_before_paths _gtr_after_paths
    local _gtr_path _gtr_new_dir="" _gtr_new_count=0 _gtr_status
    shift
    for _gtr_arg in "$@"; do
      if [ "$_gtr_arg" = "--cd" ]; then
        _gtr_cd=1
      else
        _gtr_command_args+=("$_gtr_arg")
      fi
    done
    if [ "$_gtr_cd" -eq 1 ]; then
      _gtr_before_paths="$(command git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')"
      command git gtr "$_gtr_command" "${_gtr_command_args[@]}"
      _gtr_status=$?
      [ "$_gtr_status" -ne 0 ] && return "$_gtr_status"
      _gtr_after_paths="$(command git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')"
      while IFS= read -r _gtr_path; do
        [ -z "$_gtr_path" ] && continue
        case $'\n'"$_gtr_before_paths"$'\n' in
          *$'\n'"$_gtr_path"$'\n'*) ;;
          *)
            _gtr_new_dir="$_gtr_path"
            _gtr_new_count=$((_gtr_new_count + 1))
            ;;
        esac
      done <<< "$_gtr_after_paths"
      if [ "$_gtr_new_count" -eq 1 ]; then
        __FUNC___run_post_cd_hooks "$_gtr_new_dir"
        return $?
      fi
      echo "__FUNC__: created worktree, but could not determine new directory for --cd" >&2
      return 0
    fi
    command git gtr "${_gtr_original_args[@]}"
  else
    command git gtr "$@"
  fi
}

# Completion for __FUNC__ wrapper
___FUNC___delegate_completion() {
  local _gtr_wrapper_prefix="__FUNC__ "
  local _gtr_delegate_prefix="git gtr "
  COMP_WORDS=(git gtr "${COMP_WORDS[@]:1}")
  (( COMP_CWORD += 1 ))
  COMP_LINE="$_gtr_delegate_prefix${COMP_LINE#$_gtr_wrapper_prefix}"
  (( COMP_POINT += ${#_gtr_delegate_prefix} - ${#_gtr_wrapper_prefix} ))
  _git_gtr
}

___FUNC___completion() {
  local cur
  cur="${COMP_WORDS[COMP_CWORD]}"

  if [ "$COMP_CWORD" -eq 1 ]; then
    # First argument: cd + all git-gtr subcommands
    COMPREPLY=($(compgen -W "cd new pr go run copy editor ai rm mv rename ls list clean doctor adapter config completion init trust help version" -- "$cur"))
  elif [ "${COMP_WORDS[1]}" = "cd" ] && [ "$COMP_CWORD" -eq 2 ]; then
    # Filter and quote registered targets for literal acceptance by Readline.
    local worktrees
    worktrees="1"$'\n'"$(git gtr list --porcelain 2>/dev/null | cut -f2)" || true
    ___FUNC___quote_targets "$cur" "$worktrees"
  elif { [ "${COMP_WORDS[1]}" = "new" ] || [ "${COMP_WORDS[1]}" = "pr" ]; } && [[ "$cur" == -* ]]; then
    if type _git_gtr &>/dev/null; then
      ___FUNC___delegate_completion
    fi
    COMPREPLY+=($(compgen -W "--cd" -- "$cur"))
  elif type _git_gtr &>/dev/null; then
    # Delegate to git-gtr completions (adjust words to match expected format)
    ___FUNC___delegate_completion
  fi
}
complete -F ___FUNC___completion __FUNC__
BASH
}

_init_zsh() {
  cat <<'ZSH'
# git-gtr shell integration (cached to ~/.cache/gtr/)
# Setup: see git gtr help init
ZSH
  _init_emit_posix_trust_helpers "  emulate -L zsh"
  _init_emit_config_safety_helper zsh
  cat <<'ZSH'
__FUNC___run_post_cd_hooks() {
  emulate -L zsh
  local dir="$1"
  local _gtr_trust_dir="${XDG_CONFIG_HOME:-$HOME/.config}/gtr/trusted"

  cd "$dir" && {
    __FUNC___check_git_config || return 1
    local _gtr_hook _gtr_previous _gtr_duplicate _gtr_config_file
    local -a _gtr_hooks=() _gtr_seen=()
    # Read from git config (local > global > system)
    # NULs stay in the stream; each array element holds one complete value.
    while IFS= read -r -d '' _gtr_hook; do
      [ -z "$_gtr_hook" ] || _gtr_hooks+=("$_gtr_hook")
    done < <(git config -z --get-all gtr.hook.postCd 2>/dev/null || true)
    # Read from .gtrconfig if it exists — only if trusted
    _gtr_config_file="$(__FUNC___gtrconfig_path 2>/dev/null)" || true
    if [ -f "$_gtr_config_file" ]; then
      local -a _gtr_file_hooks=()
      local _gtr_definitions
      _gtr_definitions="$(__FUNC___hooks_read_definitions "$_gtr_config_file")" || true
      while IFS= read -r -d '' _gtr_hook; do
        [ -z "$_gtr_hook" ] || _gtr_file_hooks+=("$_gtr_hook")
      done < <(__FUNC___hooks_definitions_get "$_gtr_definitions" hooks.postCd nul)
      if [ "${#_gtr_file_hooks[@]}" -gt 0 ]; then
        # Verify trust before including .gtrconfig hooks
        if __FUNC___hooks_are_trusted "$_gtr_config_file" "$_gtr_trust_dir" "$_gtr_definitions"; then
          _gtr_hooks+=("${_gtr_file_hooks[@]}")
        else
          echo "__FUNC__: Untrusted .gtrconfig hooks skipped — run 'git gtr trust' to approve" >&2
        fi
      fi
    fi
    if [ "${#_gtr_hooks[@]}" -gt 0 ]; then
      # Deduplicate whole values while preserving their original order.
      export WORKTREE_PATH="$dir"
      export REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
      export BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
      for _gtr_hook in "${_gtr_hooks[@]}"; do
        _gtr_duplicate=0
        for _gtr_previous in "${_gtr_seen[@]}"; do
          if [ "$_gtr_hook" = "$_gtr_previous" ]; then
            _gtr_duplicate=1
            break
          fi
        done
        [ "$_gtr_duplicate" -eq 0 ] || continue
        _gtr_seen+=("$_gtr_hook")
        eval "$_gtr_hook" </dev/null || echo "__FUNC__: postCd hook failed: $_gtr_hook" >&2
      done
      unset WORKTREE_PATH REPO_ROOT BRANCH
    fi
  }
}

__FUNC__() {
  emulate -L zsh
  if [ "$#" -gt 0 ] && [ "$1" = "cd" ]; then
    shift
    local dir
    if [ "$#" -eq 0 ] && command -v fzf >/dev/null 2>&1; then
      local _gtr_porcelain
      _gtr_porcelain="$(command git gtr list --ids)"
      if [ "$(printf '%s\n' "$_gtr_porcelain" | wc -l)" -le 1 ]; then
        echo "No worktrees to pick from. Create one with: git gtr new <branch>" >&2
        return 0
      fi
      local _gtr_selection _gtr_key _gtr_line _gtr_branch
      _gtr_selection="$(printf '%s\n' "$_gtr_porcelain" | fzf \
        --delimiter=$'\t' \
        --with-nth=2,1 \
        --no-ansi \
        --layout=reverse \
        --border \
        --prompt='Worktree> ' \
        --header='enter:cd │ ctrl-n:new │ ctrl-e:editor │ ctrl-a:ai │ ctrl-d:delete │ ctrl-y:copy │ ctrl-r:refresh' \
        --expect=ctrl-n,ctrl-a,ctrl-e \
        --preview='git gtr run {s1} git log --oneline --graph --color=always -15 2>/dev/null; echo "---"; git gtr run {s1} git status --short 2>/dev/null' \
        --preview-window=right:50% \
        --bind='ctrl-d:execute(git gtr rm {s1} > /dev/tty 2>&1 < /dev/tty)+reload(git gtr list --ids)' \
        --bind='ctrl-y:execute(git gtr copy {s1} > /dev/tty 2>&1 < /dev/tty)' \
        --bind='ctrl-r:reload(git gtr list --ids)')" || return 0
      [ -z "$_gtr_selection" ] && return 0
      _gtr_key="$(head -1 <<< "$_gtr_selection")"
      _gtr_line="$(sed -n '2p' <<< "$_gtr_selection")"
      if [ "$_gtr_key" = "ctrl-n" ]; then
        printf "Branch name: " >&2
        read -r _gtr_branch
        [ -z "$_gtr_branch" ] && return 0
        command git gtr new "$_gtr_branch"
        return $?
      fi
      [ -z "$_gtr_line" ] && return 0
      # ctrl-a/ctrl-e: run after fzf exits (needs full terminal for TUI apps)
      if [ "$_gtr_key" = "ctrl-a" ]; then
        command git gtr ai "$(printf '%s' "$_gtr_line" | cut -f1)"
        return $?
      elif [ "$_gtr_key" = "ctrl-e" ]; then
        command git gtr editor "$(printf '%s' "$_gtr_line" | cut -f1)"
        return $?
      fi
      # Resolve the identity again; preserve path newlines with a sentinel.
      dir="$(command git gtr go "$(printf '%s' "$_gtr_line" | cut -f1)" && printf '.')" || return $?
      dir="${dir%.}"
      dir="${dir%$'\n'}"
    elif [ "$#" -eq 0 ]; then
      echo "Usage: __FUNC__ cd <branch>" >&2
      echo "Tip: Install fzf for an interactive picker (https://github.com/junegunn/fzf)" >&2
      return 1
    else
      dir="$(command git gtr go "$@")" || return $?
    fi
    __FUNC___run_post_cd_hooks "$dir"
  elif [ "$#" -gt 0 ] && { [ "$1" = "new" ] || [ "$1" = "pr" ]; }; then
    local -a _gtr_original_args _gtr_command_args
    local _gtr_command="$1" _gtr_arg _gtr_cd=0 _gtr_before_paths _gtr_after_paths
    local _gtr_path _gtr_new_dir="" _gtr_new_count=0 _gtr_status
    _gtr_original_args=("$@")
    _gtr_command_args=()
    shift
    for _gtr_arg in "$@"; do
      if [ "$_gtr_arg" = "--cd" ]; then
        _gtr_cd=1
      else
        _gtr_command_args+=("$_gtr_arg")
      fi
    done
    if [ "$_gtr_cd" -eq 1 ]; then
      _gtr_before_paths="$(command git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')"
      command git gtr "$_gtr_command" "${_gtr_command_args[@]}"
      _gtr_status=$?
      [ "$_gtr_status" -ne 0 ] && return "$_gtr_status"
      _gtr_after_paths="$(command git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')"
      while IFS= read -r _gtr_path; do
        [ -z "$_gtr_path" ] && continue
        case $'\n'"$_gtr_before_paths"$'\n' in
          *$'\n'"$_gtr_path"$'\n'*) ;;
          *)
            _gtr_new_dir="$_gtr_path"
            _gtr_new_count=$((_gtr_new_count + 1))
            ;;
        esac
      done <<< "$_gtr_after_paths"
      if [ "$_gtr_new_count" -eq 1 ]; then
        __FUNC___run_post_cd_hooks "$_gtr_new_dir"
        return $?
      fi
      echo "__FUNC__: created worktree, but could not determine new directory for --cd" >&2
      return 0
    fi
    command git gtr "${_gtr_original_args[@]}"
  else
    command git gtr "$@"
  fi
}

# Completion for __FUNC__ wrapper
___FUNC___completion() {
  local at_subcmd=0
  local current_word="${words[CURRENT]:-}"
  (( CURRENT == 2 )) && at_subcmd=1

  if [[ "${words[2]}" == "cd" ]] && (( CURRENT >= 3 )); then
    # Completing worktree name after "cd"
    if (( CURRENT == 3 )); then
      local -a worktrees
      worktrees=("1" ${(f)"$(git gtr list --porcelain 2>/dev/null | cut -f2)"})
      _describe 'worktree' worktrees
    fi
    return
  fi

  # Delegate to _git-gtr for standard command completions
  if (( $+functions[_git-gtr] )); then
    _git-gtr
  fi

  if [[ "${words[2]}" == (new|pr) && "$current_word" == -* ]]; then
    compadd -- --cd
  fi

  # When completing the subcommand position, also offer "cd"
  if (( at_subcmd )); then
    local -a extra=('cd:Change directory to worktree')
    _describe 'extra commands' extra
  fi
}
compdef ___FUNC___completion __FUNC__
ZSH
}

_init_fish() {
  cat <<'FISH'
# git-gtr shell integration
# Add to ~/.config/fish/config.fish:
#   git gtr init fish | source
FISH
  _init_emit_fish_trust_helpers
  _init_emit_config_safety_helper fish
  cat <<'FISH'
function __FUNC___run_post_cd_hooks
  set -l dir "$argv[1]"
  set -l _gtr_trust_dir "$HOME/.config/gtr/trusted"
  if set -q XDG_CONFIG_HOME
    set _gtr_trust_dir "$XDG_CONFIG_HOME/gtr/trusted"
  end
  cd $dir
  and begin
    __FUNC___check_git_config; or return 1
    set -l _gtr_hooks
    set -l _gtr_seen
    # Read from git config (local > global > system)
    # split0 preserves embedded and trailing newlines in each list element.
    set -l _gtr_git_hooks (git config -z --get-all gtr.hook.postCd 2>/dev/null | string split0)
    # Read from .gtrconfig if it exists — only if trusted
    set -l _gtr_config_file (__FUNC___gtrconfig_path 2>/dev/null)
    set -l _gtr_file_hooks
    if test -f "$_gtr_config_file"
      set -l _gtr_definitions (__FUNC___hooks_read_definitions "$_gtr_config_file")
      set -l _gtr_candidate_hooks (__FUNC___hooks_definitions_get "$_gtr_definitions" hooks.postCd nul | string split0)
      if test (count $_gtr_candidate_hooks) -gt 0
        # Verify trust before including .gtrconfig hooks
        if __FUNC___hooks_are_trusted "$_gtr_config_file" "$_gtr_trust_dir" "$_gtr_definitions"
          set _gtr_file_hooks $_gtr_candidate_hooks
        else
          echo "__FUNC__: Untrusted .gtrconfig hooks skipped — run 'git gtr trust' to approve" >&2
        end
      end
    end
    # Merge and deduplicate
    set _gtr_hooks $_gtr_git_hooks $_gtr_file_hooks
    if test (count $_gtr_hooks) -gt 0
      set -lx WORKTREE_PATH "$dir"
      set -lx REPO_ROOT (git rev-parse --show-toplevel 2>/dev/null)
      set -lx BRANCH (git rev-parse --abbrev-ref HEAD 2>/dev/null)
      for _gtr_hook in $_gtr_hooks
        if test -n "$_gtr_hook"
          if not contains -- "$_gtr_hook" $_gtr_seen
            set -a _gtr_seen "$_gtr_hook"
            eval "$_gtr_hook"; or echo "__FUNC__: postCd hook failed: $_gtr_hook" >&2
          end
        end
      end
    end
  end
end

function __FUNC__
  if test (count $argv) -gt 0; and test "$argv[1]" = "cd"
    set -l dir
    if test (count $argv) -eq 1; and type -q fzf
      set -l _gtr_porcelain (command git gtr list --ids)
      if test (count $_gtr_porcelain) -le 1
        echo "No worktrees to pick from. Create one with: git gtr new <branch>" >&2
        return 0
      end
      set -l _gtr_selection (printf '%s\n' $_gtr_porcelain | fzf \
        --delimiter=\t \
        --with-nth=2,1 \
        --no-ansi \
        --layout=reverse \
        --border \
        --prompt='Worktree> ' \
        --header='enter:cd │ ctrl-n:new │ ctrl-e:editor │ ctrl-a:ai │ ctrl-d:delete │ ctrl-y:copy │ ctrl-r:refresh' \
        --expect=ctrl-n,ctrl-a,ctrl-e \
        --preview='git gtr run {s1} git log --oneline --graph --color=always -15 2>/dev/null; echo "---"; git gtr run {s1} git status --short 2>/dev/null' \
        --preview-window=right:50% \
        --bind='ctrl-d:execute(git gtr rm {s1} > /dev/tty 2>&1 < /dev/tty)+reload(git gtr list --ids)' \
        --bind='ctrl-y:execute(git gtr copy {s1} > /dev/tty 2>&1 < /dev/tty)' \
        --bind='ctrl-r:reload(git gtr list --ids)')
      or return 0
      test -z "$_gtr_selection"; and return 0
      # --expect gives two lines: key (index 1) and selection (index 2)
      # Fish collapses empty lines in command substitution, so when Enter
      # is pressed the empty key line disappears and count drops to 1.
      set -l _gtr_key
      set -l _gtr_line
      if test (count $_gtr_selection) -eq 1
        set _gtr_key ""
        set _gtr_line "$_gtr_selection[1]"
      else
        set _gtr_key "$_gtr_selection[1]"
        set _gtr_line "$_gtr_selection[2]"
      end
      if test "$_gtr_key" = "ctrl-n"
        read -P "Branch name: " _gtr_branch
        test -z "$_gtr_branch"; and return 0
        command git gtr new "$_gtr_branch"
        return $status
      end
      test -z "$_gtr_line"; and return 0
      # ctrl-a/ctrl-e: run after fzf exits (needs full terminal for TUI apps)
      if test "$_gtr_key" = "ctrl-a"
        command git gtr ai (string split \t -- "$_gtr_line")[1]
        return $status
      else if test "$_gtr_key" = "ctrl-e"
        command git gtr editor (string split \t -- "$_gtr_line")[1]
        return $status
      end
      # NUL output preserves embedded/trailing newlines as one Fish argument.
      set dir (command git gtr run (string split \t -- "$_gtr_line")[1] sh -c 'printf "%s\0" "$PWD"' | string split0)
      test "$pipestatus[1]" -eq 0; or return 1
    else if test (count $argv) -eq 1
      echo "Usage: __FUNC__ cd <branch>" >&2
      echo "Tip: Install fzf for an interactive picker (https://github.com/junegunn/fzf)" >&2
      return 1
    else
      set dir (command git gtr go $argv[2..])
      or return $status
    end
    __FUNC___run_post_cd_hooks "$dir"
  else if test (count $argv) -gt 0; and contains -- "$argv[1]" new pr
    set -l _gtr_command "$argv[1]"
    set -l _gtr_cd 0
    set -l _gtr_command_args
    for _gtr_arg in $argv[2..-1]
      if test "$_gtr_arg" = "--cd"
        set _gtr_cd 1
      else
        set -a _gtr_command_args "$_gtr_arg"
      end
    end
    if test "$_gtr_cd" = "1"
      set -l _gtr_before_paths (command git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
      command git gtr $_gtr_command $_gtr_command_args
      set -l _gtr_status $status
      test $_gtr_status -ne 0; and return $_gtr_status
      set -l _gtr_after_paths (command git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
      set -l _gtr_new_paths
      for _gtr_path in $_gtr_after_paths
        if not contains -- "$_gtr_path" $_gtr_before_paths
          set -a _gtr_new_paths "$_gtr_path"
        end
      end
      if test (count $_gtr_new_paths) -eq 1
        __FUNC___run_post_cd_hooks "$_gtr_new_paths[1]"
        return $status
      end
      echo "__FUNC__: created worktree, but could not determine new directory for --cd" >&2
      return 0
    end
    command git gtr $argv
  else
    command git gtr $argv
  end
end

# Completion helpers for __FUNC__ wrapper
function ___FUNC___needs_subcommand
  set -l cmd (commandline -opc)
  test (count $cmd) -eq 1
end

function ___FUNC___using_subcommand
  set -l cmd (commandline -opc)
  if test (count $cmd) -ge 2
    for i in $argv
      if test "$cmd[2]" = "$i"
        return 0
      end
    end
  end
  return 1
end

# Subcommands (cd + all git gtr commands)
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a cd -d 'Change directory to worktree'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a new -d 'Create a new worktree'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a pr -d 'Create a pull request worktree'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a go -d 'Navigate to worktree'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a run -d 'Execute command in worktree'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a copy -d 'Copy files between worktrees'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a rm -d 'Remove worktree(s)'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a mv -d 'Rename worktree and branch'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a rename -d 'Rename worktree and branch'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a editor -d 'Open worktree in editor'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a ai -d 'Start AI coding tool'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a ls -d 'List all worktrees'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a list -d 'List all worktrees'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a clean -d 'Remove stale worktrees'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a doctor -d 'Health check'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a adapter -d 'List available adapters'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a config -d 'Manage configuration'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a completion -d 'Generate shell completions'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a init -d 'Generate shell integration'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a trust -d 'Trust .gtrconfig commands'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a version -d 'Show version'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a help -d 'Show help'

# Worktree name completions for cd
complete -f -c __FUNC__ -n '___FUNC___using_subcommand cd' -a '(echo 1; git gtr list --porcelain 2>/dev/null | cut -f2)'
complete -f -c __FUNC__ -n '___FUNC___using_subcommand new pr' -l cd -d 'Create and cd into the new worktree'
FISH
}
