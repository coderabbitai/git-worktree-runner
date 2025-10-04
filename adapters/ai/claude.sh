#!/usr/bin/env bash
# Claude Code AI adapter

# Check if Claude Code is available
ai_can_start() {
  command -v claude >/dev/null 2>&1 || command -v claude-code >/dev/null 2>&1
}

# Start Claude Code in a directory
# Usage: ai_start path [args...]
ai_start() {
  local path="$1"
  shift

  if ! ai_can_start; then
    log_error "Claude Code not found. Install from https://claude.com/claude-code"
    log_info "The CLI is called 'claude' (or 'claude-code' in older versions)"
    return 1
  fi

  if [ ! -d "$path" ]; then
    log_error "Directory not found: $path"
    return 1
  fi

  # Try 'claude' first (official binary name), fallback to 'claude-code'
  if command -v claude >/dev/null 2>&1; then
    (cd "$path" && claude "$@")
  else
    (cd "$path" && claude-code "$@")
  fi
}
