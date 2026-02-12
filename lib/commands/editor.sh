#!/usr/bin/env bash
# shellcheck disable=SC2154

# Editor command
cmd_editor() {
  parse_args "--editor: value" "$@"

  local identifier="${_pa_positional[0]:-}"
  local editor="${_arg_editor:-}"

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
  local worktree_path
  resolve_worktree "$identifier" "$repo_root" "$base_dir" "$prefix" || exit 1

  worktree_path="$_ctx_worktree_path"

  if [ "$editor" = "none" ]; then
    if ! open_in_gui "$worktree_path"; then
      log_warn "Could not open file browser"
    else
      log_info "Opened in file browser"
    fi
  else
    _open_editor "$editor" "$worktree_path" || exit 1
  fi
}