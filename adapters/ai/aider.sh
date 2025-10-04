#!/usr/bin/env bash
# Aider AI coding assistant adapter

# Check if Aider is available
ai_can_start() {
  command -v aider >/dev/null 2>&1
}

# Start Aider in a directory
# Usage: ai_start path [args...]
ai_start() {
  local path="$1"
  shift

  if ! ai_can_start; then
    log_error "Aider not found. Install with: pip install aider-chat"
    log_info "See https://aider.chat for more information"
    return 1
  fi

  if [ ! -d "$path" ]; then
    log_error "Directory not found: $path"
    return 1
  fi

  # Change to the directory and run aider with any additional arguments
  (cd "$path" && aider "$@")
}
