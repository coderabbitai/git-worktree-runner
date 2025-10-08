#!/usr/bin/env bash
# Sublime Text editor adapter

# Check if Sublime Text is available
editor_can_open() {
  command -v subl >/dev/null 2>&1
}

# Open a directory in Sublime Text
# Usage: editor_open path
editor_open() {
  local path="$1"

  if ! editor_can_open; then
    log_error "Sublime Text 'subl' command not found. Install from https://www.sublimetext.com"
    return 1
  fi

  subl "$path"
}
