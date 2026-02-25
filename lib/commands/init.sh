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

  # Generate output (cached to ~/.cache/gtr/, auto-invalidates on version change)
  local cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/gtr"
  local cache_file="$cache_dir/init-${func_name}.${shell}"
  local cache_stamp="# gtr-cache: version=${GTR_VERSION:-unknown} func=$func_name shell=$shell"

  # Return cached output if version matches
  if [ -f "$cache_file" ]; then
    local first_line
    first_line="$(head -1 "$cache_file")"
    if [ "$first_line" = "$cache_stamp" ]; then
      tail -n +2 "$cache_file"
      return 0
    fi
  fi

  # Generate, cache, and output
  local output
  output="$("$generator" | sed "s/__FUNC__/$func_name/g")"
  mkdir -p "$cache_dir"
  printf '%s\n%s\n' "$cache_stamp" "$output" > "$cache_file"
  printf '%s\n' "$output"
}

_init_bash() {
  cat <<'BASH'
# git-gtr shell integration (output is cached to ~/.cache/gtr/)
# Add to ~/.bashrc:
#   eval "$(git gtr init bash)"
# Faster: source the cache file directly (see git gtr help init)

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
      local _gtr_selection
      _gtr_selection="$(printf '%s\n' "$_gtr_porcelain" | fzf \
        --delimiter=$'\t' \
        --with-nth=2 \
        --ansi \
        --layout=reverse \
        --border \
        --prompt='Worktree> ' \
        --header='enter:cd │ ctrl-e:editor │ ctrl-a:ai │ ctrl-d:delete │ ctrl-y:copy │ ctrl-r:refresh' \
        --preview='git -C {1} log --oneline --graph --color=always -15 2>/dev/null; echo "---"; git -C {1} status --short 2>/dev/null' \
        --preview-window=right:50% \
        --bind='ctrl-e:execute(git gtr editor {2})' \
        --bind='ctrl-a:execute(git gtr ai {2})' \
        --bind='ctrl-d:execute(git gtr rm {2})+reload(git gtr list --porcelain)' \
        --bind='ctrl-y:execute(git gtr copy {2})' \
        --bind='ctrl-r:reload(git gtr list --porcelain)')" || return 0
      [ -z "$_gtr_selection" ] && return 0
      dir="$(printf '%s' "$_gtr_selection" | cut -f1)"
    elif [ "$#" -eq 0 ]; then
      echo "Usage: __FUNC__ cd <branch>" >&2
      echo "Tip: Install fzf for an interactive picker (https://github.com/junegunn/fzf)" >&2
      return 1
    else
      dir="$(command git gtr go "$@")" || return $?
    fi
    cd "$dir" && {
      local _gtr_hooks _gtr_hook _gtr_seen _gtr_config_file
      _gtr_hooks=""
      _gtr_seen=""
      # Read from git config (local > global > system)
      _gtr_hooks="$(git config --get-all gtr.hook.postCd 2>/dev/null)" || true
      # Read from .gtrconfig if it exists
      _gtr_config_file="$(git rev-parse --show-toplevel 2>/dev/null)/.gtrconfig"
      if [ -f "$_gtr_config_file" ]; then
        local _gtr_file_hooks
        _gtr_file_hooks="$(git config -f "$_gtr_config_file" --get-all hooks.postCd 2>/dev/null)" || true
        if [ -n "$_gtr_file_hooks" ]; then
          if [ -n "$_gtr_hooks" ]; then
            _gtr_hooks="$_gtr_hooks"$'\n'"$_gtr_file_hooks"
          else
            _gtr_hooks="$_gtr_file_hooks"
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
          eval "$_gtr_hook" || echo "__FUNC__: postCd hook failed: $_gtr_hook" >&2
        done <<< "$_gtr_hooks"
        unset WORKTREE_PATH REPO_ROOT BRANCH
      fi
    }
  else
    command git gtr "$@"
  fi
}

# Completion for __FUNC__ wrapper
___FUNC___completion() {
  local cur
  cur="${COMP_WORDS[COMP_CWORD]}"

  if [ "$COMP_CWORD" -eq 1 ]; then
    # First argument: cd + all git-gtr subcommands
    COMPREPLY=($(compgen -W "cd new go run copy editor ai rm mv rename ls list clean doctor adapter config completion init help version" -- "$cur"))
  elif [ "${COMP_WORDS[1]}" = "cd" ] && [ "$COMP_CWORD" -eq 2 ]; then
    # Worktree names for cd
    local worktrees
    worktrees="1 $(git gtr list --porcelain 2>/dev/null | cut -f2 | tr '\n' ' ')"
    COMPREPLY=($(compgen -W "$worktrees" -- "$cur"))
  elif type _git_gtr &>/dev/null; then
    # Delegate to git-gtr completions (adjust words to match expected format)
    COMP_WORDS=(git gtr "${COMP_WORDS[@]:1}")
    (( COMP_CWORD += 1 ))
    _git_gtr
  fi
}
complete -F ___FUNC___completion __FUNC__
BASH
}

_init_zsh() {
  cat <<'ZSH'
# git-gtr shell integration (output is cached to ~/.cache/gtr/)
# Add to ~/.zshrc:
#   eval "$(git gtr init zsh)"
# Faster: source the cache file directly (see git gtr help init)

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
      local _gtr_selection
      _gtr_selection="$(printf '%s\n' "$_gtr_porcelain" | fzf \
        --delimiter=$'\t' \
        --with-nth=2 \
        --ansi \
        --layout=reverse \
        --border \
        --prompt='Worktree> ' \
        --header='enter:cd │ ctrl-e:editor │ ctrl-a:ai │ ctrl-d:delete │ ctrl-y:copy │ ctrl-r:refresh' \
        --preview='git -C {1} log --oneline --graph --color=always -15 2>/dev/null; echo "---"; git -C {1} status --short 2>/dev/null' \
        --preview-window=right:50% \
        --bind='ctrl-e:execute(git gtr editor {2})' \
        --bind='ctrl-a:execute(git gtr ai {2})' \
        --bind='ctrl-d:execute(git gtr rm {2})+reload(git gtr list --porcelain)' \
        --bind='ctrl-y:execute(git gtr copy {2})' \
        --bind='ctrl-r:reload(git gtr list --porcelain)')" || return 0
      [ -z "$_gtr_selection" ] && return 0
      dir="$(printf '%s' "$_gtr_selection" | cut -f1)"
    elif [ "$#" -eq 0 ]; then
      echo "Usage: __FUNC__ cd <branch>" >&2
      echo "Tip: Install fzf for an interactive picker (https://github.com/junegunn/fzf)" >&2
      return 1
    else
      dir="$(command git gtr go "$@")" || return $?
    fi
    cd "$dir" && {
      local _gtr_hooks _gtr_hook _gtr_seen _gtr_config_file
      _gtr_hooks=""
      _gtr_seen=""
      # Read from git config (local > global > system)
      _gtr_hooks="$(git config --get-all gtr.hook.postCd 2>/dev/null)" || true
      # Read from .gtrconfig if it exists
      _gtr_config_file="$(git rev-parse --show-toplevel 2>/dev/null)/.gtrconfig"
      if [ -f "$_gtr_config_file" ]; then
        local _gtr_file_hooks
        _gtr_file_hooks="$(git config -f "$_gtr_config_file" --get-all hooks.postCd 2>/dev/null)" || true
        if [ -n "$_gtr_file_hooks" ]; then
          if [ -n "$_gtr_hooks" ]; then
            _gtr_hooks="$_gtr_hooks"$'\n'"$_gtr_file_hooks"
          else
            _gtr_hooks="$_gtr_file_hooks"
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
          eval "$_gtr_hook" || echo "__FUNC__: postCd hook failed: $_gtr_hook" >&2
        done <<< "$_gtr_hooks"
        unset WORKTREE_PATH REPO_ROOT BRANCH
      fi
    }
  else
    command git gtr "$@"
  fi
}

# Completion for __FUNC__ wrapper
___FUNC___completion() {
  local at_subcmd=0
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
        --header='enter:cd │ ctrl-e:editor │ ctrl-a:ai │ ctrl-d:delete │ ctrl-y:copy │ ctrl-r:refresh' \
        --preview='git -C {1} log --oneline --graph --color=always -15 2>/dev/null; echo "---"; git -C {1} status --short 2>/dev/null' \
        --preview-window=right:50% \
        --bind='ctrl-e:execute(git gtr editor {2})' \
        --bind='ctrl-a:execute(git gtr ai {2})' \
        --bind='ctrl-d:execute(git gtr rm {2})+reload(git gtr list --porcelain)' \
        --bind='ctrl-y:execute(git gtr copy {2})' \
        --bind='ctrl-r:reload(git gtr list --porcelain)')
      or return 0
      test -z "$_gtr_selection"; and return 0
      set dir (string split \t -- "$_gtr_selection")[1]
    else if test (count $argv) -eq 1
      echo "Usage: __FUNC__ cd <branch>" >&2
      echo "Tip: Install fzf for an interactive picker (https://github.com/junegunn/fzf)" >&2
      return 1
    else
      set dir (command git gtr go $argv[2..])
      or return $status
    end
    cd $dir
    and begin
      set -l _gtr_hooks
      set -l _gtr_seen
      # Read from git config (local > global > system)
      set -l _gtr_git_hooks (git config --get-all gtr.hook.postCd 2>/dev/null)
      # Read from .gtrconfig if it exists
      set -l _gtr_config_file (git rev-parse --show-toplevel 2>/dev/null)"/.gtrconfig"
      set -l _gtr_file_hooks
      if test -f "$_gtr_config_file"
        set _gtr_file_hooks (git config -f "$_gtr_config_file" --get-all hooks.postCd 2>/dev/null)
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
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a version -d 'Show version'
complete -f -c __FUNC__ -n '___FUNC___needs_subcommand' -a help -d 'Show help'

# Worktree name completions for cd
complete -f -c __FUNC__ -n '___FUNC___using_subcommand cd' -a '(echo 1; git gtr list --porcelain 2>/dev/null | cut -f2)'
FISH
}
