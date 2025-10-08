#!/usr/bin/env bash
# Neovim editor adapter

# Check if Neovim is available
editor_can_open() {
  command -v nvim >/dev/null 2>&1
}

# Open a directory in Neovim
# Usage: editor_open path
editor_open() {
  local path="$1"

  if ! editor_can_open; then
    log_error "Neovim not found. Install from https://neovim.io"
    return 1
  fi

  # Open neovim in the directory
  (cd "$path" && nvim .)
}
