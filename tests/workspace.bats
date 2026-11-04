#!/usr/bin/env bats
# Workspace selection through the real CLI with a benign editor that only logs argv.

load test_helper

setup() {
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
  unset GTR_EDITOR_CMD GTR_EDITOR_DEFAULT GTR_WORKTREES_DIR
  TEST_REPO="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$TEST_REPO" "$BATS_TEST_TMPDIR/bin"
  TEST_REPO=$(cd -P "$TEST_REPO" && pwd -P)
  git -C "$TEST_REPO" init --quiet
  git -C "$TEST_REPO" config user.name "Test User"
  git -C "$TEST_REPO" config user.email "test@example.com"
  git -C "$TEST_REPO" commit --allow-empty -m init --quiet
  TEST_WT_PATH="$TEST_REPO/worktrees/feature"
  git -C "$TEST_REPO" worktree add --quiet -b feature "$TEST_WT_PATH"
  git -C "$TEST_REPO" config gtr.worktrees.dir worktrees
  export WORKSPACE_EDITOR_LOG="$BATS_TEST_TMPDIR/editor-argv"
  cat > "$BATS_TEST_TMPDIR/bin/code" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$#" "$@" > "$WORKSPACE_EDITOR_LOG"
EOF
  chmod +x "$BATS_TEST_TMPDIR/bin/code"
  export PATH="$BATS_TEST_TMPDIR/bin:$PATH"
  cd "$TEST_REPO"
  source_gtr_commands
}

assert_editor_target() {
  [ "$status" -eq 0 ]
  local expected actual
  expected=$(printf '1\n%s' "$1")
  actual=$(cat "$WORKSPACE_EDITOR_LOG")
  if [ "$actual" != "$expected" ]; then
    printf 'Expected editor argv: %s\nActual editor argv: %s\n' "$expected" "$actual" >&2
    return 1
  fi
}

open_workspace() {
  run /bin/bash "$PROJECT_ROOT/bin/git-gtr" editor feature --editor vscode
}

@test "workspace traversal in untrusted shared config falls back to the worktree" {
  touch "$TEST_REPO/outside.code-workspace" "$TEST_WT_PATH/auto.code-workspace"
  git config -f .gtrconfig editor.workspace ../../outside.code-workspace
  git config gtr.editor.default vscode

  run /bin/bash "$PROJECT_ROOT/bin/git-gtr" editor feature

  assert_editor_target "$TEST_WT_PATH"
  [ ! -d "$XDG_CONFIG_HOME/gtr/trusted" ]
}

@test "workspace containment also applies to explicit local and global config" {
  touch "$TEST_REPO/outside.code-workspace"
  git config --global gtr.editor.workspace ../../outside.code-workspace
  open_workspace
  assert_editor_target "$TEST_WT_PATH"

  git config --local gtr.editor.workspace ../../outside.code-workspace
  open_workspace
  assert_editor_target "$TEST_WT_PATH"
}

@test "workspace file symlink cannot select an external file" {
  touch "$TEST_REPO/outside.code-workspace"
  ln -s ../../outside.code-workspace "$TEST_WT_PATH/project.code-workspace"
  git config -f .gtrconfig editor.workspace project.code-workspace
  open_workspace
  assert_editor_target "$TEST_WT_PATH"
}

@test "workspace directory symlink cannot select a sibling with the same path prefix" {
  mkdir "$TEST_WT_PATH-other"
  touch "$TEST_WT_PATH-other/project.code-workspace"
  ln -s ../feature-other "$TEST_WT_PATH/linked"
  git config -f .gtrconfig editor.workspace linked/project.code-workspace
  open_workspace
  assert_editor_target "$TEST_WT_PATH"
}

@test "workspace supports nested paths with spaces and internal parent components" {
  mkdir -p "$TEST_WT_PATH/configs/subdir"
  touch "$TEST_WT_PATH/configs/my project.code-workspace"
  git config -f .gtrconfig editor.workspace './configs/subdir/../my project.code-workspace'
  open_workspace
  assert_editor_target "$TEST_WT_PATH/./configs/subdir/../my project.code-workspace"
}

@test "workspace preserves internal directory and chained file symlinks" {
  mkdir "$TEST_WT_PATH/configs"
  touch "$TEST_WT_PATH/configs/project.code-workspace"
  ln -s configs "$TEST_WT_PATH/linked"
  ln -s linked/project.code-workspace "$TEST_WT_PATH/relative.code-workspace"
  ln -s "$TEST_WT_PATH/relative.code-workspace" "$TEST_WT_PATH/absolute.code-workspace"
  git config -f .gtrconfig editor.workspace absolute.code-workspace
  open_workspace
  assert_editor_target "$TEST_WT_PATH/absolute.code-workspace"
}

@test "workspace resolves a symlinked worktree root without changing the caller directory" {
  touch "$TEST_WT_PATH/project.code-workspace"
  ln -s "$TEST_WT_PATH" "$TEST_REPO/linked-worktree"
  git config -f .gtrconfig editor.workspace project.code-workspace
  local before="$PWD" result
  result=$(resolve_workspace_file "$TEST_REPO/linked-worktree")
  [ "$result" = "$TEST_REPO/linked-worktree/project.code-workspace" ]
  [ "$PWD" = "$before" ]
}

@test "workspace none and missing explicit files disable auto-detection" {
  touch "$TEST_WT_PATH/auto.code-workspace"
  local configured
  for configured in none missing.code-workspace; do
    git config -f .gtrconfig editor.workspace "$configured"
    open_workspace
    assert_editor_target "$TEST_WT_PATH"
  done
}

@test "workspace auto-detects a root file and otherwise opens the folder" {
  open_workspace
  assert_editor_target "$TEST_WT_PATH"
  touch "$TEST_WT_PATH/project.code-workspace"
  open_workspace
  assert_editor_target "$TEST_WT_PATH/project.code-workspace"
}

@test "workspace auto-detection does not follow external file symlinks" {
  touch "$TEST_REPO/outside.code-workspace"
  ln -s ../../outside.code-workspace "$TEST_WT_PATH/project.code-workspace"
  open_workspace
  assert_editor_target "$TEST_WT_PATH"
}

@test "workspace selection retains local over shared over global precedence" {
  touch "$TEST_WT_PATH/local.code-workspace" "$TEST_WT_PATH/shared.code-workspace"
  touch "$TEST_WT_PATH/global.code-workspace"
  git config --global gtr.editor.workspace global.code-workspace
  git config -f .gtrconfig editor.workspace shared.code-workspace
  git config --local gtr.editor.workspace local.code-workspace
  open_workspace
  assert_editor_target "$TEST_WT_PATH/local.code-workspace"
  git config --unset gtr.editor.workspace
  open_workspace
  assert_editor_target "$TEST_WT_PATH/shared.code-workspace"
  git config -f .gtrconfig --unset editor.workspace
  open_workspace
  assert_editor_target "$TEST_WT_PATH/global.code-workspace"
}

@test "workspace data does not approve a shared editor command" {
  git config -f .gtrconfig defaults.editor vscode
  git config -f .gtrconfig editor.workspace project.code-workspace
  touch "$TEST_WT_PATH/project.code-workspace"
  [ "$(_cfg_editor_default)" = none ]
  open_workspace
  assert_editor_target "$TEST_WT_PATH/project.code-workspace"
  [ ! -d "$XDG_CONFIG_HOME/gtr/trusted" ]
}

@test "workspace broken links and link cycles fall back under set -e" {
  ln -s missing.code-workspace "$TEST_WT_PATH/broken.code-workspace"
  ln -s cycle.code-workspace "$TEST_WT_PATH/cycle.code-workspace"
  local configured
  for configured in broken.code-workspace cycle.code-workspace; do
    git config -f .gtrconfig editor.workspace "$configured"
    open_workspace
    assert_editor_target "$TEST_WT_PATH"
  done
}

@test "workspace cannot confuse a newline-suffixed sibling with the worktree" {
  local outside="$TEST_WT_PATH"$'\n'
  mkdir "$outside"
  touch "$outside/project.code-workspace"
  ln -s "$outside" "$TEST_WT_PATH/linked"
  git config -f .gtrconfig editor.workspace linked/project.code-workspace
  open_workspace
  assert_editor_target "$TEST_WT_PATH"
}

@test "workspace treats shell metacharacters as a single literal filename" {
  local name='$(touch should-not-run); project.code-workspace'
  touch "$TEST_WT_PATH/$name"
  git config -f .gtrconfig editor.workspace "$name"
  open_workspace
  assert_editor_target "$TEST_WT_PATH/$name"
  [ ! -e "$TEST_REPO/should-not-run" ]
}

@test "workspace rejects absolute configuration even when the joined path exists" {
  mkdir -p "$TEST_WT_PATH/absolute"
  touch "$TEST_WT_PATH/absolute/project.code-workspace"
  git config -f .gtrconfig editor.workspace /absolute/project.code-workspace
  open_workspace
  assert_editor_target "$TEST_WT_PATH"
}

@test "workspace normalizes Windows separators before checking containment" {
  # Exercise Windows path handling without claiming a native Windows test.
  detect_os() { printf windows; }
  touch "$TEST_REPO/outside.code-workspace"
  git config -f .gtrconfig editor.workspace '..\..\outside.code-workspace'
  run resolve_workspace_file "$TEST_WT_PATH"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  mkdir "$TEST_WT_PATH/configs"
  touch "$TEST_WT_PATH/configs/project.code-workspace"
  git config -f .gtrconfig editor.workspace 'configs\project.code-workspace'
  run resolve_workspace_file "$TEST_WT_PATH"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_WT_PATH/configs/project.code-workspace" ]
}

@test "workspace resolves drive-like symlink targets relative to their parent on POSIX" {
  [ "$(detect_os)" != windows ] || skip "POSIX path semantics"
  mkdir "$TEST_REPO/outside" "$TEST_WT_PATH/inside"
  touch "$TEST_REPO/outside/project.code-workspace"
  touch "$TEST_WT_PATH/inside/project.code-workspace"
  ln -s "$TEST_REPO/outside" "$TEST_WT_PATH/a:"
  ln -s "$TEST_WT_PATH/inside" "$TEST_REPO/a:"
  ln -s a:/project.code-workspace "$TEST_WT_PATH/project.code-workspace"
  git config -f .gtrconfig editor.workspace project.code-workspace
  open_workspace
  assert_editor_target "$TEST_WT_PATH"

  rm "$TEST_WT_PATH/a:"
  ln -s inside "$TEST_WT_PATH/a:"
  open_workspace
  assert_editor_target "$TEST_WT_PATH/project.code-workspace"
}
