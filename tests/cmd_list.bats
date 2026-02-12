#!/usr/bin/env bats
# Tests for cmd_list in lib/commands/list.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
}

teardown() {
  teardown_integration_repo
}

@test "cmd_list shows main repo" {
  run cmd_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"[main repo]"* ]]
}

@test "cmd_list shows created worktree" {
  create_test_worktree "list-me"
  run cmd_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"list-me"* ]]
}

@test "cmd_list --porcelain outputs TSV format" {
  create_test_worktree "porcelain-test"
  local output
  output=$(cmd_list --porcelain)
  # First line: main repo
  local first_line
  first_line=$(echo "$output" | head -1)
  [[ "$first_line" == *"$TEST_REPO"* ]]
  # Should contain tab-separated fields
  [[ "$output" == *$'\t'* ]]
}

@test "cmd_list --porcelain includes worktree branch and status" {
  create_test_worktree "tsv-test"
  local output
  output=$(cmd_list --porcelain)
  # Worktree line should have: path<tab>branch<tab>status
  [[ "$output" == *"tsv-test"*$'\t'*"ok"* ]]
}

@test "cmd_list with no worktrees still works" {
  run cmd_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Git Worktrees"* ]]
}

@test "cmd_list human format has header" {
  run cmd_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"BRANCH"* ]]
  [[ "$output" == *"PATH"* ]]
}
