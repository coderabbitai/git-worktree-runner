#!/usr/bin/env bats
# Tests for cmd_copy in lib/commands/copy.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
  create_test_worktree "copy-target"
  # Create a source file in main repo
  echo "secret=value" > "$TEST_REPO/.env"
}

teardown() {
  teardown_integration_repo
}

# ── Basic copy ───────────────────────────────────────────────────────────────

@test "cmd_copy copies files matching explicit pattern" {
  run cmd_copy copy-target -- ".env"
  [ "$status" -eq 0 ]
  [ -f "$TEST_WORKTREES_DIR/copy-target/.env" ]
}

@test "cmd_copy dry-run does not copy files" {
  run cmd_copy copy-target --dry-run -- ".env"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_WORKTREES_DIR/copy-target/.env" ]
}

@test "cmd_copy copies multiple patterns" {
  echo "data" > "$TEST_REPO/config.json"
  run cmd_copy copy-target -- ".env" "config.json"
  [ "$status" -eq 0 ]
  [ -f "$TEST_WORKTREES_DIR/copy-target/.env" ]
  [ -f "$TEST_WORKTREES_DIR/copy-target/config.json" ]
}

@test "cmd_copy copies configured includeDirs" {
  mkdir -p "$TEST_REPO/.zed"
  echo "settings" > "$TEST_REPO/.zed/settings.json"
  git config --add gtr.copy.includeDirs ".zed"

  run cmd_copy copy-target
  [ "$status" -eq 0 ]
  [ -f "$TEST_WORKTREES_DIR/copy-target/.zed/settings.json" ]
}

@test "cmd_copy dry-run does not copy configured includeDirs" {
  mkdir -p "$TEST_REPO/.zed"
  echo "settings" > "$TEST_REPO/.zed/settings.json"
  git config --add gtr.copy.includeDirs ".zed"

  run cmd_copy copy-target --dry-run
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_WORKTREES_DIR/copy-target/.zed" ]
}

@test "cmd_copy applies configured excludeDirs" {
  mkdir -p "$TEST_REPO/.zed/cache"
  echo "settings" > "$TEST_REPO/.zed/settings.json"
  echo "token" > "$TEST_REPO/.zed/cache/token"
  git config --add gtr.copy.includeDirs ".zed"
  git config --add gtr.copy.excludeDirs ".zed/cache"

  run cmd_copy copy-target
  [ "$status" -eq 0 ]
  [ -f "$TEST_WORKTREES_DIR/copy-target/.zed/settings.json" ]
  [ ! -e "$TEST_WORKTREES_DIR/copy-target/.zed/cache/token" ]
}

# ── --all flag ───────────────────────────────────────────────────────────────

@test "cmd_copy --all copies to all worktrees" {
  create_test_worktree "copy-target-2"
  run cmd_copy --all -- ".env"
  [ "$status" -eq 0 ]
  [ -f "$TEST_WORKTREES_DIR/copy-target/.env" ]
  [ -f "$TEST_WORKTREES_DIR/copy-target-2/.env" ]
}

@test "cmd_copy --all copies configured includeDirs to all worktrees" {
  create_test_worktree "copy-target-2"
  mkdir -p "$TEST_REPO/.zed"
  echo "settings" > "$TEST_REPO/.zed/settings.json"
  git config --add gtr.copy.includeDirs ".zed"

  run cmd_copy --all
  [ "$status" -eq 0 ]
  [ -f "$TEST_WORKTREES_DIR/copy-target/.zed/settings.json" ]
  [ -f "$TEST_WORKTREES_DIR/copy-target-2/.zed/settings.json" ]
}

@test "cmd_copy --from copies configured includeDirs from source worktree" {
  create_test_worktree "copy-source"
  mkdir -p "$TEST_WORKTREES_DIR/copy-source/.idea"
  echo "workspace" > "$TEST_WORKTREES_DIR/copy-source/.idea/workspace.xml"
  git config --add gtr.copy.includeDirs ".idea"

  run cmd_copy copy-target --from copy-source
  [ "$status" -eq 0 ]
  [ -f "$TEST_WORKTREES_DIR/copy-target/.idea/workspace.xml" ]
}

# ── Error cases ──────────────────────────────────────────────────────────────

@test "cmd_copy fails with no arguments" {
  run cmd_copy
  [ "$status" -eq 1 ]
}

@test "cmd_copy for unknown branch warns but succeeds" {
  # cmd_copy skips unknown targets with || continue, then warns
  run cmd_copy nonexistent -- ".env"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No files copied"* ]]
}
