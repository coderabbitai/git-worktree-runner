#!/bin/sh
# Cursor AI agent adapter

# Check if Cursor agent/CLI is available
ai_can_start() {
  command -v cursor-agent >/dev/null 2>&1 || command -v cursor >/dev/null 2>&1
}

# Start Cursor agent in a directory
# Usage: ai_start path [args...]
ai_start() {
  local path="$1"
  shift

  if ! ai_can_start; then
    log_error "Cursor not found. Install from https://cursor.com"
    log_info "Make sure to enable the Cursor CLI/agent from the app"
    return 1
  fi

  if [ ! -d "$path" ]; then
    log_error "Directory not found: $path"
    return 1
  fi

  # Try cursor-agent first, then fallback to cursor CLI commands
  if command -v cursor-agent >/dev/null 2>&1; then
    (cd "$path" && cursor-agent "$@")
  elif command -v cursor >/dev/null 2>&1; then
    # Try various Cursor CLI patterns (implementation varies by version)
    (cd "$path" && cursor cli "$@") 2>/dev/null || (cd "$path" && cursor "$@")
  fi
}
