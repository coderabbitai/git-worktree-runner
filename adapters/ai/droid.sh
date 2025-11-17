#!/usr/bin/env bash
# Droid AI adapter

# Check if Droid is available
ai_can_start() {
  command -v droid >/dev/null 2>&1
}

# Start Droid in a directory
# Usage: ai_start path [args...]
ai_start() {
  local path="$1"
  shift

  if ! ai_can_start; then
    log_error "Droid not found. Install from https://github.com/factory-droid/droid"
    return 1
  fi

  if [ ! -d "$path" ]; then
    log_error "Directory not found: $path"
    return 1
  fi

  (cd "$path" && droid "$@")
}
