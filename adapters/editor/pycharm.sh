#!/usr/bin/env bash
# PyCharm editor adapter

# Check if PyCharm is available
editor_can_open() {
  command -v pycharm >/dev/null 2>&1
}

# Open a directory in PyCharm
# Usage: editor_open path
editor_open() {
  local path="$1"

  if ! editor_can_open; then
    log_error "PyCharm 'pycharm' command not found. Enable shell launcher in Tools > Create Command-line Launcher"
    return 1
  fi

  pycharm "$path"
}
