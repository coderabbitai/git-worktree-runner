#!/usr/bin/env bats
# Tests for cmd_run in lib/commands/run.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
  create_test_worktree "run-test"
}

teardown() {
  teardown_integration_repo
}

# ── Basic execution ──────────────────────────────────────────────────────────

@test "cmd_run executes command in worktree" {
  run cmd_run run-test pwd
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_WORKTREES_DIR/run-test"* ]]
}

@test "cmd_run passes arguments to command" {
  run cmd_run run-test echo hello world
  [ "$status" -eq 0 ]
  [[ "$output" == *"hello world"* ]]
}

@test "cmd_run ID 1 runs in main repo" {
  run cmd_run 1 pwd
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_REPO"* ]]
}

@test "cmd_run propagates command exit code" {
  run cmd_run run-test false
  [ "$status" -ne 0 ]
}

# ── Error cases ──────────────────────────────────────────────────────────────

@test "cmd_run fails with no arguments" {
  run cmd_run
  [ "$status" -eq 1 ]
}

@test "cmd_run fails with only branch (no command)" {
  run cmd_run run-test
  [ "$status" -eq 1 ]
}

@test "cmd_run fails for unknown branch" {
  run cmd_run nonexistent echo hi
  [ "$status" -eq 1 ]
}

# ── Flag-like args in command ────────────────────────────────────────────────

@test "cmd_run passes flags to inner command" {
  run cmd_run run-test git status --short
  [ "$status" -eq 0 ]
}
