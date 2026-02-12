#!/usr/bin/env bats
# Integration tests for cmd_create in lib/commands/create.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
}

teardown() {
  teardown_integration_repo
}

# Note: --from HEAD is needed because test repos have no origin remote,
# so resolve_default_branch can't detect a default branch.

@test "cmd_create creates worktree with basic args" {
  cmd_create new-feature --from HEAD --no-fetch --yes
  [ -d "$TEST_WORKTREES_DIR/new-feature" ]
}

@test "cmd_create creates worktree with --track none" {
  cmd_create track-none --from HEAD --track none --no-fetch --yes
  [ -d "$TEST_WORKTREES_DIR/track-none" ]
}

@test "cmd_create creates worktree with --name suffix" {
  cmd_create named-branch --from HEAD --name backend --no-fetch --yes
  [ -d "$TEST_WORKTREES_DIR/named-branch-backend" ]
}

@test "cmd_create creates worktree with --folder override" {
  cmd_create folder-branch --from HEAD --folder my-custom --no-fetch --yes
  [ -d "$TEST_WORKTREES_DIR/my-custom" ]
}

@test "cmd_create rejects --folder + --name together" {
  run cmd_create test --folder a --name b --no-fetch --yes
  [ "$status" -eq 1 ]
}

@test "cmd_create rejects --force without --name or --folder" {
  run cmd_create test --force --no-fetch --yes
  [ "$status" -eq 1 ]
}

@test "cmd_create --no-copy skips file copying" {
  git config --add gtr.copy.include ".env"
  echo "secret" > "$TEST_REPO/.env"
  cmd_create no-copy-test --from HEAD --no-copy --no-fetch --yes
  [ ! -f "$TEST_WORKTREES_DIR/no-copy-test/.env" ]
}

@test "cmd_create --no-hooks skips post-create hooks" {
  git config --add gtr.hook.postCreate "touch hook-ran"
  cmd_create no-hook-test --from HEAD --no-hooks --no-fetch --yes
  [ ! -f "$TEST_WORKTREES_DIR/no-hook-test/hook-ran" ]
}

@test "cmd_create runs post-create hooks when enabled" {
  git config --add gtr.hook.postCreate 'touch "$WORKTREE_PATH/hook-ran"'
  cmd_create hook-test --from HEAD --no-fetch --yes
  [ -f "$TEST_WORKTREES_DIR/hook-test/hook-ran" ]
}

@test "cmd_create sanitizes slashed branch name for folder" {
  cmd_create feature/deep --from HEAD --no-fetch --yes
  [ -d "$TEST_WORKTREES_DIR/feature-deep" ]
}
