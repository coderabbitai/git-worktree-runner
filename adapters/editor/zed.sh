#!/bin/sh
# Zed editor adapter

# Check if Zed is available
editor_can_open() {
  command -v zed >/dev/null 2>&1
}

# Open a directory in Zed
# Usage: editor_open path
editor_open() {
  local path="$1"

  if ! editor_can_open; then
    log_error "Zed not found. Install from https://zed.dev"
    return 1
  fi

  zed "$path"
}
