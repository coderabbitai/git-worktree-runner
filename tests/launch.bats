#!/usr/bin/env bats
# Tests for lib/launch.sh config resolution and AI launch orchestration

load test_helper

setup() {
  setup_integration_repo
  export XDG_CONFIG_HOME="$BATS_TMPDIR/gtr-launch-config-$$"
  export GIT_CONFIG_GLOBAL="$BATS_TMPDIR/gtr-launch-global-$$"
  source_gtr_commands
}

teardown() {
  rm -rf "$XDG_CONFIG_HOME"
  rm -f "$GIT_CONFIG_GLOBAL"
  teardown_integration_repo
}

@test "_cfg_ai_default skips untrusted .gtrconfig defaults.ai" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[defaults]
  ai = npx --package=./malicious evilbin
EOF

  result=$(_cfg_ai_default)

  [ "$result" = "none" ]
}

@test "_cfg_ai_default uses .gtrconfig defaults.ai after trust" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[defaults]
  ai = claude
EOF

  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"

  result=$(_cfg_ai_default)

  [ "$result" = "claude" ]
}

@test "_cfg_editor_default skips untrusted .gtrconfig defaults.editor and uses global fallback" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[defaults]
  editor = npx --package=./malicious evilbin
EOF
  git config --global gtr.editor.default vim

  result=$(_cfg_editor_default)

  [ "$result" = "vim" ]
}

@test "_cfg_editor_default allows local config over untrusted .gtrconfig defaults.editor" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[defaults]
  editor = npx --package=./malicious evilbin
EOF
  git config --local gtr.editor.default cursor

  result=$(_cfg_editor_default)

  [ "$result" = "cursor" ]
}

# Use a real adapter process so exported hook variables must reach a child.
setup_auto_launch_ai() {
  TEST_WORKTREES_DIR="$TEST_REPO/trees with spaces"
  create_test_worktree ai-launch
  mkdir "$TEST_REPO/mock-bin"
  cat > "$TEST_REPO/mock-bin/gtr-test-ai" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$PWD" "${REPO_ROOT:-}" "${WORKTREE_PATH:-}" "${BRANCH:-}" \
  "$GTR_LAUNCH_TEST_ENV" >> "$GTR_LAUNCH_TEST_OUTPUT"
EOF
  chmod +x "$TEST_REPO/mock-bin/gtr-test-ai"
  export PATH="$TEST_REPO/mock-bin:$PATH"
  export GTR_LAUNCH_TEST_OUTPUT="$TEST_REPO/ai-started"
  export GTR_LAUNCH_TEST_ENV=parent
  git config gtr.ai.default gtr-test-ai
}

# Exercise the production function's guarded subshell with errexit enabled.
# A failed auto-launch must warn without terminating the enclosing command.
run_auto_launch_ai() {
  run bash -e -c '
    source "$1/tests/test_helper.bash"
    source_gtr_commands
    _auto_launch_ai "$2" "$3" ai-launch
    [ "$GTR_LAUNCH_TEST_ENV" = parent ]
  ' _ "$PROJECT_ROOT" "$TEST_WT_PATH" "$TEST_REPO"
}

@test "_auto_launch_ai stops when destination config is rejected in its guarded subshell" {
  setup_auto_launch_ai
  git config extensions.worktreeConfig true
  git -C "$TEST_WT_PATH" config --worktree gtr.hook.postCd 'touch "$REPO_ROOT/hook-ran"'
  local config_file
  config_file=$(git -C "$TEST_WT_PATH" rev-parse --git-path config.worktree)
  chmod 0660 "$config_file"
  # Source configuration is safe; only dispatch in the destination rejects it.
  _gtr_config_check

  run_auto_launch_ai

  [ "$status" -eq 0 ]
  [ ! -e "$GTR_LAUNCH_TEST_OUTPUT" ]
  [ ! -e "$TEST_REPO/hook-ran" ]
  [[ "$output" == *"Unsafe Git configuration: $config_file"* ]]
  [[ "$output" == *"Failed to start AI tool"* ]]
}

@test "_auto_launch_ai starts normally when no postCd hooks are configured" {
  setup_auto_launch_ai

  run_auto_launch_ai

  [ "$status" -eq 0 ]
  [ "$(head -1 "$GTR_LAUNCH_TEST_OUTPUT")" = "$TEST_WT_PATH" ]
  [ "$(tail -1 "$GTR_LAUNCH_TEST_OUTPUT")" = parent ]
  [ "$(wc -l < "$GTR_LAUNCH_TEST_OUTPUT" | tr -d ' ')" -eq 5 ]
  [[ "$output" != *"Failed to start AI tool"* ]]
}

@test "_auto_launch_ai propagates postCd exports to AI without leaking to its caller" {
  setup_auto_launch_ai
  git config gtr.hook.postCd 'export GTR_LAUNCH_TEST_ENV=from-hook'

  run_auto_launch_ai

  [ "$status" -eq 0 ]
  [ "$(cat "$GTR_LAUNCH_TEST_OUTPUT")" = "$(printf '%s\n' \
    "$TEST_WT_PATH" "$TEST_REPO" "$TEST_WT_PATH" ai-launch from-hook)" ]
  [[ "$output" != *"Failed to start AI tool"* ]]
}

@test "_auto_launch_ai still launches after an individual postCd hook fails" {
  setup_auto_launch_ai
  git config --add gtr.hook.postCd false
  git config --add gtr.hook.postCd 'export GTR_LAUNCH_TEST_ENV=after-failure'

  run_auto_launch_ai

  [ "$status" -eq 0 ]
  [ "$(tail -1 "$GTR_LAUNCH_TEST_OUTPUT")" = after-failure ]
  [[ "$output" == *"Hook 1 failed (continuing)"* ]]
  [[ "$output" != *"Failed to start AI tool"* ]]
}
