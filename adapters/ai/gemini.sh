#!/usr/bin/env bash
# Gemini CLI adapter

# Check if Gemini is available
ai_can_start() {
  command -v gemini >/dev/null 2>&1
}

# Start Gemini in a directory
# Usage: ai_start path [args...]
ai_start() {
  local path="$1"
  shift

  if ! ai_can_start; then
    log_error "Gemini CLI not found. Install with: npm install -g @google/gemini-cli"
    log_info "Or: brew install gemini-cli"
    log_info "See https://github.com/google-gemini/gemini-cli for more info"
    return 1
  fi

  if [ ! -d "$path" ]; then
    log_error "Directory not found: $path"
    return 1
  fi

  # Change to the directory and run gemini with any additional arguments
  (cd "$path" && gemini "$@")
}