#!/usr/bin/env bash

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
  local cache_file="$cache_dir/init-${func_name}.${shell}"
  local cache_schema="${GTR_INIT_CACHE_VERSION:-5}"
  local cache_stamp="# gtr-cache: version=${GTR_VERSION:-unknown} init=${cache_schema} func=$func_name shell=$shell"

  # Return cached output if version matches
  if [ -f "$cache_file" ]; then
    local first_line
    first_line="$(head -1 "$cache_file")"
    if [ "$first_line" = "$cache_stamp" ]; then
      tail -n +2 "$cache_file"
      return 0
    fi
  fi

  # Generate, output, and cache (output first so set -e cache failures don't swallow it)
  local output
  output="$("$generator" | sed "s/__FUNC__/$func_name/g")"
  printf '%s\n' "$output"
  if mkdir -p "$cache_dir" 2>/dev/null; then
    printf '%s\n%s\n' "$cache_stamp" "$output" > "$cache_file" 2>/dev/null || true
  fi
}

_init_emit_posix_trust_helpers() {
  local shell_prelude="$1"
  local template

  template=$(cat <<'EOF'
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
  local _gtr_hook_defs
  _gtr_hook_defs="$(git config -f "$_gtr_config_file" --get-regexp '^hooks\.' 2>/dev/null)" || return 1
  printf '%s\n' "$_gtr_hook_defs" | shasum -a 256 | cut -d' ' -f1
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
  local _gtr_hook_hash _gtr_repo_root
  _gtr_hook_hash="$(__FUNC___hooks_current_content_hash "$_gtr_config_file" 2>/dev/null)" || return 1
  _gtr_repo_root="$(__FUNC___hooks_repo_root "$_gtr_config_file" 2>/dev/null)" || return 1
  printf '%s\n%s\n' "$_gtr_repo_root" "$_gtr_hook_hash" | shasum -a 256 | cut -d' ' -f1
}

__FUNC___hooks_marker_matches_config() {
__SHELL_PRELUDE__
  local _gtr_trust_path="$1"
  local _gtr_config_file="$2"
  local _gtr_marker _gtr_canonical_config
  [ -f "$_gtr_trust_path" ] || return 1
  _gtr_marker="$(cat "$_gtr_trust_path" 2>/dev/null)" || return 1
  _gtr_canonical_config="$(__FUNC___hooks_canonical_config_path "$_gtr_config_file" 2>/dev/null)" || return 1
  [ "$_gtr_marker" = "$_gtr_canonical_config" ]
}

__FUNC___hooks_are_trusted() {
__SHELL_PRELUDE__
  local _gtr_config_file="$1"
  local _gtr_trust_dir="$2"
  local _gtr_trust_key
  _gtr_trust_key="$(__FUNC___hooks_current_trust_key "$_gtr_config_file" 2>/dev/null)" || return 1
  __FUNC___hooks_marker_matches_config "$_gtr_trust_dir/$_gtr_trust_key" "$_gtr_config_file"
}
EOF
)

  printf '%s\n' "${template//__SHELL_PRELUDE__/$shell_prelude}"
}

_init_emit_fish_trust_helpers() {
  cat <<'FISH'
function __FUNC___gtrconfig_path
  set -l _gtr_git_common_dir (git rev-parse --git-common-dir 2>/dev/null)
  test -n "$_gtr_git_common_dir"; or return 1

  if test "$_gtr_git_common_dir" = ".git"
    set -l _gtr_repo_root (git rev-parse --show-toplevel 2>/dev/null)
    test -n "$_gtr_repo_root"; or return 1
    printf '%s/.gtrconfig\n' "$_gtr_repo_root"
  else
    printf '%s/.gtrconfig\n' (string replace -r '/\\.git$' '' -- "$_gtr_git_common_dir")
  end
end

function __FUNC___hooks_current_content_hash
  set -l _gtr_config_file "$argv[1]"
  set -l _gtr_hook_defs (git config -f "$_gtr_config_file" --get-regexp '^hooks\.' 2>/dev/null)
  test $status -eq 0; or return 1
  printf '%s\n' "$_gtr_hook_defs" | shasum -a 256 | cut -d' ' -f1
end

function __FUNC___hooks_repo_root
  set -l _gtr_config_file "$argv[1]"
  cd (dirname "$_gtr_config_file") 2>/dev/null; and pwd -P
end

function __FUNC___hooks_canonical_config_path
  set -l _gtr_config_file "$argv[1]"
  set -l _gtr_repo_root (__FUNC___hooks_repo_root "$_gtr_config_file" 2>/dev/null)
  test -n "$_gtr_repo_root"; or return 1
  printf '%s/%s\n' "$_gtr_repo_root" (basename "$_gtr_config_file")
end

function __FUNC___hooks_current_trust_key
  set -l _gtr_config_file "$argv[1]"
  set -l _gtr_hook_hash (__FUNC___hooks_current_content_hash "$_gtr_config_file" 2>/dev/null)
  test -n "$_gtr_hook_hash"; or return 1
  set -l _gtr_repo_root (__FUNC___hooks_repo_root "$_gtr_config_file" 2>/dev/null)
  test -n "$_gtr_repo_root"; or return 1
  printf '%s\n%s\n' "$_gtr_repo_root" "$_gtr_hook_hash" | shasum -a 256 | cut -d' ' -f1
end

function __FUNC___hooks_marker_matches_config
  set -l _gtr_trust_path "$argv[1]"
  set -l _gtr_config_file "$argv[2]"
  test -f "$_gtr_trust_path"; or return 1
  set -l _gtr_marker (cat "$_gtr_trust_path" 2>/dev/null)
  set -l _gtr_canonical_config (__FUNC___hooks_canonical_config_path "$_gtr_config_file" 2>/dev/null)
  test "$_gtr_marker" = "$_gtr_canonical_config"
end

function __FUNC___hooks_are_trusted
  set -l _gtr_config_file "$argv[1]"
  set -l _gtr_trust_dir "$argv[2]"
  set -l _gtr_trust_key (__FUNC___hooks_current_trust_key "$_gtr_config_file" 2>/dev/null)
  test -n "$_gtr_trust_key"; or return 1
  __FUNC___hooks_marker_matches_config "$_gtr_trust_dir/$_gtr_trust_key" "$_gtr_config_file"
end
FISH
}

_init_bash() {
  cat <<'BASH'
# git-gtr shell integration (cached to ~/.cache/gtr/)
# Setup: see git gtr help init
BASH
  _init_emit_posix_trust_helpers ""
  cat <<'BASH'
__FUNC___run_post_cd_hooks() {
  local dir="$1"
  local _gtr_trust_dir="${XDG_CONFIG_HOME:-$HOME/.config}/gtr/trusted"

  cd "$dir" && {
    local _gtr_hooks _gtr_hook _gtr_seen _gtr_config_file
    _gtr_hooks=""
    _gtr_seen=""
    # Read from git config (local > global > system)
    _gtr_hooks="$(git config --get-all gtr.hook.postCd 2>/dev/null)" || true
    # Read from .gtrconfig if it exists — only if trusted
    _gtr_config_file="$(__FUNC___gtrconfig_path 2>/dev/null)" || true
    if [ -f "$_gtr_config_file" ]; then
      local _gtr_file_hooks
      _gtr_file_hooks="$(git config -f "$_gtr_config_file" --get-all hooks.postCd 2>/dev/null)" || true
      if [ -n "$_gtr_file_hooks" ]; then
        # Verify trust before including .gtrconfig hooks
        if __FUNC___hooks_are_trusted "$_gtr_config_file" "$_gtr_trust_dir"; then
          if [ -n "$_gtr_hooks" ]; then
            _gtr_hooks="$_gtr_hooks"$'\n'"$_gtr_file_hooks"
          else
            _gtr_hooks="$_gtr_file_hooks"
          fi
        else
          echo "__FUNC__: Untrusted .gtrconfig hooks skipped — run 'git gtr trust' to approve" >&2
        fi
      fi
    fi
    if [ -n "$_gtr_hooks" ]; then
      # Deduplicate while preserving order
      _gtr_seen=""
      export WORKTREE_PATH="$dir"
      export REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
      export BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
      while IFS= read -r _gtr_hook; do
        [ -z "$_gtr_hook" ] && continue
        case "$_gtr_seen" in *"|$_gtr_hook|"*) continue ;; esac
        _gtr_seen="$_gtr_seen|$_gtr_hook|"
        eval "$_gtr_hook" </dev/null || echo "__FUNC__: postCd hook failed: $_gtr_hook" >&2
      done <<< "$_gtr_hooks"
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
      _gtr_porcelain="$(command git gtr list --porcelain)"
      if [ "$(printf '%s\n' "$_gtr_porcelain" | wc -l)" -le 1 ]; then
        echo "No worktrees to pick from. Create one with: git gtr new <branch>" >&2
        return 0
      fi
      local _gtr_selection _gtr_key _gtr_line _gtr_branch
      _gtr_selection="$(printf '%s\n' "$_gtr_porcelain" | fzf \
        --delimiter=$'\t' \
        --with-nth=2 \
        --ansi \
        --layout=reverse \
        --border \
        --prompt='Worktree> ' \
        --header='enter:cd │ ctrl-n:new │ ctrl-e:editor │ ctrl-a:ai │ ctrl-d:delete │ ctrl-y:copy │ ctrl-r:refresh' \
        --expect=ctrl-n,ctrl-a,ctrl-e \
        --preview='git -C {1} log --oneline --graph --color=always -15 2>/dev/null; echo "---"; git -C {1} status --short 2>/dev/null' \
        --preview-window=right:50% \
        --bind='ctrl-d:execute(git gtr rm {2} > /dev/tty 2>&1 < /dev/tty)+reload(git gtr list --porcelain)' \
        --bind='ctrl-y:execute(git gtr copy {2} > /dev/tty 2>&1 < /dev/tty)' \
        --bind='ctrl-r:reload(git gtr list --porcelain)')" || return 0
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
        command git gtr ai "$(printf '%s' "$_gtr_line" | cut -f2)"
        return $?
      elif [ "$_gtr_key" = "ctrl-e" ]; then
        command git gtr editor "$(printf '%s' "$_gtr_line" | cut -f2)"
        return $?
      fi
      dir="$(printf '%s' "$_gtr_line" | cut -f1)"
    elif [ "$#" -eq 0 ]; then
      echo "Usage: __FUNC__ cd <branch>" >&2
      echo "Tip: Install fzf for an interactive picker (https://github.com/junegunn/fzf)" >&2
      return 1
    else
      dir="$(command git gtr go "$@")" || return $?
    fi
    __FUNC___run_post_cd_hooks "$dir"
  elif [ "$#" -gt 0 ] && [ "$1" = "new" ]; then
    local -a _gtr_original_args=("$@") _gtr_new_args=()
    local _gtr_arg _gtr_new_cd=0 _gtr_before_paths _gtr_after_paths
    local _gtr_path _gtr_new_dir="" _gtr_new_count=0 _gtr_status
    shift
    for _gtr_arg in "$@"; do
      if [ "$_gtr_arg" = "--cd" ]; then
        _gtr_new_cd=1
      else
        _gtr_new_args+=("$_gtr_arg")
      fi
    done
    if [ "$_gtr_new_cd" -eq 1 ]; then
      _gtr_before_paths="$(command git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')"
      command git gtr new "${_gtr_new_args[@]}"
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
    COMPREPLY=($(compgen -W "cd new go run copy editor ai rm mv rename ls list clean doctor adapter config completion init trust help version" -- "$cur"))
  elif [ "${COMP_WORDS[1]}" = "cd" ] && [ "$COMP_CWORD" -eq 2 ]; then
    # Worktree names for cd
    local worktrees
    worktrees="1 $(git gtr list --porcelain 2>/dev/null | cut -f2 | tr '\n' ' ')"
    COMPREPLY=($(compgen -W "$worktrees" -- "$cur"))
  elif [ "${COMP_WORDS[1]}" = "new" ] && [[ "$cur" == -* ]]; then
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
  cat <<'ZSH'
__FUNC___run_post_cd_hooks() {
  emulate -L zsh
  local dir="$1"
  local _gtr_trust_dir="${XDG_CONFIG_HOME:-$HOME/.config}/gtr/trusted"

  cd "$dir" && {
    local _gtr_hooks _gtr_hook _gtr_seen _gtr_config_file
    _gtr_hooks=""
    _gtr_seen=""
    # Read from git config (local > global > system)
    _gtr_hooks="$(git config --get-all gtr.hook.postCd 2>/dev/null)" || true
    # Read from .gtrconfig if it exists — only if trusted
    _gtr_config_file="$(__FUNC___gtrconfig_path 2>/dev/null)" || true
    if [ -f "$_gtr_config_file" ]; then
      local _gtr_file_hooks
      _gtr_file_hooks="$(git config -f "$_gtr_config_file" --get-all hooks.postCd 2>/dev/null)" || true
      if [ -n "$_gtr_file_hooks" ]; then
        # Verify trust before including .gtrconfig hooks
        if __FUNC___hooks_are_trusted "$_gtr_config_file" "$_gtr_trust_dir"; then
          if [ -n "$_gtr_hooks" ]; then
            _gtr_hooks="$_gtr_hooks"$'\n'"$_gtr_file_hooks"
          else
            _gtr_hooks="$_gtr_file_hooks"
          fi
        else
          echo "__FUNC__: Untrusted .gtrconfig hooks skipped — run 'git gtr trust' to approve" >&2
        fi
      fi
    fi
    if [ -n "$_gtr_hooks" ]; then
      # Deduplicate while preserving order
      _gtr_seen=""
      export WORKTREE_PATH="$dir"
      export REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"
      export BRANCH="$(git rev-parse --abbrev-ref HEAD 2>/dev/null)"
      while IFS= read -r _gtr_hook; do
        [ -z "$_gtr_hook" ] && continue
        case "$_gtr_seen" in *"|$_gtr_hook|"*) continue ;; esac
        _gtr_seen="$_gtr_seen|$_gtr_hook|"
        eval "$_gtr_hook" </dev/null || echo "__FUNC__: postCd hook failed: $_gtr_hook" >&2
      done <<< "$_gtr_hooks"
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
      _gtr_porcelain="$(command git gtr list --porcelain)"
      if [ "$(printf '%s\n' "$_gtr_porcelain" | wc -l)" -le 1 ]; then
        echo "No worktrees to pick from. Create one with: git gtr new <branch>" >&2
        return 0
      fi
      local _gtr_selection _gtr_key _gtr_line _gtr_branch
      _gtr_selection="$(printf '%s\n' "$_gtr_porcelain" | fzf \
        --delimiter=$'\t' \
        --with-nth=2 \
        --ansi \
        --layout=reverse \
        --border \
        --prompt='Worktree> ' \
        --header='enter:cd │ ctrl-n:new │ ctrl-e:editor │ ctrl-a:ai │ ctrl-d:delete │ ctrl-y:copy │ ctrl-r:refresh' \
        --expect=ctrl-n,ctrl-a,ctrl-e \
        --preview='git -C {1} log --oneline --graph --color=always -15 2>/dev/null; echo "---"; git -C {1} status --short 2>/dev/null' \
        --preview-window=right:50% \
        --bind='ctrl-d:execute(git gtr rm {2} > /dev/tty 2>&1 < /dev/tty)+reload(git gtr list --porcelain)' \
        --bind='ctrl-y:execute(git gtr copy {2} > /dev/tty 2>&1 < /dev/tty)' \
        --bind='ctrl-r:reload(git gtr list --porcelain)')" || return 0
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
        command git gtr ai "$(printf '%s' "$_gtr_line" | cut -f2)"
        return $?
      elif [ "$_gtr_key" = "ctrl-e" ]; then
        command git gtr editor "$(printf '%s' "$_gtr_line" | cut -f2)"
        return $?
      fi
      dir="$(printf '%s' "$_gtr_line" | cut -f1)"
    elif [ "$#" -eq 0 ]; then
      echo "Usage: __FUNC__ cd <branch>" >&2
      echo "Tip: Install fzf for an interactive picker (https://github.com/junegunn/fzf)" >&2
      return 1
    else
      dir="$(command git gtr go "$@")" || return $?
    fi
    __FUNC___run_post_cd_hooks "$dir"
  elif [ "$#" -gt 0 ] && [ "$1" = "new" ]; then
    local -a _gtr_original_args _gtr_new_args
    local _gtr_arg _gtr_new_cd=0 _gtr_before_paths _gtr_after_paths
    local _gtr_path _gtr_new_dir="" _gtr_new_count=0 _gtr_status
    _gtr_original_args=("$@")
    _gtr_new_args=()
    shift
    for _gtr_arg in "$@"; do
      if [ "$_gtr_arg" = "--cd" ]; then
        _gtr_new_cd=1
      else
        _gtr_new_args+=("$_gtr_arg")
      fi
    done
    if [ "$_gtr_new_cd" -eq 1 ]; then
      _gtr_before_paths="$(command git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')"
      command git gtr new "${_gtr_new_args[@]}"
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

  if [[ "${words[2]}" == "new" && "$current_word" == -* ]]; then
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
  cat <<'FISH'
function __FUNC___run_post_cd_hooks
  set -l dir "$argv[1]"
  set -l _gtr_trust_dir "$HOME/.config/gtr/trusted"
  if set -q XDG_CONFIG_HOME
    set _gtr_trust_dir "$XDG_CONFIG_HOME/gtr/trusted"
  end
  cd $dir
  and begin
    set -l _gtr_hooks
    set -l _gtr_seen
    # Read from git config (local > global > system)
    set -l _gtr_git_hooks (git config --get-all gtr.hook.postCd 2>/dev/null)
    # Read from .gtrconfig if it exists — only if trusted
    set -l _gtr_config_file (__FUNC___gtrconfig_path 2>/dev/null)
    set -l _gtr_file_hooks
    if test -f "$_gtr_config_file"
      set -l _gtr_candidate_hooks (git config -f "$_gtr_config_file" --get-all hooks.postCd 2>/dev/null)
      if test (count $_gtr_candidate_hooks) -gt 0
        # Verify trust before including .gtrconfig hooks
        if __FUNC___hooks_are_trusted "$_gtr_config_file" "$_gtr_trust_dir"
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
      set -l _gtr_porcelain (command git gtr list --porcelain)
      if test (count $_gtr_porcelain) -le 1
        echo "No worktrees to pick from. Create one with: git gtr new <branch>" >&2
        return 0
      end
      set -l _gtr_selection (printf '%s\n' $_gtr_porcelain | fzf \
        --delimiter=\t \
        --with-nth=2 \
        --ansi \
        --layout=reverse \
        --border \
        --prompt='Worktree> ' \
        --header='enter:cd │ ctrl-n:new │ ctrl-e:editor │ ctrl-a:ai │ ctrl-d:delete │ ctrl-y:copy │ ctrl-r:refresh' \
        --expect=ctrl-n,ctrl-a,ctrl-e \
        --preview='git -C {1} log --oneline --graph --color=always -15 2>/dev/null; echo "---"; git -C {1} status --short 2>/dev/null' \
        --preview-window=right:50% \
        --bind='ctrl-d:execute(git gtr rm {2} > /dev/tty 2>&1 < /dev/tty)+reload(git gtr list --porcelain)' \
        --bind='ctrl-y:execute(git gtr copy {2} > /dev/tty 2>&1 < /dev/tty)' \
        --bind='ctrl-r:reload(git gtr list --porcelain)')
      or return 0
      test -z "$_gtr_selection"; and return 0
      # --expect gives two lines: key (index 1) and selection (index 2)
      # Fish collapses empty lines in command substitution, so when Enter
      # is pressed the empty key line disappears and count drops to 1.
      if test (count $_gtr_selection) -eq 1
        set -l _gtr_key ""
        set -l _gtr_line "$_gtr_selection[1]"
      else
        set -l _gtr_key "$_gtr_selection[1]"
        set -l _gtr_line "$_gtr_selection[2]"
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
        command git gtr ai (string split \t -- "$_gtr_line")[2]
        return $status
      else if test "$_gtr_key" = "ctrl-e"
        command git gtr editor (string split \t -- "$_gtr_line")[2]
        return $status
      end
      set dir (string split \t -- "$_gtr_line")[1]
    else if test (count $argv) -eq 1
      echo "Usage: __FUNC__ cd <branch>" >&2
      echo "Tip: Install fzf for an interactive picker (https://github.com/junegunn/fzf)" >&2
      return 1
    else
      set dir (command git gtr go $argv[2..])
      or return $status
    end
    __FUNC___run_post_cd_hooks "$dir"
  else if test (count $argv) -gt 0; and test "$argv[1]" = "new"
    set -l _gtr_new_cd 0
    set -l _gtr_new_args
    for _gtr_arg in $argv[2..-1]
      if test "$_gtr_arg" = "--cd"
        set _gtr_new_cd 1
      else
        set -a _gtr_new_args "$_gtr_arg"
      end
    end
    if test "$_gtr_new_cd" = "1"
      set -l _gtr_before_paths (command git worktree list --porcelain 2>/dev/null | sed -n 's/^worktree //p')
      command git gtr new $_gtr_new_args
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
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a trust -d 'Trust .gtrconfig hooks'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a version -d 'Show version'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a help -d 'Show help'

# Worktree name completions for cd
complete -f -c __FUNC__ -n '___FUNC___using_subcommand cd' -a '(echo 1; git gtr list --porcelain 2>/dev/null | cut -f2)'
complete -f -c __FUNC__ -n '___FUNC___using_subcommand new' -l cd -d 'Create and cd into the new worktree'
FISH
}
