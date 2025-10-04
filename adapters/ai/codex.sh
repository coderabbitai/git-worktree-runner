#!/usr/bin/env bash
# OpenAI Codex CLI adapter

# Check if Codex is available
ai_can_start() {
  command -v codex >/dev/null 2>&1
}

# Start Codex in a directory
# Usage: ai_start path [args...]
ai_start() {
  local path="$1"
  shift

  if ! ai_can_start; then
    log_error "Codex CLI not found. Install with: npm install -g @openai/codex"
    log_info "Or: brew install codex"
    log_info "See https://github.com/openai/codex for more info"
    return 1
  fi

  if [ ! -d "$path" ]; then
    log_error "Directory not found: $path"
    return 1
  fi

  # Change to the directory and run codex with any additional arguments
  (cd "$path" && codex "$@")
}
