#!/usr/bin/env bash

# Init command (generate shell integration for cd support)
cmd_init() {
  local shell="${1:-}"

  case "$shell" in
    bash)
      cat <<'BASH'
# git-gtr shell integration
# Add to ~/.bashrc:
#   eval "$(git gtr init bash)"

gtr() {
  if [ "$#" -gt 0 ] && [ "$1" = "cd" ]; then
    shift
    local dir
    dir="$(command git gtr go "$@")" && cd "$dir" && {
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
          eval "$_gtr_hook" || echo "gtr: postCd hook failed: $_gtr_hook" >&2
        done <<< "$_gtr_hooks"
        unset WORKTREE_PATH REPO_ROOT BRANCH
      fi
    }
  else
    command git gtr "$@"
  fi
}

# Forward completions to gtr wrapper
if type _git_gtr &>/dev/null; then
  complete -F _git_gtr gtr
fi
BASH
      ;;
    zsh)
      cat <<'ZSH'
# git-gtr shell integration
# Add to ~/.zshrc:
#   eval "$(git gtr init zsh)"

gtr() {
  if [ "$#" -gt 0 ] && [ "$1" = "cd" ]; then
    shift
    local dir
    dir="$(command git gtr go "$@")" && cd "$dir" && {
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
          eval "$_gtr_hook" || echo "gtr: postCd hook failed: $_gtr_hook" >&2
        done <<< "$_gtr_hooks"
        unset WORKTREE_PATH REPO_ROOT BRANCH
      fi
    }
  else
    command git gtr "$@"
  fi
}

# Forward completions to gtr wrapper
if (( $+functions[_git-gtr] )); then
  compdef gtr=git-gtr
fi
ZSH
      ;;
    fish)
      cat <<'FISH'
# git-gtr shell integration
# Add to ~/.config/fish/config.fish:
#   git gtr init fish | source

function gtr
  if test (count $argv) -gt 0; and test "$argv[1]" = "cd"
    set -l dir (command git gtr go $argv[2..])
    and cd $dir
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
              eval "$_gtr_hook"; or echo "gtr: postCd hook failed: $_gtr_hook" >&2
            end
          end
        end
      end
    end
  else
    command git gtr $argv
  end
end

# Forward completions to gtr wrapper
complete -c gtr -w git-gtr
FISH
      ;;
    ""|--help|-h)
      echo "Generate shell integration for git gtr"
      echo ""
      echo "Usage: git gtr init <shell>"
      echo ""
      echo "This outputs a gtr() shell function that enables:"
      echo "  gtr cd <branch>    Change directory to worktree"
      echo "  gtr <command>      Passes through to git gtr"
      echo ""
      echo "Shells:"
      echo "  bash    Generate Bash integration"
      echo "  zsh     Generate Zsh integration"
      echo "  fish    Generate Fish integration"
      echo ""
      echo "Examples:"
      echo "  # Bash: add to ~/.bashrc"
      echo "  eval \"\$(git gtr init bash)\""
      echo ""
      echo "  # Zsh: add to ~/.zshrc"
      echo "  eval \"\$(git gtr init zsh)\""
      echo ""
      echo "  # Fish: add to ~/.config/fish/config.fish"
      echo "  git gtr init fish | source"
      return 0
      ;;
    *)
      log_error "Unknown shell: $shell"
      log_error "Supported shells: bash, zsh, fish"
      log_info "Run 'git gtr init --help' for usage"
      return 1
      ;;
  esac
}