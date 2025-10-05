#!/usr/bin/env bash
# WebStorm editor adapter

# Check if WebStorm is available
editor_can_open() {
  command -v webstorm >/dev/null 2>&1
}

# Open a directory in WebStorm
# Usage: editor_open path
editor_open() {
  local path="$1"

  if ! editor_can_open; then
    log_error "WebStorm 'webstorm' command not found. Enable shell launcher in Tools > Create Command-line Launcher"
    return 1
  fi

  webstorm "$path"
}
