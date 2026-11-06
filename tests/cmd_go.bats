#!/usr/bin/env bats
# Tests for cmd_go in lib/commands/go.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
  create_test_worktree "go-test"
}

teardown() {
  teardown_integration_repo
}

@test "cmd_go prints worktree path to stdout" {
  run cmd_go go-test
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_WORKTREES_DIR/go-test"* ]]
}

@test "cmd_go resolves ID 1 to main repo" {
  run cmd_go 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_REPO"* ]]
}

@test "cmd_go fails with no arguments" {
  run cmd_go
  [ "$status" -eq 1 ]
}

@test "cmd_go fails for unknown branch" {
  run cmd_go nonexistent
  [ "$status" -eq 1 ]
}

@test "git gtr go rejects a sanitized collision" {
  create_test_worktree "feat-login"
  run "$PROJECT_ROOT/bin/gtr" go feat/login
  [ "$status" -eq 1 ]
  [[ "$output" == *"Worktree not found"* ]]
}

@test "cmd_go resolves slashed branch" {
  create_test_worktree "feature/nav"
  run cmd_go "feature/nav"
  [ "$status" -eq 0 ]
  [[ "$output" == *"feature-nav"* ]]
}

@test "cmd_go prints human messages to stderr" {
  local stdout stderr
  stdout=$(cmd_go go-test 2>/dev/null)
  stderr=$(cmd_go go-test 2>&1 >/dev/null)
  # stdout should be just the path
  [[ "$stdout" == *"$TEST_WORKTREES_DIR/go-test"* ]]
  # stderr should contain human-readable info
  [[ "$stderr" == *"Worktree"* ]] || [[ "$stderr" == *"Branch"* ]]
}

@test "git gtr go emits every trailing newline byte for branches and escaped identities" {
  git worktree list --porcelain -z >/dev/null 2>&1 || skip "NUL worktree listing is unavailable"
  local suffix path branch identifier
  for suffix in $'\n' $'\n\n'; do
    branch="go-newline-${#suffix}"
    path="$TEST_WORKTREES_DIR/$branch$suffix"
    git worktree add -b "$branch" "$path" HEAD >/dev/null
    mkdir "$TEST_WORKTREES_DIR/$branch"
    printf '%s\n' "$path" > "$TEST_REPO/expected"
    for identifier in "$branch" "path:$(_tsv_escape_field "$path")"; do
      # Compare files: BATS run and ordinary command substitution trim newlines.
      "$PROJECT_ROOT/bin/gtr" go "$identifier" > "$TEST_REPO/actual"
      cmp "$TEST_REPO/expected" "$TEST_REPO/actual"
    done
  done
}

@test "cmd_go 1 from inside a worktree resolves to main repo" {
  cd "$TEST_WORKTREES_DIR/go-test"
  run cmd_go 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_REPO"* ]]
}
