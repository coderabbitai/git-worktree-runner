#!/usr/bin/env bats

setup() {
  load test_helper
  source "$PROJECT_ROOT/lib/core.sh"

  # Create a temporary git repo for testing
  TEST_REPO=$(mktemp -d)
  git -C "$TEST_REPO" init --quiet
  git -C "$TEST_REPO" config user.name "Test User"
  git -C "$TEST_REPO" config user.email "test@example.com"
  git -C "$TEST_REPO" commit --allow-empty -m "init" --quiet
}

teardown() {
  rm -rf "$TEST_REPO"
}

@test "default base dir is repo-worktrees sibling" {
  result=$(resolve_base_dir "$TEST_REPO")
  expected="$(dirname "$TEST_REPO")/$(basename "$TEST_REPO")-worktrees"
  [ "$result" = "$expected" ]
}

@test "absolute path config is used as-is" {
  # Override cfg_default to return an absolute path
  cfg_default() { printf "/custom/worktrees"; }
  result=$(resolve_base_dir "$TEST_REPO")
  [ "$result" = "/custom/worktrees" ]
}

@test "tilde in path is expanded" {
  cfg_default() { printf "~/my-worktrees"; }
  result=$(resolve_base_dir "$TEST_REPO")
  [ "$result" = "$HOME/my-worktrees" ]
}

@test "relative path is resolved from repo root" {
  cfg_default() { printf ".worktrees"; }
  result=$(resolve_base_dir "$TEST_REPO")
  [ "$result" = "$TEST_REPO/.worktrees" ]
}
