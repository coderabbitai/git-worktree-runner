#!/usr/bin/env bash
# Launch helpers for editors and AI tools
# Orchestrates config resolution, adapter loading, and tool invocation
# Used by: cmd_create, cmd_editor, cmd_ai, cmd_doctor

# Config default helpers — single source of truth for editor/AI config keys
_cfg_editor_default() {
  cfg_default gtr.editor.default GTR_EDITOR_DEFAULT "none" defaults.editor
}

_cfg_ai_default() {
  cfg_default gtr.ai.default GTR_AI_DEFAULT "none" defaults.ai
}

# Open a worktree in an editor (shared by _auto_launch_editor and cmd_editor)
# Usage: _open_editor <editor_name> <worktree_path>
# Returns: 0 on success, 1 on adapter load failure
_open_editor() {
  local editor="$1" worktree_path="$2"
  load_editor_adapter "$editor" || return 1
  local workspace_file
  workspace_file=$(resolve_workspace_file "$worktree_path")
  log_step "Opening in $editor..."
  editor_open "$worktree_path" "$workspace_file"
}

# Auto-launch editor for a worktree
_auto_launch_editor() {
  local worktree_path="$1"
  local editor
  editor=$(_cfg_editor_default)
  if [ "$editor" != "none" ]; then
    _open_editor "$editor" "$worktree_path" || log_warn "Failed to open editor"
  else
    if ! open_in_gui "$worktree_path"; then
      log_warn "Could not open file browser"
    else
      log_info "Opened in file browser (no editor configured)"
    fi
  fi
}

# Auto-launch AI tool for a worktree
_auto_launch_ai() {
  local worktree_path="$1"
  local ai_tool
  ai_tool=$(_cfg_ai_default)
  if [ "$ai_tool" = "none" ]; then
    log_warn "No AI tool configured. Set with: git gtr config set gtr.ai.default claude"
  else
    load_ai_adapter "$ai_tool" || return 1
    log_step "Starting $ai_tool..."
    ai_start "$worktree_path" || log_warn "Failed to start AI tool"
  fi
}
