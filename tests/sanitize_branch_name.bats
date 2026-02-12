#!/usr/bin/env bats

setup() {
  load test_helper
  source "$PROJECT_ROOT/lib/core.sh"
}

@test "simple branch name passes through unchanged" {
  result=$(sanitize_branch_name "my-feature")
  [ "$result" = "my-feature" ]
}

@test "slashes are replaced with hyphens" {
  result=$(sanitize_branch_name "feature/user-auth")
  [ "$result" = "feature-user-auth" ]
}

@test "nested slashes are replaced" {
  result=$(sanitize_branch_name "org/team/feature")
  [ "$result" = "org-team-feature" ]
}

@test "spaces are replaced with hyphens" {
  result=$(sanitize_branch_name "my feature branch")
  [ "$result" = "my-feature-branch" ]
}

@test "colons are replaced with hyphens" {
  result=$(sanitize_branch_name "fix:bug")
  [ "$result" = "fix-bug" ]
}

@test "leading hyphens are stripped" {
  result=$(sanitize_branch_name "/leading-slash")
  [ "$result" = "leading-slash" ]
}

@test "trailing hyphens are stripped" {
  result=$(sanitize_branch_name "trailing-slash/")
  [ "$result" = "trailing-slash" ]
}

@test "multiple special chars are each replaced" {
  result=$(sanitize_branch_name "a//b")
  [ "$result" = "a--b" ]
}

@test "backslashes are replaced" {
  result=$(sanitize_branch_name 'feature\auth')
  [ "$result" = "feature-auth" ]
}
