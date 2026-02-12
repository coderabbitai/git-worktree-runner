#!/usr/bin/env bash
# Adapter loading infrastructure — registries, builders, generic fallbacks, and loaders
# shellcheck disable=SC2329 # Functions defined inside adapter builders are invoked indirectly

# Adapter registries — declarative definitions for standard adapters
# Custom adapters (nano, claude, cursor-ai) remain as override files in adapters/
# Format — editor: name|cmd|type|err_msg|flags (comma-separated: workspace, background)
# Format — ai:     name|cmd|err_msg|info_lines (semicolon-separated)
_EDITOR_REGISTRY="
atom|atom|standard|Atom not found. Install from https://atom.io|
cursor|cursor|standard|Cursor not found. Install from https://cursor.com or enable the shell command.|workspace
emacs|emacs|terminal|Emacs not found. Install from https://www.gnu.org/software/emacs/|background
idea|idea|standard|IntelliJ IDEA 'idea' command not found. Enable shell launcher in Tools > Create Command-line Launcher|
nvim|nvim|terminal|Neovim not found. Install from https://neovim.io|
pycharm|pycharm|standard|PyCharm 'pycharm' command not found. Enable shell launcher in Tools > Create Command-line Launcher|
sublime|subl|standard|Sublime Text 'subl' command not found. Install from https://www.sublimetext.com|
vim|vim|terminal|Vim not found. Install via your package manager.|
vscode|code|standard|VS Code 'code' command not found. Install from https://code.visualstudio.com|workspace
webstorm|webstorm|standard|WebStorm 'webstorm' command not found. Enable shell launcher in Tools > Create Command-line Launcher|
zed|zed|standard|Zed not found. Install from https://zed.dev|
"

_AI_REGISTRY="
aider|aider|Aider not found. Install with: pip install aider-chat|See https://aider.chat for more information
auggie|auggie|Auggie CLI not found. Install with: npm install -g @augmentcode/auggie|See https://www.augmentcode.com/product/CLI for more information
codex|codex|Codex CLI not found. Install with: npm install -g @openai/codex|Or: brew install codex;See https://github.com/openai/codex for more info
continue|cn|Continue CLI not found. Install from https://continue.dev|See https://docs.continue.dev/cli/install for installation
copilot|copilot|GitHub Copilot CLI not found.|Install with: npm install -g @github/copilot;Or: brew install copilot-cli;See https://github.com/github/copilot-cli for more information
gemini|gemini|Gemini CLI not found. Install with: npm install -g @google/gemini-cli|Or: brew install gemini-cli;See https://github.com/google-gemini/gemini-cli for more info
opencode|opencode|OpenCode not found. Install from https://opencode.ai|Make sure the 'opencode' CLI is available in your PATH
"

# Registry lookup — find an adapter entry by name
# Usage: _registry_lookup <registry_content> <name>
# Prints matching line on success, returns 1 on miss
_registry_lookup() {
  local registry="$1" name="$2"
  local line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    if [ "${line%%|*}" = "$name" ]; then
      printf "%s" "$line"
      return 0
    fi
  done <<EOF
$registry
EOF
  return 1
}

# Load an editor adapter from a registry entry
# Parses fields and calls the appropriate builder
_load_from_editor_registry() {
  local entry="$1"
  # Parse: name|cmd|type|err_msg|flags
  local remainder="$entry"
  local name="${remainder%%|*}"; remainder="${remainder#*|}"
  local cmd="${remainder%%|*}"; remainder="${remainder#*|}"
  local type="${remainder%%|*}"; remainder="${remainder#*|}"
  local err_msg="${remainder%%|*}"; remainder="${remainder#*|}"
  local flags="$remainder"

  _EDITOR_CMD="$cmd"
  _EDITOR_ERR_MSG="$err_msg"
  _EDITOR_WORKSPACE=0
  _EDITOR_BACKGROUND=0

  case ",$flags," in
    *,workspace,*) _EDITOR_WORKSPACE=1 ;;
  esac
  case ",$flags," in
    *,background,*) _EDITOR_BACKGROUND=1 ;;
  esac

  case "$type" in
    terminal) _editor_define_terminal ;;
    *)        _editor_define_standard ;;
  esac
}

# Load an AI adapter from a registry entry
# Parses fields and calls the standard builder
_load_from_ai_registry() {
  local entry="$1"
  # Parse: name|cmd|err_msg|info_lines
  local remainder="$entry"
  local name="${remainder%%|*}"; remainder="${remainder#*|}"
  local cmd="${remainder%%|*}"; remainder="${remainder#*|}"
  local err_msg="${remainder%%|*}"; remainder="${remainder#*|}"
  local info_lines_raw="$remainder"

  _AI_CMD="$cmd"
  _AI_ERR_MSG="$err_msg"
  _AI_INFO_LINES=()

  if [ -n "$info_lines_raw" ]; then
    local old_ifs="$IFS"
    IFS=';'
    set -f  # Disable globbing during split
    # shellcheck disable=SC2086
    set -- $info_lines_raw
    set +f
    _AI_INFO_LINES=("$@")
    IFS="$old_ifs"
  fi

  _ai_define_standard
}

# List all adapter names from a registry
# Usage: _list_registry_names <registry_content>
_list_registry_names() {
  local registry="$1"
  local names="" line
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    names="${names:+$names, }${line%%|*}"
  done <<EOF
$registry
EOF
  printf "%s" "$names"
}

# Generic adapter functions (used when no explicit adapter file exists)
# These will be overridden if an adapter file is sourced
# Globals set by load_editor_adapter: GTR_EDITOR_CMD, GTR_EDITOR_CMD_NAME
editor_can_open() {
  command -v "$GTR_EDITOR_CMD_NAME" >/dev/null 2>&1
}

editor_open() {
  local path="$1"
  local workspace="${2:-}"
  local target="$path"

  # Use workspace file if provided and exists
  if [ -n "$workspace" ] && [ -f "$workspace" ]; then
    # shellcheck disable=SC2034
    target="$workspace"
  fi

  # $GTR_EDITOR_CMD may contain arguments (e.g., "code --wait")
  # Using eval here is necessary to handle multi-word commands properly
  eval "$GTR_EDITOR_CMD \"\$target\""
}

# Globals set by load_ai_adapter: GTR_AI_CMD, GTR_AI_CMD_NAME
ai_can_start() {
  command -v "$GTR_AI_CMD_NAME" >/dev/null 2>&1
}

ai_start() {
  local path="$1"
  shift
  # $GTR_AI_CMD may contain arguments (e.g., "bunx @github/copilot@latest")
  # Using eval here is necessary to handle multi-word commands properly
  (cd "$path" && eval "$GTR_AI_CMD \"\$@\"")
}

# Standard AI adapter builder — used by adapter files that follow the common pattern
# Sets globals then call this: _AI_CMD, _AI_ERR_MSG, _AI_INFO_LINES (array)
_ai_define_standard() {
  # shellcheck disable=SC2317 # Functions are called indirectly via adapter dispatch
  ai_can_start() {
    command -v "$_AI_CMD" >/dev/null 2>&1
  }

  # shellcheck disable=SC2317
  ai_start() {
    local path="$1"; shift
    if ! ai_can_start; then
      log_error "$_AI_ERR_MSG"
      local _line
      for _line in "${_AI_INFO_LINES[@]}"; do
        log_info "$_line"
      done
      return 1
    fi
    if [ ! -d "$path" ]; then
      log_error "Directory not found: $path"
      return 1
    fi
    (cd "$path" && "$_AI_CMD" "$@")
  }
}

# Standard editor adapter builder — used by adapter files that follow the common pattern
# Sets globals then call this: _EDITOR_CMD, _EDITOR_ERR_MSG, _EDITOR_WORKSPACE (optional, 0 or 1)
_editor_define_standard() {
  # shellcheck disable=SC2317 # Functions are called indirectly via adapter dispatch
  editor_can_open() {
    command -v "$_EDITOR_CMD" >/dev/null 2>&1
  }

  # shellcheck disable=SC2317
  editor_open() {
    local path="$1"
    local workspace="${2:-}"
    if ! editor_can_open; then
      log_error "$_EDITOR_ERR_MSG"
      return 1
    fi
    if [ "${_EDITOR_WORKSPACE:-0}" = "1" ] && [ -n "$workspace" ] && [ -f "$workspace" ]; then
      "$_EDITOR_CMD" "$workspace"
    else
      "$_EDITOR_CMD" "$path"
    fi
  }
}

# Terminal editor adapter builder — for editors that run in the current terminal
# Sets globals then call this: _EDITOR_CMD, _EDITOR_ERR_MSG, _EDITOR_BACKGROUND (optional, 0 or 1)
_editor_define_terminal() {
  # shellcheck disable=SC2317 # Functions are called indirectly via adapter dispatch
  editor_can_open() {
    command -v "$_EDITOR_CMD" >/dev/null 2>&1
  }

  # shellcheck disable=SC2317
  editor_open() {
    local path="$1"
    if ! editor_can_open; then
      log_error "$_EDITOR_ERR_MSG"
      return 1
    fi
    if [ "${_EDITOR_BACKGROUND:-0}" = "1" ]; then
      "$_EDITOR_CMD" "$path" &
    else
      (cd "$path" && "$_EDITOR_CMD" .)
    fi
  }
}

# Resolve workspace file for VS Code/Cursor editors
# Returns the workspace file path if found, empty otherwise
resolve_workspace_file() {
  local worktree_path="$1"

  # Check config first (gtr.editor.workspace or editor.workspace in .gtrconfig)
  local configured
  configured=$(cfg_default gtr.editor.workspace "" "" editor.workspace)

  # Opt-out: "none" disables workspace lookup entirely
  if [ "$configured" = "none" ]; then
    return 0
  fi

  if [ -n "$configured" ]; then
    local full_path="$worktree_path/$configured"
    if [ -f "$full_path" ]; then
      echo "$full_path"
    fi
    # Explicit config set - don't fall through to auto-detect
    return 0
  fi

  # Auto-detect: find first .code-workspace in worktree root
  local ws_file
  ws_file=$(find "$worktree_path" -maxdepth 1 -name "*.code-workspace" -type f 2>/dev/null | head -1)
  if [ -n "$ws_file" ]; then
    echo "$ws_file"
  fi
}

# Load an adapter by type (shared implementation for editor and AI adapters)
# Usage: _load_adapter <type> <name> <label> <builtin_list> <path_hint>
_load_adapter() {
  local type="$1" name="$2" label="$3" builtin_list="$4" path_hint="$5"
  local adapter_file="$GTR_DIR/adapters/${type}/${name}.sh"

  # 1. Try loading explicit adapter file (custom overrides like claude, nano)
  if [ -f "$adapter_file" ]; then
    # shellcheck disable=SC1090
    . "$adapter_file"
    return 0
  fi

  # 2. Try registry lookup (declarative adapters)
  local registry entry
  if [ "$type" = "editor" ]; then
    registry="$_EDITOR_REGISTRY"
  else
    registry="$_AI_REGISTRY"
  fi

  if entry=$(_registry_lookup "$registry" "$name"); then
    if [ "$type" = "editor" ]; then
      _load_from_editor_registry "$entry"
    else
      _load_from_ai_registry "$entry"
    fi
    return 0
  fi

  # 3. Generic fallback: check if command exists in PATH
  # Extract first word (command name) from potentially multi-word string
  local cmd_name="${name%% *}"

  if ! command -v "$cmd_name" >/dev/null 2>&1; then
    log_error "$label '$name' not found"
    log_info "Built-in adapters: $builtin_list"
    log_info "Or use any $label command available in your PATH (e.g., $path_hint)"
    return 1
  fi

  # Set globals for generic adapter functions
  # Note: $name may contain arguments (e.g., "code --wait", "bunx @github/copilot@latest")
  if [ "$type" = "editor" ]; then
    GTR_EDITOR_CMD="$name"
    GTR_EDITOR_CMD_NAME="$cmd_name"
  else
    GTR_AI_CMD="$name"
    GTR_AI_CMD_NAME="$cmd_name"
  fi
}

load_editor_adapter() {
  local builtin_names
  builtin_names="$(_list_registry_names "$_EDITOR_REGISTRY"), nano"
  _load_adapter "editor" "$1" "Editor" "$builtin_names" "code-insiders, fleet"
}

load_ai_adapter() {
  local builtin_names
  builtin_names="$(_list_registry_names "$_AI_REGISTRY"), claude, cursor"
  _load_adapter "ai" "$1" "AI tool" "$builtin_names" "bunx, gpt"
}
