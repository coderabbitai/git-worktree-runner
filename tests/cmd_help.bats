#!/usr/bin/env bats
# Tests for cmd_help and per-command help in lib/commands/help.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
}

teardown() {
  teardown_integration_repo
}

# ── Full help ────────────────────────────────────────────────────────────────

@test "cmd_help with no args shows full help" {
  run cmd_help
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr - Git worktree runner"* ]]
  [[ "$output" == *"QUICK START"* ]]
  [[ "$output" == *"CONFIGURATION OPTIONS"* ]]
}

@test "cmd_help full page includes gtr.ui.color" {
  run cmd_help
  [ "$status" -eq 0 ]
  [[ "$output" == *"gtr.ui.color"* ]]
}

# ── Per-command help ─────────────────────────────────────────────────────────

@test "cmd_help new shows new command help" {
  run cmd_help new
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr new"* ]]
  [[ "$output" == *"--from"* ]]
  [[ "$output" == *"--track"* ]]
  # Should NOT contain full help sections
  [[ "$output" != *"QUICK START"* ]]
}

@test "cmd_help editor shows editor help" {
  run cmd_help editor
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr editor"* ]]
  [[ "$output" == *"--editor"* ]]
}

@test "cmd_help ai shows ai help" {
  run cmd_help ai
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr ai"* ]]
  [[ "$output" == *"--ai"* ]]
}

@test "cmd_help rm shows rm help" {
  run cmd_help rm
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr rm"* ]]
  [[ "$output" == *"--delete-branch"* ]]
}

@test "cmd_help go shows go help" {
  run cmd_help go
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr go"* ]]
}

@test "cmd_help config shows config help" {
  run cmd_help config
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr config"* ]]
  [[ "$output" == *"list"* ]]
  [[ "$output" == *"get"* ]]
  [[ "$output" == *"set"* ]]
}

@test "cmd_help clean shows clean help" {
  run cmd_help clean
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr clean"* ]]
  [[ "$output" == *"--merged"* ]]
}

@test "cmd_help copy shows copy help" {
  run cmd_help copy
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr copy"* ]]
  [[ "$output" == *"--dry-run"* ]]
}

# ── Alias mapping ────────────────────────────────────────────────────────────

@test "cmd_help ls maps to list help" {
  run cmd_help ls
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr list"* ]]
}

@test "cmd_help rename maps to mv help" {
  run cmd_help rename
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr mv"* ]]
}

@test "cmd_help adapters maps to adapter help" {
  run cmd_help adapters
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr adapter"* ]]
}

# ── Error cases ──────────────────────────────────────────────────────────────

@test "cmd_help unknown command returns error" {
  run cmd_help nonexistent
  [ "$status" -eq 1 ]
}
