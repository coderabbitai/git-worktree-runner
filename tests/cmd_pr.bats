#!/usr/bin/env bats
# Integration tests for cmd_pr in lib/commands/pr.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
  TEST_REMOTE_REPO=$(mktemp -d)
  git -C "$TEST_REMOTE_REPO" init --bare --quiet
  git remote add origin "$TEST_REMOTE_REPO"
  git push origin HEAD:refs/heads/main --quiet
  git commit --allow-empty -m "pr head" --quiet
  TEST_PR_SHA=$(git rev-parse HEAD)
  git push origin HEAD:refs/pull/123/head --quiet
  TEST_MOCK_BIN=$(mktemp -d)
  cat > "$TEST_MOCK_BIN/gh" <<'SCRIPT'
#!/usr/bin/env bash
printf '123\tfeature/from-pr\n'
SCRIPT
  chmod +x "$TEST_MOCK_BIN/gh"
  export PATH="$TEST_MOCK_BIN:$PATH"
}

teardown() {
  teardown_integration_repo
  rm -rf "$TEST_REMOTE_REPO" "$TEST_MOCK_BIN"
}

@test "cmd_pr creates worktree from GitHub pull request ref" {
  cmd_pr 123 --no-copy --no-hooks --yes

  [ -d "$TEST_WORKTREES_DIR/pr-123" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/pr-123" rev-parse HEAD)" = "$TEST_PR_SHA" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/pr-123" branch --show-current)" = "pr/123" ]
}

@test "cmd_pr supports custom local branch and folder" {
  cmd_pr 123 --branch review/pr-123 --folder review-123 --no-copy --no-hooks --yes

  [ -d "$TEST_WORKTREES_DIR/review-123" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/review-123" rev-parse HEAD)" = "$TEST_PR_SHA" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/review-123" branch --show-current)" = "review/pr-123" ]
}

@test "cmd_pr rejects missing selector in non-interactive mode" {
  run cmd_pr --yes
  [ "$status" -eq 1 ]
}

@test "cmd_pr rejects force without a distinct folder" {
  run cmd_pr 123 --force --no-copy --no-hooks --yes
  [ "$status" -eq 1 ]
}

@test "cmd_pr requires GitHub CLI" {
  rm "$TEST_MOCK_BIN/gh"

  run cmd_pr 123 --no-copy --no-hooks --yes

  [ "$status" -eq 1 ]
}
