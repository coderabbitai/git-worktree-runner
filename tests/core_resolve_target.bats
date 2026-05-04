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

# ── porcelain fallback ─────────────────────────────────────────────────────────

@test "resolve_target finds externally-created worktree via porcelain fallback" {
  # Create a worktree with raw git (outside gtr-managed directory)
  local ext_dir="${TEST_REPO}-external"
  git -C "$TEST_REPO" worktree add "$ext_dir" -b external-branch --quiet
  local result
  result=$(resolve_target "external-branch" "$TEST_REPO" "$TEST_WORKTREES_DIR" "")
  # Assert: found with is_main=0, correct branch, path ends with expected suffix
  [[ "$result" == "0"$'\t'*"-external"$'\t'"external-branch" ]]
}

@test "resolve_target finds nested externally-created worktree under base dir" {
  mkdir -p "$TEST_WORKTREES_DIR/jsmith"
  git -C "$TEST_REPO" worktree add "$TEST_WORKTREES_DIR/jsmith/my-feature" -b jsmith/my-feature --quiet

  local result
  result=$(resolve_target "jsmith/my-feature" "$TEST_REPO" "$TEST_WORKTREES_DIR" "")
  local expected_path
  expected_path=$(cd "$TEST_WORKTREES_DIR/jsmith/my-feature" && pwd -P)

  [[ "$result" == "0"$'\t'"$expected_path"$'\t'"jsmith/my-feature" ]]
}

@test "list_worktree_records reports normal detached and locked worktrees" {
  create_test_worktree "records-normal"
  git -C "$TEST_REPO" worktree add --detach "$TEST_WORKTREES_DIR/records-detached" HEAD --quiet
  create_test_worktree "records-locked"
  git -C "$TEST_REPO" worktree lock "$TEST_WORKTREES_DIR/records-locked" --reason "test lock"

  local records
  records=$(list_worktree_records "$TEST_REPO")
  local repo_root
  repo_root=$(cd "$TEST_REPO" && pwd -P)

  [[ "$records" == *"1"$'\t'"$repo_root"$'\t'*$'\t'"ok"* ]]
  [[ "$records" == *"0"$'\t'"$TEST_WORKTREES_DIR/records-normal"$'\t'"records-normal"$'\t'"ok"* ]]
  [[ "$records" == *"0"$'\t'"$TEST_WORKTREES_DIR/records-detached"$'\t'"(detached)"$'\t'"detached"* ]]
  [[ "$records" == *"0"$'\t'"$TEST_WORKTREES_DIR/records-locked"$'\t'"records-locked"$'\t'"locked"* ]]

  git -C "$TEST_REPO" worktree unlock "$TEST_WORKTREES_DIR/records-locked"
}

@test "worktree_status handles registered path containing tab" {
  local tab_path="$TEST_WORKTREES_DIR/with"$'\t'"tab"
  git -C "$TEST_REPO" worktree add "$tab_path" -b tab-path --quiet

  local status
  status=$(worktree_status "$tab_path")

  [ "$status" = "ok" ]
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

@test "discover_repo_root returns main repo root when called from a repo subdirectory" {
  mkdir -p "$TEST_REPO/subdir/nested"
  cd "$TEST_REPO/subdir/nested"
  local root expected
  root=$(discover_repo_root)
  expected=$(cd "$TEST_REPO" && pwd -P)
  [ "$root" = "$expected" ]
}

@test "discover_repo_root returns 1 outside a git repository" {
  local outside_repo
  outside_repo=$(mktemp -d)
  cd "$outside_repo"

  run discover_repo_root
  [ "$status" -eq 1 ]

  rm -rf "$outside_repo"
}
