#!/usr/bin/env bash
# Claude Code AI adapter

# Find the actual claude executable (not a shell function)
# Returns the path to the executable, or empty string if not found
find_claude_executable() {
  local cmd

  # Check common installation paths first
  if [ -x "$HOME/.claude/local/claude" ]; then
    echo "$HOME/.claude/local/claude"
    return 0
  fi

  # Try to find executable using type -P (Bash/Zsh)
  for cmd in claude claude-code; do
    if command -v type >/dev/null 2>&1; then
      local exe_path
      exe_path="$(type -P "$cmd" 2>/dev/null)" && [ -n "$exe_path" ] && {
        echo "$exe_path"
        return 0
      }
    fi
  done

  # Fallback: use command -v but exclude functions
  for cmd in claude claude-code; do
    if type "$cmd" 2>/dev/null | grep -qv "function"; then
      if command -v "$cmd" >/dev/null 2>&1; then
        echo "$cmd"
        return 0
      fi
    fi
  done

  return 1
}

# Check if Claude Code is available
ai_can_start() {
  find_claude_executable >/dev/null 2>&1
}

# Start Claude Code in a directory
# Usage: ai_start path [args...]
ai_start() {
  local path="$1"
  shift

  local claude_cmd
  claude_cmd="$(find_claude_executable)"

  if [ -z "$claude_cmd" ]; then
    log_error "Claude Code not found. Install from https://claude.com/claude-code"
    log_info "The CLI is called 'claude' (or 'claude-code' in older versions)"
    return 1
  fi

  if [ ! -d "$path" ]; then
    log_error "Directory not found: $path"
    return 1
  fi

  (cd "$path" && "$claude_cmd" "$@")
}
