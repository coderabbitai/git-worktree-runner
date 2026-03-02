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

# ── from_ref handling ──────────────────────────────────────────────────────

@test "create_worktree from local branch starts at that branch's commit" {
  git commit --allow-empty -m "second" --quiet
  local expected_sha
  expected_sha=$(git rev-parse HEAD)

  git branch from-source HEAD
  git reset --hard HEAD~1 --quiet

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "from-local" "from-source" "none" "1")
  [ -d "$wt_path" ]

  local actual_sha
  actual_sha=$(git -C "$wt_path" rev-parse HEAD)
  [ "$actual_sha" = "$expected_sha" ]
}

@test "create_worktree from lightweight tag starts at the tagged commit" {
  git commit --allow-empty -m "tagged commit" --quiet
  local expected_sha
  expected_sha=$(git rev-parse HEAD)
  git tag v1.0.0

  git commit --allow-empty -m "after tag" --quiet

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "from-light-tag" "v1.0.0" "none" "1")
  [ -d "$wt_path" ]

  local actual_sha
  actual_sha=$(git -C "$wt_path" rev-parse HEAD)
  [ "$actual_sha" = "$expected_sha" ]
}

@test "create_worktree from annotated tag starts at the tagged commit" {
  git commit --allow-empty -m "tagged commit" --quiet
  local expected_sha
  expected_sha=$(git rev-parse HEAD)
  git tag -a v2.0.0 -m "v2.0.0"

  git commit --allow-empty -m "after tag" --quiet

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "from-ann-tag" "v2.0.0" "none" "1")
  [ -d "$wt_path" ]

  local actual_sha
  actual_sha=$(git -C "$wt_path" rev-parse HEAD)
  [ "$actual_sha" = "$expected_sha" ]
}

@test "create_worktree from commit SHA starts at that commit" {
  git commit --allow-empty -m "target commit" --quiet
  local expected_sha
  expected_sha=$(git rev-parse HEAD)

  git commit --allow-empty -m "later commit" --quiet

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "from-sha" "$expected_sha" "none" "1")
  [ -d "$wt_path" ]

  local actual_sha
  actual_sha=$(git -C "$wt_path" rev-parse HEAD)
  [ "$actual_sha" = "$expected_sha" ]
}

@test "create_worktree from remote branch uses the requested branch name not the remote name" {
  # Set up a "remote" by using the test repo as its own remote
  git remote add origin "$TEST_REPO" 2>/dev/null || true
  git branch remote-feature HEAD
  git fetch origin --quiet

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "my-branch" "remote-feature" "none" "1")
  [ -d "$wt_path" ]

  # The worktree branch must be our requested name, not the remote branch name
  local actual_branch
  actual_branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD)
  [ "$actual_branch" = "my-branch" ]
}

@test "create_worktree from remote branch starts at the correct commit" {
  git commit --allow-empty -m "remote target" --quiet
  local expected_sha
  expected_sha=$(git rev-parse HEAD)

  git remote add origin "$TEST_REPO" 2>/dev/null || true
  git branch remote-source HEAD
  git fetch origin --quiet

  git commit --allow-empty -m "moved on" --quiet

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "from-remote-ref" "remote-source" "none" "1")
  [ -d "$wt_path" ]

  local actual_sha
  actual_sha=$(git -C "$wt_path" rev-parse HEAD)
  [ "$actual_sha" = "$expected_sha" ]
}

@test "create_worktree auto mode from local branch starts at that commit" {
  git commit --allow-empty -m "auto target" --quiet
  local expected_sha
  expected_sha=$(git rev-parse HEAD)

  git branch auto-source HEAD
  git reset --hard HEAD~1 --quiet

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "auto-from-local" "auto-source" "auto" "1")
  [ -d "$wt_path" ]

  local actual_sha
  actual_sha=$(git -C "$wt_path" rev-parse HEAD)
  [ "$actual_sha" = "$expected_sha" ]
}

@test "create_worktree fails with invalid from_ref" {
  run create_worktree "$TEST_WORKTREES_DIR" "" "bad-ref" "nonexistent-ref-xyz" "none" "1"
  [ "$status" -eq 1 ]
}
