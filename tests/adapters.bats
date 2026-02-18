#!/usr/bin/env bats
# Tests for lib/adapters.sh — registry lookup, name listing
load test_helper

setup() {
  # Adapters source needs stubs for additional functions it may reference
  resolve_workspace_file() { :; }
  export -f resolve_workspace_file
  source "$PROJECT_ROOT/lib/adapters.sh"
}

# ── _registry_lookup ─────────────────────────────────────────────────────────

@test "_registry_lookup finds vscode entry" {
  result=$(_registry_lookup "$_EDITOR_REGISTRY" "vscode")
  [[ "$result" == "vscode|code|"* ]]
}

@test "_registry_lookup finds vim entry" {
  result=$(_registry_lookup "$_EDITOR_REGISTRY" "vim")
  [[ "$result" == "vim|vim|terminal|"* ]]
}

@test "_registry_lookup finds aider AI entry" {
  result=$(_registry_lookup "$_AI_REGISTRY" "aider")
  [[ "$result" == "aider|aider|"* ]]
}

@test "_registry_lookup returns 1 for unknown editor" {
  run _registry_lookup "$_EDITOR_REGISTRY" "nonexistent"
  [ "$status" -eq 1 ]
}

@test "_registry_lookup returns 1 for unknown AI tool" {
  run _registry_lookup "$_AI_REGISTRY" "nonexistent"
  [ "$status" -eq 1 ]
}

@test "_registry_lookup matches exact names only" {
  # "code" is the *command* for vscode, not the *name* — should not match
  run _registry_lookup "$_EDITOR_REGISTRY" "code"
  [ "$status" -eq 1 ]
}

# ── _list_registry_names ─────────────────────────────────────────────────────

@test "_list_registry_names includes expected editors" {
  result=$(_list_registry_names "$_EDITOR_REGISTRY")
  [[ "$result" == *"vscode"* ]]
  [[ "$result" == *"vim"* ]]
  [[ "$result" == *"cursor"* ]]
  [[ "$result" == *"emacs"* ]]
}

@test "_list_registry_names includes expected AI tools" {
  result=$(_list_registry_names "$_AI_REGISTRY")
  [[ "$result" == *"aider"* ]]
  [[ "$result" == *"copilot"* ]]
  [[ "$result" == *"gemini"* ]]
}

@test "_list_registry_names returns comma-separated format" {
  result=$(_list_registry_names "$_EDITOR_REGISTRY")
  # Should contain commas between names
  [[ "$result" == *", "* ]]
}

# ── _load_from_editor_registry ───────────────────────────────────────────────

@test "_load_from_editor_registry parses vscode entry correctly" {
  local entry
  entry=$(_registry_lookup "$_EDITOR_REGISTRY" "vscode")
  _load_from_editor_registry "$entry"
  [ "$_EDITOR_CMD" = "code" ]
  [ "$_EDITOR_WORKSPACE" -eq 1 ]
}

@test "_load_from_editor_registry parses vim as terminal type" {
  local entry
  entry=$(_registry_lookup "$_EDITOR_REGISTRY" "vim")
  _load_from_editor_registry "$entry"
  [ "$_EDITOR_CMD" = "vim" ]
  # Terminal editors get editor_open defined
  declare -f editor_can_open >/dev/null
}

@test "_load_from_editor_registry parses emacs with background flag" {
  local entry
  entry=$(_registry_lookup "$_EDITOR_REGISTRY" "emacs")
  _load_from_editor_registry "$entry"
  [ "$_EDITOR_CMD" = "emacs" ]
  [ "$_EDITOR_BACKGROUND" -eq 1 ]
}

@test "_load_from_editor_registry parses antigravity with workspace and dot flags" {
  local entry
  entry=$(_registry_lookup "$_EDITOR_REGISTRY" "antigravity")
  _load_from_editor_registry "$entry"
  [ "$_EDITOR_CMD" = "agy" ]
  [ "$_EDITOR_WORKSPACE" -eq 1 ]
  [ "$_EDITOR_DOT" -eq 1 ]
}

# ── _load_from_ai_registry ──────────────────────────────────────────────────

@test "_load_from_ai_registry parses aider entry correctly" {
  local entry
  entry=$(_registry_lookup "$_AI_REGISTRY" "aider")
  _load_from_ai_registry "$entry"
  [ "$_AI_CMD" = "aider" ]
  declare -f ai_can_start >/dev/null
}

@test "_load_from_ai_registry parses codex with multiple info lines" {
  local entry
  entry=$(_registry_lookup "$_AI_REGISTRY" "codex")
  _load_from_ai_registry "$entry"
  [ "$_AI_CMD" = "codex" ]
  # codex has semicolon-separated info lines (e.g., "Or: brew install codex;See https://...")
  [ "${#_AI_INFO_LINES[@]}" -ge 2 ]
}
