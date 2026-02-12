#!/usr/bin/env bats
# Tests for cmd_remove in lib/commands/remove.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
}

teardown() {
  teardown_integration_repo
}

@test "cmd_remove removes a worktree" {
  create_test_worktree "rm-me"
  [ -d "$TEST_WORKTREES_DIR/rm-me" ]
  cmd_remove rm-me
  [ ! -d "$TEST_WORKTREES_DIR/rm-me" ]
}

@test "cmd_remove fails with no arguments" {
  run cmd_remove
  [ "$status" -eq 1 ]
}

@test "cmd_remove skips unknown branch and continues" {
  # cmd_remove uses 'continue' for individual failures, not 'exit'
  run cmd_remove nonexistent
  [ "$status" -eq 0 ]
}

@test "cmd_remove cannot remove main repo" {
  run cmd_remove 1
  [ "$status" -eq 0 ]  # continues past error, doesn't exit
  # Main repo should still exist
  [ -d "$TEST_REPO" ]
}

@test "cmd_remove handles multiple worktrees" {
  create_test_worktree "multi-a"
  create_test_worktree "multi-b"
  cmd_remove multi-a multi-b
  [ ! -d "$TEST_WORKTREES_DIR/multi-a" ]
  [ ! -d "$TEST_WORKTREES_DIR/multi-b" ]
}

@test "cmd_remove runs pre-remove hooks" {
  create_test_worktree "hook-rm"
  git config --add gtr.hook.preRemove "touch $TEST_REPO/pre-hook-ran"
  cmd_remove hook-rm
  [ -f "$TEST_REPO/pre-hook-ran" ]
}

@test "cmd_remove pre-remove hook failure blocks removal" {
  create_test_worktree "hook-block"
  git config --add gtr.hook.preRemove "exit 1"
  run cmd_remove hook-block
  # Worktree should still exist (hook blocked removal)
  [ -d "$TEST_WORKTREES_DIR/hook-block" ]
}

@test "cmd_remove --force skips failed pre-remove hook" {
  create_test_worktree "force-rm"
  git config --add gtr.hook.preRemove "exit 1"
  cmd_remove --force force-rm
  [ ! -d "$TEST_WORKTREES_DIR/force-rm" ]
}

@test "cmd_remove runs post-remove hooks" {
  create_test_worktree "post-rm"
  git config --add gtr.hook.postRemove "touch $TEST_REPO/post-hook-ran"
  cmd_remove post-rm
  [ -f "$TEST_REPO/post-hook-ran" ]
}

@test "cmd_remove continues on individual failures" {
  create_test_worktree "good-rm"
  # Try to remove both a nonexistent and existing worktree
  run cmd_remove nonexistent good-rm
  # The good one should have been removed despite the bad one failing
  [ ! -d "$TEST_WORKTREES_DIR/good-rm" ]
}
