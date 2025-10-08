#!/usr/bin/env bash
# Emacs editor adapter

# Check if Emacs is available
editor_can_open() {
  command -v emacs >/dev/null 2>&1
}

# Open a directory in Emacs
# Usage: editor_open path
editor_open() {
  local path="$1"

  if ! editor_can_open; then
    log_error "Emacs not found. Install from https://www.gnu.org/software/emacs/"
    return 1
  fi

  # Open emacs with the directory
  emacs "$path" &
}
