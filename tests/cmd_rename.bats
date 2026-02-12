#!/usr/bin/env bats
# Tests for cmd_rename in lib/commands/rename.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
}

teardown() {
  teardown_integration_repo
}

# ── Basic rename ─────────────────────────────────────────────────────────────

@test "cmd_rename renames worktree and branch" {
  create_test_worktree "old-name"
  cmd_rename old-name new-name --yes 2>/dev/null
  [ -d "$TEST_WORKTREES_DIR/new-name" ]
  [ ! -d "$TEST_WORKTREES_DIR/old-name" ]
}

@test "cmd_rename updates branch name" {
  create_test_worktree "rename-branch"
  cmd_rename rename-branch renamed-branch --yes 2>/dev/null
  # New branch should exist
  run git -C "$TEST_REPO" show-ref --verify "refs/heads/renamed-branch"
  [ "$status" -eq 0 ]
  # Old branch should not exist
  run git -C "$TEST_REPO" show-ref --verify "refs/heads/rename-branch"
  [ "$status" -ne 0 ]
}

# ── Error cases ──────────────────────────────────────────────────────────────

@test "cmd_rename fails with insufficient args" {
  run cmd_rename
  [ "$status" -eq 1 ]
}

@test "cmd_rename fails with only one arg" {
  run cmd_rename old-name
  [ "$status" -eq 1 ]
}

@test "cmd_rename cannot rename main repo" {
  run cmd_rename 1 something --yes
  [ "$status" -eq 1 ]
}

@test "cmd_rename fails if target branch already exists" {
  create_test_worktree "src-branch"
  create_test_worktree "dst-branch"
  run cmd_rename src-branch dst-branch --yes
  [ "$status" -eq 1 ]
}

@test "cmd_rename fails if target folder already exists" {
  create_test_worktree "src-wt"
  mkdir -p "$TEST_WORKTREES_DIR/target-wt"
  touch "$TEST_WORKTREES_DIR/target-wt/placeholder"
  run cmd_rename src-wt target-wt --yes
  [ "$status" -eq 1 ]
}

@test "cmd_rename fails for unknown worktree" {
  run cmd_rename nonexistent new-name --yes
  [ "$status" -eq 1 ]
}
