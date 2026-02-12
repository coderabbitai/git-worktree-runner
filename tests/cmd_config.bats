#!/usr/bin/env bats
# Tests for cmd_config in lib/commands/config.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
}

teardown() {
  teardown_integration_repo
}

# ── Set and get ──────────────────────────────────────────────────────────────

@test "cmd_config set creates config value" {
  cmd_config set gtr.editor.default vim 2>/dev/null
  local value
  value=$(git config --local --get gtr.editor.default)
  [ "$value" = "vim" ]
}

@test "cmd_config get reads config value" {
  git config --local gtr.editor.default "cursor"
  run cmd_config get gtr.editor.default
  [ "$status" -eq 0 ]
  [[ "$output" == *"cursor"* ]]
}

@test "cmd_config set replaces existing value" {
  cmd_config set gtr.editor.default vim 2>/dev/null
  cmd_config set gtr.editor.default cursor 2>/dev/null
  local value
  value=$(git config --local --get gtr.editor.default)
  [ "$value" = "cursor" ]
}

# ── Add and unset ────────────────────────────────────────────────────────────

@test "cmd_config add appends to multi-valued key" {
  cmd_config add gtr.copy.include ".env*" 2>/dev/null
  cmd_config add gtr.copy.include "*.json" 2>/dev/null
  local count
  count=$(git config --local --get-all gtr.copy.include | wc -l)
  [ "$count" -eq 2 ]
}

@test "cmd_config unset removes config value" {
  cmd_config set gtr.editor.default vim 2>/dev/null
  cmd_config unset gtr.editor.default 2>/dev/null
  run git config --local --get gtr.editor.default
  [ "$status" -ne 0 ]
}

# ── List ─────────────────────────────────────────────────────────────────────

@test "cmd_config list shows config values" {
  cmd_config set gtr.editor.default cursor 2>/dev/null
  run cmd_config list
  [ "$status" -eq 0 ]
  [[ "$output" == *"gtr.editor.default"* ]]
  [[ "$output" == *"cursor"* ]]
}

@test "cmd_config with no args defaults to list" {
  cmd_config set gtr.editor.default vim 2>/dev/null
  run cmd_config
  [ "$status" -eq 0 ]
  [[ "$output" == *"gtr.editor.default"* ]]
}

@test "cmd_config list shows message when empty" {
  run cmd_config list
  [ "$status" -eq 0 ]
  [[ "$output" == *"No gtr configuration found"* ]]
}

# ── Scope flags ──────────────────────────────────────────────────────────────

@test "cmd_config set --global writes to global config" {
  cmd_config set gtr.editor.default zed --global 2>/dev/null
  local value
  value=$(git config --global --get gtr.editor.default 2>/dev/null || true)
  [ "$value" = "zed" ]
  # Clean up global
  git config --global --unset gtr.editor.default 2>/dev/null || true
}

@test "cmd_config list --local shows only local config" {
  cmd_config set gtr.editor.default vim 2>/dev/null
  run cmd_config list --local
  [ "$status" -eq 0 ]
  [[ "$output" == *"gtr.editor.default"* ]]
}

# ── Validation ───────────────────────────────────────────────────────────────

@test "cmd_config get without key fails" {
  run cmd_config get
  [ "$status" -eq 1 ]
}

@test "cmd_config set without value fails" {
  run cmd_config set gtr.editor.default
  [ "$status" -eq 1 ]
}

@test "cmd_config rejects --system for write operations" {
  run cmd_config set gtr.editor.default vim --system
  [ "$status" -eq 1 ]
}
