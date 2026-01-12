#!/usr/bin/env bash
# Cursor editor adapter

# Check if Cursor is available
editor_can_open() {
  command -v cursor >/dev/null 2>&1
}

# Open a directory or workspace file in Cursor
# Usage: editor_open path [workspace_file]
editor_open() {
  local path="$1"
  local workspace="${2:-}"

  if ! editor_can_open; then
    log_error "Cursor not found. Install from https://cursor.com or enable the shell command."
    return 1
  fi

  # Open workspace file if provided, otherwise open directory
  if [ -n "$workspace" ] && [ -f "$workspace" ]; then
    cursor "$workspace"
  else
    cursor "$path"
  fi
}
