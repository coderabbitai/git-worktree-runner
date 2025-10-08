#!/usr/bin/env bash
# IntelliJ IDEA editor adapter

# Check if IntelliJ IDEA is available
editor_can_open() {
  command -v idea >/dev/null 2>&1
}

# Open a directory in IntelliJ IDEA
# Usage: editor_open path
editor_open() {
  local path="$1"

  if ! editor_can_open; then
    log_error "IntelliJ IDEA 'idea' command not found. Enable shell launcher in Tools > Create Command-line Launcher"
    return 1
  fi

  idea "$path"
}
