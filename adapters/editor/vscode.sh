#!/usr/bin/env bash
# VS Code editor adapter

# Check if VS Code is available
editor_can_open() {
  command -v code >/dev/null 2>&1
}

# Open a directory or workspace file in VS Code
# Usage: editor_open path [workspace_file]
editor_open() {
  local path="$1"
  local workspace="${2:-}"

  if ! editor_can_open; then
    log_error "VS Code 'code' command not found. Install from https://code.visualstudio.com"
    return 1
  fi

  # Open workspace file if provided, otherwise open directory
  if [ -n "$workspace" ] && [ -f "$workspace" ]; then
    code "$workspace"
  else
    code "$path"
  fi
}
