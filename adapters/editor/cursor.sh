#!/usr/bin/env bash
# Cursor editor adapter

# Check if Cursor is available
editor_can_open() {
  command -v cursor >/dev/null 2>&1
}

# Open a directory in Cursor
# Usage: editor_open path
editor_open() {
  local path="$1"

  if ! editor_can_open; then
    log_error "Cursor not found. Install from https://cursor.com or enable the shell command."
    return 1
  fi

  cursor "$path"
}
