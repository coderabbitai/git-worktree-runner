#!/usr/bin/env bash
# Auggie CLI AI adapter

# Check if Auggie is available
ai_can_start() {
  command -v auggie >/dev/null 2>&1
}

# Start Auggie in a directory
# Usage: ai_start path [args...]
ai_start() {
  local path="$1"
  shift

  if ! ai_can_start; then
    log_error "Auggie CLI not found. Install with: npm install -g @augmentcode/auggie"
    log_info "See https://www.augmentcode.com/product/CLI for more information"
    return 1
  fi

  if [ ! -d "$path" ]; then
    log_error "Directory not found: $path"
    return 1
  fi

  # Change to the directory and run auggie with any additional arguments
  (cd "$path" && auggie "$@")
}

