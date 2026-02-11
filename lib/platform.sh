#!/usr/bin/env bash
# Platform-specific utilities

# Detect operating system
# Returns: darwin, linux, or windows
detect_os() {
  case "$OSTYPE" in
    darwin*)
      echo "darwin"
      ;;
    linux*)
      echo "linux"
      ;;
    msys*|cygwin*|win32*)
      echo "windows"
      ;;
    *)
      # Fallback to uname
      case "$(uname -s 2>/dev/null)" in
        Darwin)
          echo "darwin"
          ;;
        Linux)
          echo "linux"
          ;;
        MINGW*|MSYS*|CYGWIN*)
          echo "windows"
          ;;
        *)
          echo "unknown"
          ;;
      esac
      ;;
  esac
}

# Open a directory in the system's GUI file browser
# Usage: open_in_gui path
open_in_gui() {
  local path="$1"
  local os

  os=$(detect_os)

  case "$os" in
    darwin)
      open "$path" 2>/dev/null || true
      ;;
    linux)
      # Try common Linux file managers
      if command -v xdg-open >/dev/null 2>&1; then
        xdg-open "$path" >/dev/null 2>&1 || true
      elif command -v gnome-open >/dev/null 2>&1; then
        gnome-open "$path" >/dev/null 2>&1 || true
      fi
      ;;
    windows)
      if command -v cygpath >/dev/null 2>&1; then
        cmd.exe /c start "" "$(cygpath -w "$path")" 2>/dev/null || true
      else
        cmd.exe /c start "" "$path" 2>/dev/null || true
      fi
      ;;
    *)
      log_warn "Cannot open GUI on unknown OS"
      return 1
      ;;
  esac
}

# Escape a string for safe interpolation into AppleScript double-quoted strings
# Handles backslashes and double quotes that would break AppleScript syntax
_escape_applescript() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  printf '%s' "$s"
}

# Spawn a new terminal window/tab in a directory
# Usage: spawn_terminal_in path title [command]
# Note: Best-effort implementation, may not work on all systems
spawn_terminal_in() {
  local path="$1"
  local title="$2"
  local cmd="${3:-}"
  local os

  os=$(detect_os)

  case "$os" in
    darwin)
      # Escape variables for AppleScript string interpolation
      local safe_path safe_title safe_cmd
      safe_path=$(_escape_applescript "$path")
      safe_title=$(_escape_applescript "$title")
      safe_cmd=$(_escape_applescript "$cmd")

      # Try iTerm2 first, then Terminal.app
      if osascript -e 'tell application "System Events" to get name of first application process whose frontmost is true' 2>/dev/null | grep -q "iTerm"; then
        osascript <<-EOF 2>/dev/null || true
					tell application "iTerm"
						tell current window
							create tab with default profile
							tell current session
								write text "cd \"$safe_path\""
								set name to "$safe_title"
								$([ -n "$safe_cmd" ] && echo "write text \"$safe_cmd\"")
							end tell
						end tell
					end tell
				EOF
      else
        osascript <<-EOF 2>/dev/null || true
					tell application "Terminal"
						do script "cd \"$safe_path\"; $safe_cmd"
						set custom title of front window to "$safe_title"
					end tell
				EOF
      fi
      ;;
    linux)
      # Try common terminal emulators
      if command -v gnome-terminal >/dev/null 2>&1; then
        gnome-terminal --working-directory="$path" --title="$title" -- sh -c "$cmd; exec \$SHELL" 2>/dev/null || true
      elif command -v konsole >/dev/null 2>&1; then
        konsole --workdir "$path" -p "tabtitle=$title" -e sh -c "$cmd; exec \$SHELL" 2>/dev/null || true
      elif command -v xterm >/dev/null 2>&1; then
        xterm -T "$title" -e "cd \"$path\" && $cmd && exec \$SHELL" 2>/dev/null || true
      else
        log_warn "No supported terminal emulator found"
        return 1
      fi
      ;;
    windows)
      # Try Windows Terminal, then fallback to cmd
      if command -v wt >/dev/null 2>&1; then
        wt -d "$path" "$cmd" 2>/dev/null || true
      else
        cmd.exe /c start "$title" cmd.exe /k "cd /d \"$path\" && $cmd" 2>/dev/null || true
      fi
      ;;
    *)
      log_warn "Cannot spawn terminal on unknown OS"
      return 1
      ;;
  esac
}
