#!/usr/bin/env bash
# Vim editor adapter

# Check if Vim is available
editor_can_open() {
  command -v vim >/dev/null 2>&1
}

# Open a directory in Vim
# Usage: editor_open path
editor_open() {
  local path="$1"

  if ! editor_can_open; then
    log_error "Vim not found. Install via your package manager."
    return 1
  fi

  # Open vim in the directory
  (cd "$path" && vim .)
}
