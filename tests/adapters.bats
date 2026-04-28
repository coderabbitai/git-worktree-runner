#!/usr/bin/env bats
# Tests for lib/adapters.sh — registry lookup, name listing
load test_helper

setup() {
  # Adapters source needs stubs for additional functions it may reference
  resolve_workspace_file() { :; }
  export -f resolve_workspace_file
  GTR_DIR="$PROJECT_ROOT"
  source "$PROJECT_ROOT/lib/adapters.sh"
}

teardown() {
  if [ -n "${mock_bin_dir:-}" ]; then
    rm -rf "$mock_bin_dir"
  fi
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

@test "_load_adapter allows generic commands with slash-bearing arguments" {
  mock_bin_dir="$(mktemp -d)"
  cat > "$mock_bin_dir/bunx" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$mock_bin_dir/bunx"
  PATH="$mock_bin_dir:$PATH"

  _load_adapter "ai" "bunx @github/copilot@latest" "AI tool" "$(_list_registry_names "$_AI_REGISTRY")" "bunx, gpt"
  [ "$GTR_AI_CMD" = "bunx @github/copilot@latest" ]
  [ "$GTR_AI_CMD_NAME" = "bunx" ]
}

@test "_load_adapter allows path-like literal arguments" {
  mock_bin_dir="$(mktemp -d)"
  cat > "$mock_bin_dir/tool" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$mock_bin_dir/tool"
  PATH="$mock_bin_dir:$PATH"

  _load_adapter "ai" "tool ~/.toolrc ../config/local.yml" "AI tool" "$(_list_registry_names "$_AI_REGISTRY")" "tool"
  [ "$GTR_AI_CMD" = "tool ~/.toolrc ../config/local.yml" ]
  [ "$GTR_AI_CMD_NAME" = "tool" ]
}

@test "_load_adapter allows raw metacharacters inside literal argv data" {
  mock_bin_dir="$(mktemp -d)"
  cat > "$mock_bin_dir/tool" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  chmod +x "$mock_bin_dir/tool"
  PATH="$mock_bin_dir:$PATH"

  _load_adapter "ai" "tool --label foo&bar" "AI tool" "$(_list_registry_names "$_AI_REGISTRY")" "tool"
  [ "$GTR_AI_CMD" = "tool --label foo&bar" ]
  [ "$GTR_AI_CMD_NAME" = "tool" ]
}

@test "_load_adapter rejects filesystem path commands in generic fallback" {
  run _load_adapter "editor" "./bin/gtr" "Editor" "$(_list_registry_names "$_EDITOR_REGISTRY")" "code, vim"
  [ "$status" -eq 1 ]
}

@test "_load_adapter rejects shell wrapper commands in generic fallback" {
  run _load_adapter "ai" 'sh -c "printf injected"' "AI tool" "$(_list_registry_names "$_AI_REGISTRY")" "bunx, gpt"
  [ "$status" -eq 1 ]
}

@test "_parse_configured_command writes caller-owned argv without shell evaluation" {
  local -a parsed_argv=()
  _parse_configured_command parsed_argv "printf '%s\n' 'hello world'"

  [ "${#parsed_argv[@]}" -eq 3 ]
  [ "${parsed_argv[0]}" = "printf" ]
  [ "${parsed_argv[1]}" = "%s\n" ]
  [ "${parsed_argv[2]}" = "hello world" ]
}

@test "_run_configured_command preserves quoted arguments from parsed argv" {
  local -a parsed_argv=()
  _parse_configured_command parsed_argv "printf '%s\n' 'hello world'"

  run _run_configured_command "${parsed_argv[@]}"
  [ "$status" -eq 0 ]
  [ "$output" = "hello world" ]
}

@test "override AI adapters preserve configured flags" {
  export HOME="$BATS_TMPDIR/home"
  PATH="/usr/bin:/bin"
  mkdir -p "$HOME/.claude/local" "$BATS_TMPDIR/worktree"
  cat > "$HOME/.claude/local/claude" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$BATS_TMPDIR/claude-args"
EOF
  chmod +x "$HOME/.claude/local/claude"

  load_ai_adapter "claude --continue"
  ai_start "$BATS_TMPDIR/worktree" --resume

  [ "$(cat "$BATS_TMPDIR/claude-args")" = "--continue --resume" ]
}

@test "override editor adapters preserve configured flags" {
  mock_bin_dir="$(mktemp -d)"
  mkdir -p "$BATS_TMPDIR/project"
  cat > "$mock_bin_dir/nano" <<'EOF'
#!/usr/bin/env bash
printf '%s|%s\n' "$(pwd)" "$*" > "$BATS_TMPDIR/nano-call"
EOF
  chmod +x "$mock_bin_dir/nano"
  PATH="$mock_bin_dir:$PATH"

  load_editor_adapter "nano -w"
  editor_open "$BATS_TMPDIR/project"

  [ "$(cat "$BATS_TMPDIR/nano-call")" = "$BATS_TMPDIR/project|-w" ]
}
