#!/bin/sh
# Continue CLI adapter

# Check if Continue is available
ai_can_start() {
  command -v cn >/dev/null 2>&1
}

# Start Continue in a directory
# Usage: ai_start path [args...]
ai_start() {
  local path="$1"
  shift

  if ! ai_can_start; then
    log_error "Continue CLI not found. Install from https://continue.dev"
    log_info "See https://docs.continue.dev/cli/install for installation"
    return 1
  fi

  if [ ! -d "$path" ]; then
    log_error "Directory not found: $path"
    return 1
  fi

  # Change to the directory and run cn with any additional arguments
  (cd "$path" && cn "$@")
}
