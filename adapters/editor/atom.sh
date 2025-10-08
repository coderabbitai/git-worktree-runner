#!/usr/bin/env bash
# Atom editor adapter

# Check if Atom is available
editor_can_open() {
  command -v atom >/dev/null 2>&1
}

# Open a directory in Atom
# Usage: editor_open path
editor_open() {
  local path="$1"

  if ! editor_can_open; then
    log_error "Atom not found. Install from https://atom.io"
    return 1
  fi

  atom "$path"
}
