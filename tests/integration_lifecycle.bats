#!/usr/bin/env bats
# Integration tests for the core worktree lifecycle: create → list → resolve → remove

load test_helper

setup() {
  setup_integration_repo
  source_gtr_libs
}

teardown() {
  teardown_integration_repo
}

@test "create_worktree produces expected directory" {
  local default_branch
  default_branch=$(git rev-parse --abbrev-ref HEAD)
  local base_dir="${TEST_REPO}-worktrees"

  local wt_path
  wt_path=$(create_worktree "$base_dir" "" "test-feature" "$default_branch" "auto" "1" "0" "" "")
  [ -d "$wt_path" ]

  # Verify branch in worktree matches
  local branch
  branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD)
  [ "$branch" = "test-feature" ]
}

@test "list_worktree_branches shows created worktree" {
  local default_branch
  default_branch=$(git rev-parse --abbrev-ref HEAD)
  local base_dir="${TEST_REPO}-worktrees"

  create_worktree "$base_dir" "" "test-list" "$default_branch" "auto" "1" "0" "" "" >/dev/null
  local branches
  branches=$(list_worktree_branches "$base_dir" "")
  [[ "$branches" == *"test-list"* ]]
}

@test "resolve_target finds worktree by branch name" {
  local default_branch
  default_branch=$(git rev-parse --abbrev-ref HEAD)
  local base_dir="${TEST_REPO}-worktrees"

  create_worktree "$base_dir" "" "find-me" "$default_branch" "auto" "1" "0" "" "" >/dev/null

  local result
  result=$(resolve_target "find-me" "$TEST_REPO" "$base_dir" "")
  unpack_target "$result"
  [ "$_ctx_is_main" = "0" ]
  [ "$_ctx_branch" = "find-me" ]
  [ -d "$_ctx_worktree_path" ]
}

@test "resolve_target ID 1 returns main repo" {
  local base_dir="${TEST_REPO}-worktrees"
  local result
  result=$(resolve_target "1" "$TEST_REPO" "$base_dir" "")
  unpack_target "$result"
  [ "$_ctx_is_main" = "1" ]
  [ "$_ctx_worktree_path" = "$TEST_REPO" ]
}

@test "resolve_target handles slashed branch names" {
  local default_branch
  default_branch=$(git rev-parse --abbrev-ref HEAD)
  local base_dir="${TEST_REPO}-worktrees"

  create_worktree "$base_dir" "" "feature/auth" "$default_branch" "auto" "1" "0" "" "" >/dev/null

  local result
  result=$(resolve_target "feature/auth" "$TEST_REPO" "$base_dir" "")
  unpack_target "$result"
  [ "$_ctx_is_main" = "0" ]
  [ "$_ctx_branch" = "feature/auth" ]
  # Directory name should be sanitized (slashes → hyphens)
  [[ "$_ctx_worktree_path" == *"feature-auth"* ]]
}

@test "remove_worktree deletes directory" {
  local default_branch
  default_branch=$(git rev-parse --abbrev-ref HEAD)
  local base_dir="${TEST_REPO}-worktrees"

  local wt_path
  wt_path=$(create_worktree "$base_dir" "" "to-remove" "$default_branch" "auto" "1" "0" "" "")
  [ -d "$wt_path" ]

  remove_worktree "$wt_path" "0"
  [ ! -d "$wt_path" ]
}

@test "full lifecycle: create → resolve → remove" {
  local default_branch
  default_branch=$(git rev-parse --abbrev-ref HEAD)
  local base_dir="${TEST_REPO}-worktrees"

  # Create
  local wt_path
  wt_path=$(create_worktree "$base_dir" "" "lifecycle" "$default_branch" "auto" "1" "0" "" "")
  [ -d "$wt_path" ]

  # Resolve
  local result
  result=$(resolve_target "lifecycle" "$TEST_REPO" "$base_dir" "")
  unpack_target "$result"
  [ "$_ctx_is_main" = "0" ]
  [ "$_ctx_worktree_path" = "$wt_path" ]

  # Remove
  remove_worktree "$wt_path" "0"
  [ ! -d "$wt_path" ]

  # Verify resolve fails after removal
  run resolve_target "lifecycle" "$TEST_REPO" "$base_dir" ""
  [ "$status" -ne 0 ]
}
