#!/usr/bin/env bats
# Tests for cmd_clean in lib/commands/clean.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
}

teardown() {
  teardown_integration_repo
}

# ── Basic clean (prune + empty dirs) ────────────────────────────────────────

@test "cmd_clean runs without errors" {
  run cmd_clean
  [ "$status" -eq 0 ]
}

@test "cmd_clean removes empty directories" {
  mkdir -p "$TEST_WORKTREES_DIR/empty-dir"
  cmd_clean
  [ ! -d "$TEST_WORKTREES_DIR/empty-dir" ]
}

@test "cmd_clean preserves non-empty directories" {
  create_test_worktree "keep-me"
  cmd_clean
  [ -d "$TEST_WORKTREES_DIR/keep-me" ]
}

@test "cmd_clean handles missing worktrees dir" {
  # Don't create any worktrees - base_dir doesn't exist
  run cmd_clean
  [ "$status" -eq 0 ]
}

# ── _clean_detect_provider ──────────────────────────────────────────────────

@test "_clean_detect_provider fails without remote" {
  run _clean_detect_provider
  [ "$status" -eq 1 ]
}

# ── _clean_should_skip ──────────────────────────────────────────────────────

@test "_clean_should_skip skips detached HEAD" {
  run _clean_should_skip "/some/dir" "(detached)"
  [ "$status" -eq 0 ]
}

@test "_clean_should_skip skips empty branch" {
  run _clean_should_skip "/some/dir" ""
  [ "$status" -eq 0 ]
}

@test "_clean_should_skip skips dirty worktree" {
  create_test_worktree "dirty-test"
  echo "dirty" > "$TEST_WORKTREES_DIR/dirty-test/untracked.txt"
  git -C "$TEST_WORKTREES_DIR/dirty-test" add untracked.txt
  run _clean_should_skip "$TEST_WORKTREES_DIR/dirty-test" "dirty-test"
  [ "$status" -eq 0 ]
}

@test "_clean_should_skip skips worktree with untracked files" {
  create_test_worktree "untracked-test"
  echo "new" > "$TEST_WORKTREES_DIR/untracked-test/newfile.txt"
  run _clean_should_skip "$TEST_WORKTREES_DIR/untracked-test" "untracked-test"
  [ "$status" -eq 0 ]
}

@test "_clean_should_skip does not skip clean worktree" {
  create_test_worktree "clean-wt"
  run _clean_should_skip "$TEST_WORKTREES_DIR/clean-wt" "clean-wt"
  [ "$status" -eq 1 ]  # 1 = don't skip
}
