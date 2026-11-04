#!/usr/bin/env bash
# Git configuration can select commands as well as worktree destinations.
# Fail closed when another OS user can modify a config file or replace its path.
# These functions also run in Bash inside generated Bash/Zsh/Fish integration.

_config_safety_error() {
  printf 'gtr: Unsafe Git configuration: %s (%s). Fix ownership/write permissions before running GTR.\n' "$1" "$2" >&2
  return 1
}

# Check a single path component without following symlinks. The caller walks
# both the link's parent chain and its target. Dynamic locals belong to
# _gtr_config_check; never accept a caller-supplied cached validation result.
_config_safety_node() {
  local path="$1" metadata owner mode cached acl
  _config_safety_sticky=0
  for cached in "${_config_safety_checked[@]}"; do
    [ "$cached" != "$path" ] || return 0
  done
  metadata=$(LC_ALL=C stat -c '%u %a' -- "$path" 2>/dev/null) ||
    metadata=$(LC_ALL=C stat -f '%u %p' -- "$path" 2>/dev/null) ||
    { _config_safety_error "$path" 'cannot inspect permissions'; return 1; }
  owner="${metadata%% *}"
  mode="${metadata#* }"
  case "$owner:$mode" in
    *[!0-9:]*|:*) _config_safety_error "$path" 'unknown ownership or permissions'; return 1 ;;
  esac
  case "$mode" in
    ''|*[!0-7]*) _config_safety_error "$path" 'unknown permissions'; return 1 ;;
  esac
  if [ "$owner" != 0 ] && [ "$owner" != "$_config_safety_uid" ]; then
    _config_safety_error "$path" 'owned by another user'; return 1
  fi
  # Symlink mode bits do not control who can replace the link.
  [ ! -L "$path" ] || return 0
  # Git commonly uses the null device to disable a configuration scope. Its
  # writable device contents cannot supply configuration; parents were checked.
  if [ "$path" = /dev/null ] && [ -c "$path" ]; then return 0; fi
  if [ "$((8#$mode & 0022))" -ne 0 ]; then
    # A trusted owner's sticky directory (e.g. /tmp) protects existing entries
    # owned by this user/root. Missing children are handled separately below.
    if [ -d "$path" ] && [ "$((8#$mode & 01000))" -ne 0 ]; then
      _config_safety_sticky=1
    else
      _config_safety_error "$path" 'writable by group or other users'; return 1
    fi
  fi
  # POSIX ACL write access is bounded by the group-class mode bits. macOS ACLs
  # are independent of those bits; conservatively reject write-capable grants.
  if [ "$_config_safety_os" = Darwin ]; then
    acl=$(LC_ALL=C ls -lde "$path" 2>/dev/null) ||
      { _config_safety_error "$path" 'cannot inspect ACL'; return 1; }
    if printf '%s\n' "$acl" | sed '1d' | grep -Eq '^[[:space:]]*[0-9]+:.* allow (.*[, ])?(write|append|delete|add_file|add_subdirectory|delete_child|writeattr|writeextattr|writesecurity|chown)(,|$| )'; then
      _config_safety_error "$path" 'write-capable ACL'; return 1
    fi
  fi
  if [ "$_config_safety_sticky" -eq 0 ]; then
    _config_safety_checked+=("$path")
  fi
}

# Resolve one component at a time: canonicalizing first would hide a writable
# symlink or an unsafe parent of a link whose target is otherwise protected.
_config_safety_path() {
  local pending="$1" current=/ component candidate target links=0 parent_sticky=0
  case "$pending" in /*) ;; *) pending="$(pwd -P)/$pending" ;; esac
  _config_safety_node / || return 1
  while [ -n "$pending" ]; do
    pending="${pending#/}"
    component="${pending%%/*}"
    if [ "$component" = "$pending" ]; then pending=""; else pending="${pending#*/}"; fi
    case "$component" in
      ''|.) continue ;;
      ..)
        current="${current%/*}"; current="${current:-/}"
        _config_safety_node "$current" || return 1
        parent_sticky="$_config_safety_sticky"
        continue
        ;;
    esac
    candidate="${current%/}/$component"
    if [ ! -e "$candidate" ] && [ ! -L "$candidate" ]; then
      # Missing files under private directories cannot be introduced by another
      # user. Sticky directories do not protect names that do not yet exist.
      [ "$parent_sticky" -eq 0 ] ||
        { _config_safety_error "$candidate" 'unprotected missing path'; return 1; }
      return 0
    fi
    _config_safety_node "$candidate" || return 1
    if [ -L "$candidate" ]; then
      links=$((links + 1))
      [ "$links" -le 40 ] || { _config_safety_error "$candidate" 'symlink loop'; return 1; }
      target=$(readlink "$candidate") || return 1
      case "$target" in /*) current=/ ;; esac
      pending="$target${pending:+/$pending}"
    else
      current="$candidate"
      parent_sticky="$_config_safety_sticky"
    fi
  done
}

# Inspect all native Git configuration origins, including includes and linked
# worktree config. Reading configuration/repository paths does not run hooks.
# Use NUL records to preserve whitespace in paths; do not parse Git's quoting.
_gtr_config_check() {
  local _config_safety_uid _config_safety_os _config_safety_sticky=0
  local _config_safety_checked=()
  local origin entry path key value root include_dir complete=0
  _config_safety_uid=$(id -u) || return 1
  _config_safety_os=$(uname -s) || return 1

  # Check primary sources even when empty or absent, so a concurrent writer
  # cannot introduce entries into a previously empty, unreported origin.
  if [ -n "${GIT_CONFIG_GLOBAL:-}" ]; then
    _config_safety_path "$GIT_CONFIG_GLOBAL" || return 1
  else
    _config_safety_path "$HOME/.gitconfig" || return 1
    _config_safety_path "${XDG_CONFIG_HOME:-$HOME/.config}/git/config" || return 1
  fi
  if [ "${GIT_CONFIG_NOSYSTEM:-0}" != 1 ]; then
    _config_safety_path "${GIT_CONFIG_SYSTEM:-/etc/gitconfig}" || return 1
  fi
  if [ -n "${GIT_CONFIG:-}" ]; then
    _config_safety_path "$GIT_CONFIG" || return 1
  fi
  if root=$(git rev-parse --git-common-dir 2>/dev/null); then
    _config_safety_path "$root/config" || return 1
    root=$(git rev-parse --absolute-git-dir 2>/dev/null) || return 1
    _config_safety_path "$root/config.worktree" || return 1
    if root=$(git rev-parse --show-toplevel 2>/dev/null); then
      _config_safety_path "$root/.git" || return 1
    fi
  fi
  while IFS= read -r -d '' origin && IFS= read -r -d '' entry; do
    case "$origin" in
      file:*)
        path="${origin#file:}"
        _config_safety_path "$path" || return 1
        key="${entry%%$'\n'*}"
        # Even an empty included file can later supply commands. Check include
        # destinations as well as the origins of records actually returned.
        case "$key" in
          include.path|includeif.*.path)
            value="${entry#*$'\n'}"
            # Let Git expand ~/ paths, ~user paths, and installation prefixes.
            # The sentinel preserves any trailing newlines in the pathname.
            value=$(git -c "gtr.internalSafetyPath=$value" config --path --get gtr.internalSafetyPath && printf '.') || return 1
            value="${value%.}"
            value="${value%$'\n'}"
            case "$value" in
              '') _config_safety_error "$path" 'empty include path'; return 1 ;;
              /*) ;;
              *)
                case "$path" in */*) include_dir="${path%/*}" ;; *) include_dir=. ;; esac
                value="$include_dir/$value"
                ;;
            esac
            _config_safety_path "$value" || return 1
            ;;
        esac
        ;;
      'command line:'|'standard input:') ;;
      gtr-config-end) complete=1 ;;
      *) _config_safety_error "$origin" 'unknown config origin'; return 1 ;;
    esac
  done < <(git config --null --show-origin --list && printf 'gtr-config-end\0\0')
  [ "$complete" -eq 1 ] || { _config_safety_error 'Git config' 'cannot read configuration'; return 1; }
}
