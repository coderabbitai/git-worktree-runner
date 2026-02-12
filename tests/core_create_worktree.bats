#!/usr/bin/env bats
# Tests for create_worktree and its helpers in lib/core.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_libs
}

teardown() {
  teardown_integration_repo
}

# ── _resolve_folder_name ────────────────────────────────────────────────────

@test "_resolve_folder_name sanitizes branch name" {
  local result
  result=$(_resolve_folder_name "feature/auth")
  [ "$result" = "feature-auth" ]
}

@test "_resolve_folder_name appends custom name" {
  local result
  result=$(_resolve_folder_name "feature/auth" "backend")
  [ "$result" = "feature-auth-backend" ]
}

@test "_resolve_folder_name uses folder override" {
  local result
  result=$(_resolve_folder_name "feature/auth" "" "my-folder")
  [ "$result" = "my-folder" ]
}

@test "_resolve_folder_name rejects empty result" {
  run _resolve_folder_name ""
  [ "$status" -eq 1 ]
}

@test "_resolve_folder_name rejects dot" {
  run _resolve_folder_name "."
  [ "$status" -eq 1 ]
}

@test "_resolve_folder_name rejects double-dot" {
  run _resolve_folder_name ".."
  [ "$status" -eq 1 ]
}

# ── _check_branch_refs ──────────────────────────────────────────────────────

@test "_check_branch_refs detects local branch" {
  git branch local-only HEAD
  _check_branch_refs "local-only"
  [ "$_wt_local_exists" -eq 1 ]
  [ "$_wt_remote_exists" -eq 0 ]
}

@test "_check_branch_refs sets both to 0 for unknown branch" {
  _check_branch_refs "nonexistent-branch"
  [ "$_wt_local_exists" -eq 0 ]
  [ "$_wt_remote_exists" -eq 0 ]
}

# ── create_worktree ─────────────────────────────────────────────────────────

@test "create_worktree creates directory with track=none" {
  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "new-branch" "HEAD" "none" "1")
  [ -d "$wt_path" ]
  [ "$wt_path" = "$TEST_WORKTREES_DIR/new-branch" ]
}

@test "create_worktree uses local branch with track=local" {
  git branch local-branch HEAD
  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "local-branch" "HEAD" "local" "1")
  [ -d "$wt_path" ]
}

@test "create_worktree fails for missing local branch with track=local" {
  run create_worktree "$TEST_WORKTREES_DIR" "" "nope" "HEAD" "local" "1"
  [ "$status" -eq 1 ]
}

@test "create_worktree fails for missing remote branch with track=remote" {
  run create_worktree "$TEST_WORKTREES_DIR" "" "nope" "HEAD" "remote" "1"
  [ "$status" -eq 1 ]
}

@test "create_worktree auto mode creates new branch when neither exists" {
  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "auto-new" "HEAD" "auto" "1")
  [ -d "$wt_path" ]
}

@test "create_worktree auto mode uses existing local branch" {
  git branch existing-local HEAD
  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "existing-local" "HEAD" "auto" "1")
  [ -d "$wt_path" ]
}

@test "create_worktree rejects duplicate worktree" {
  create_worktree "$TEST_WORKTREES_DIR" "" "dup-test" "HEAD" "none" "1" >/dev/null
  run create_worktree "$TEST_WORKTREES_DIR" "" "dup-test" "HEAD" "none" "1"
  [ "$status" -eq 1 ]
}

@test "create_worktree applies prefix to folder name" {
  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "wt-" "prefixed" "HEAD" "none" "1")
  [ "$wt_path" = "$TEST_WORKTREES_DIR/wt-prefixed" ]
  [ -d "$wt_path" ]
}

@test "create_worktree applies custom name suffix" {
  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "feature" "HEAD" "none" "1" "0" "backend")
  [ "$wt_path" = "$TEST_WORKTREES_DIR/feature-backend" ]
}

@test "create_worktree applies folder override" {
  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "any-branch" "HEAD" "none" "1" "0" "" "custom-dir")
  [ "$wt_path" = "$TEST_WORKTREES_DIR/custom-dir" ]
}

@test "create_worktree creates base dir if needed" {
  local nested="$TEST_WORKTREES_DIR/sub/trees"
  local wt_path
  wt_path=$(create_worktree "$nested" "" "nest-test" "HEAD" "none" "1")
  [ -d "$nested" ]
  [ -d "$wt_path" ]
}

@test "create_worktree sanitizes slashed branch for folder" {
  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "feature/deep/path" "HEAD" "none" "1")
  [ "$wt_path" = "$TEST_WORKTREES_DIR/feature-deep-path" ]
}
