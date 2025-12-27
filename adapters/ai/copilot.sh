#!/usr/bin/env bash
# GitHub Copilot CLI adapter

# Check if GitHub Copilot CLI is available
ai_can_start() {
  command -v copilot >/dev/null 2>&1
}

# Start GitHub Copilot CLI in a directory
# Usage: ai_start path [args...]
ai_start() {
  local path="$1"
  shift

  if ! ai_can_start; then
    log_error "GitHub Copilot CLI not found."
    log_info "Install with: npm install -g @github/copilot"
    log_info "Or: brew install copilot-cli"
    log_info "See https://github.com/github/copilot-cli for more information"
    return 1
  fi

  if [ ! -d "$path" ]; then
    log_error "Directory not found: $path"
    return 1
  fi

  # Change to the directory and run copilot with any additional arguments
  (cd "$path" && copilot "$@")
}
