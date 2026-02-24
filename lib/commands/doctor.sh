#!/usr/bin/env bash

# Doctor command (health check)
cmd_doctor() {
  parse_args "" "$@"

  echo "Running git gtr health check..."
  echo ""

  local issues=0

  # Check git
  if command -v git >/dev/null 2>&1; then
    local git_version
    git_version=$(git --version)
    echo "[OK] Git: $git_version"
  else
    echo "[x] Git: not found"
    issues=$((issues + 1))
  fi

  # Check repo
  local repo_root
  if repo_root=$(discover_repo_root 2>/dev/null); then
    echo "[OK] Repository: $repo_root"

    # Check worktree base dir
    local base_dir prefix
    base_dir=$(resolve_base_dir "$repo_root")
    prefix=$(cfg_default gtr.worktrees.prefix GTR_WORKTREES_PREFIX "")

    if [ -d "$base_dir" ]; then
      local count
      count=$(git worktree list --porcelain 2>/dev/null | grep -c '^worktree ' || true)
      count=$((count - 1))  # Exclude main worktree
      [ "$count" -lt 0 ] && count=0
      echo "[OK] Worktrees directory: $base_dir ($count worktrees)"
    else
      echo "[i] Worktrees directory: $base_dir (not created yet)"
    fi
    if [ -n "$prefix" ]; then
      echo "[i] Worktree prefix: $prefix"
    fi
  else
    echo "[x] Not in a git repository"
    issues=$((issues + 1))
  fi

  # Check configured editor (with .gtrconfig support)
  local editor
  editor=$(_cfg_editor_default)
  if [ "$editor" != "none" ]; then
    if load_editor_adapter "$editor" 2>/dev/null; then
      if editor_can_open 2>/dev/null; then
        echo "[OK] Editor: $editor (found)"
      else
        echo "[!] Editor: $editor (configured but not found in PATH)"
      fi
    else
      echo "[!] Editor: $editor (adapter not found)"
    fi
  else
    echo "[i] Editor: none configured"
  fi

  # Check configured AI tool (with .gtrconfig support)
  local ai_tool
  ai_tool=$(_cfg_ai_default)
  if [ "$ai_tool" != "none" ]; then
    if load_ai_adapter "$ai_tool" 2>/dev/null; then
      if ai_can_start 2>/dev/null; then
        echo "[OK] AI tool: $ai_tool (found)"
      else
        echo "[!] AI tool: $ai_tool (configured but not found in PATH)"
      fi
    else
      echo "[!] AI tool: $ai_tool (adapter not found)"
    fi
  else
    echo "[i] AI tool: none configured"
  fi

  # Check OS
  local os
  os=$(detect_os)
  echo "[OK] Platform: $os"

  # Check hosting provider
  if [ -n "$repo_root" ]; then
    local provider
    provider=$(detect_provider 2>/dev/null) || true
    if [ -n "$provider" ]; then
      echo "[OK] Provider: $provider"
      case "$provider" in
        github)
          if command -v gh >/dev/null 2>&1; then
            echo "[OK] GitHub CLI: $(gh --version 2>/dev/null | head -1)"
          else
            echo "[!] GitHub CLI: not found (needed for: clean --merged)"
          fi
          ;;
        gitlab)
          if command -v glab >/dev/null 2>&1; then
            echo "[OK] GitLab CLI: $(glab --version 2>/dev/null | head -1)"
          else
            echo "[!] GitLab CLI: not found (needed for: clean --merged)"
          fi
          ;;
      esac
    else
      echo "[i] Provider: unknown (set gtr.provider for clean --merged)"
    fi
  fi

  # Check fzf (optional, for interactive picker)
  if command -v fzf >/dev/null 2>&1; then
    echo "[OK] fzf: $(fzf --version 2>/dev/null | awk '{print $1}') (interactive picker: gtr cd)"
  else
    echo "[i] fzf: not found (install for interactive picker: gtr cd)"
  fi

  # Check shell integration (required for gtr cd)
  local _shell_name _rc_file
  _shell_name="$(basename "${SHELL:-bash}")"
  case "$_shell_name" in
    zsh)  _rc_file="$HOME/.zshrc" ;;
    bash) _rc_file="$HOME/.bashrc" ;;
    fish) _rc_file="$HOME/.config/fish/config.fish" ;;
    *)    _rc_file="" ;;
  esac
  if [ -n "$_rc_file" ] && [ -f "$_rc_file" ] && grep -q 'git gtr init' "$_rc_file" 2>/dev/null; then
    echo "[OK] Shell integration: loaded (gtr cd available)"
  else
    echo "[i] Shell integration: eval \"\$(git gtr init $_shell_name)\" in ${_rc_file##*/} for gtr cd"
  fi

  echo ""
  if [ "$issues" -eq 0 ]; then
    echo "Everything looks good!"
    return 0
  else
    echo "[!] Found $issues issue(s)"
    return 1
  fi
}