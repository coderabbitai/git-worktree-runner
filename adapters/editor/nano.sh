#!/usr/bin/env bash
# Nano editor adapter

# Check if Nano is available
editor_can_open() {
  command -v nano >/dev/null 2>&1
}

# Open a directory in Nano
# Usage: editor_open path
editor_open() {
  local path="$1"

  if ! editor_can_open; then
    log_error "Nano not found. Usually pre-installed on Unix systems."
    return 1
  fi

  # Open nano in the directory (just cd there, nano doesn't open directories)
  log_info "Opening shell in $path (nano doesn't support directory mode)"
  (cd "$path" && exec "$SHELL")
}
