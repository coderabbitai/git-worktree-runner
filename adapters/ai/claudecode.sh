#!/bin/sh
# Claude Code AI adapter

# Check if Claude Code is available
ai_can_start() {
  command -v claude-code >/dev/null 2>&1
}

# Start Claude Code in a directory
# Usage: ai_start path [args...]
ai_start() {
  local path="$1"
  shift

  if ! ai_can_start; then
    log_error "Claude Code not found. Install from https://claude.com/claude-code"
    return 1
  fi

  if [ ! -d "$path" ]; then
    log_error "Directory not found: $path"
    return 1
  fi

  # Change to the directory and run claude-code with any additional arguments
  (cd "$path" && claude-code "$@")
}
