#!/usr/bin/env bats
# Tests for resolve_target, unpack_target, resolve_worktree in lib/core.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_libs
}

teardown() {
  teardown_integration_repo
}

@test "resolve_target ID 1 returns main repo with is_main=1" {
  local result
  result=$(resolve_target "1" "$TEST_REPO" "$TEST_WORKTREES_DIR" "")
  [[ "$result" == "1"$'\t'"$TEST_REPO"* ]]
}

@test "resolve_target finds worktree by branch name" {
  create_test_worktree "find-me"
  local result
  result=$(resolve_target "find-me" "$TEST_REPO" "$TEST_WORKTREES_DIR" "")
  [[ "$result" == "0"$'\t'"$TEST_WORKTREES_DIR/find-me"$'\t'"find-me" ]]
}

@test "resolve_target resolves slashed branch to sanitized path" {
  create_test_worktree "feature/login"
  local result
  result=$(resolve_target "feature/login" "$TEST_REPO" "$TEST_WORKTREES_DIR" "")
  [[ "$result" == "0"$'\t'"$TEST_WORKTREES_DIR/feature-login"* ]]
}

@test "resolve_target returns 1 for unknown branch" {
  run resolve_target "nonexistent" "$TEST_REPO" "$TEST_WORKTREES_DIR" ""
  [ "$status" -eq 1 ]
}

@test "resolve_target matches current branch in main repo as is_main=1" {
  local current
  current=$(git rev-parse --abbrev-ref HEAD)
  local result
  result=$(resolve_target "$current" "$TEST_REPO" "$TEST_WORKTREES_DIR" "")
  [[ "$result" == "1"$'\t'"$TEST_REPO"* ]]
}

@test "resolve_target handles prefix in path" {
  create_worktree "$TEST_WORKTREES_DIR" "wt-" "prefixed" "HEAD" "none" "1" >/dev/null
  local result
  result=$(resolve_target "prefixed" "$TEST_REPO" "$TEST_WORKTREES_DIR" "wt-")
  [[ "$result" == "0"$'\t'"$TEST_WORKTREES_DIR/wt-prefixed"* ]]
}

@test "unpack_target parses TSV into context globals" {
  local tsv="0"$'\t'"/some/path"$'\t'"my-branch"
  unpack_target "$tsv"
  [ "$_ctx_is_main" = "0" ]
  [ "$_ctx_worktree_path" = "/some/path" ]
  [ "$_ctx_branch" = "my-branch" ]
}

@test "unpack_target parses main repo TSV" {
  local tsv="1"$'\t'"/repo/root"$'\t'"main"
  unpack_target "$tsv"
  [ "$_ctx_is_main" = "1" ]
  [ "$_ctx_worktree_path" = "/repo/root" ]
  [ "$_ctx_branch" = "main" ]
}

@test "resolve_worktree sets context globals" {
  create_test_worktree "ctx-test"
  resolve_worktree "ctx-test" "$TEST_REPO" "$TEST_WORKTREES_DIR" ""
  [ "$_ctx_is_main" = "0" ]
  [ "$_ctx_worktree_path" = "$TEST_WORKTREES_DIR/ctx-test" ]
  [ "$_ctx_branch" = "ctx-test" ]
}

@test "resolve_worktree returns 1 for unknown branch" {
  run resolve_worktree "nope" "$TEST_REPO" "$TEST_WORKTREES_DIR" ""
  [ "$status" -eq 1 ]
}

# ── discover_repo_root from worktree ──────────────────────────────────────────

@test "discover_repo_root returns main repo root when called from a worktree" {
  create_test_worktree "inside-wt"
  cd "$TEST_WORKTREES_DIR/inside-wt"
  local root expected
  root=$(discover_repo_root)
  # Resolve symlinks (macOS: /var -> /private/var) for comparison
  expected=$(cd "$TEST_REPO" && pwd -P)
  [ "$root" = "$expected" ]
}

@test "discover_repo_root returns main repo root when called from main repo" {
  cd "$TEST_REPO"
  local root expected
  root=$(discover_repo_root)
  expected=$(pwd -P)
  [ "$root" = "$expected" ]
}
