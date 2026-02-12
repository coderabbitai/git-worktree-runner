#!/usr/bin/env bash

# Editor command
cmd_editor() {
  local identifier=""
  local editor=""

  # Parse flags
  while [ $# -gt 0 ]; do
    case "$1" in
      --editor)
        editor="$2"
        shift 2
        ;;
      -*)
        log_error "Unknown flag: $1"
        exit 1
        ;;
      *)
        if [ -z "$identifier" ]; then
          identifier="$1"
        fi
        shift
        ;;
    esac
  done

  if [ -z "$identifier" ]; then
    log_error "Usage: git gtr editor <id|branch> [--editor <name>]"
    exit 1
  fi

  # Get editor from flag or config (with .gtrconfig support)
  if [ -z "$editor" ]; then
    editor=$(_cfg_editor_default)
  fi

  resolve_repo_context || exit 1
  local repo_root="$_ctx_repo_root" base_dir="$_ctx_base_dir" prefix="$_ctx_prefix"

  # Resolve target branch
  local worktree_path branch
  resolve_worktree "$identifier" "$repo_root" "$base_dir" "$prefix" || exit 1
  worktree_path="$_ctx_worktree_path" branch="$_ctx_branch"

  if [ "$editor" = "none" ]; then
    open_in_gui "$worktree_path"
    log_info "Opened in file browser"
  else
    _open_editor "$editor" "$worktree_path" || exit 1
  fi
}