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
printf '123\tfeature/from-pr\tocto\texample\thttps://github.com/base/example/pull/123\n'
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

  [ -d "$TEST_WORKTREES_DIR/feature-from-pr" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/feature-from-pr" rev-parse HEAD)" = "$TEST_PR_SHA" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/feature-from-pr" branch --show-current)" = "feature/from-pr" ]
  [ "$(git config branch.feature/from-pr.remote)" = "https://github.com/octo/example.git" ]
  [ "$(git config branch.feature/from-pr.merge)" = "refs/heads/feature/from-pr" ]
}

@test "cmd_pr supports custom local branch and folder" {
  cmd_pr 123 --branch review/pr-123 --folder review-123 --no-copy --no-hooks --yes

  [ -d "$TEST_WORKTREES_DIR/review-123" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/review-123" rev-parse HEAD)" = "$TEST_PR_SHA" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/review-123" branch --show-current)" = "review/pr-123" ]
  [ "$(git config branch.review/pr-123.merge)" = "refs/heads/feature/from-pr" ]
}

@test "cmd_pr rejects existing local branch at a different commit" {
  git branch feature/from-pr HEAD~1

  run cmd_pr 123 --no-copy --no-hooks --yes

  [ "$status" -eq 1 ]
  [ ! -d "$TEST_WORKTREES_DIR/feature-from-pr" ]
  [ "$(git rev-parse feature/from-pr)" != "$TEST_PR_SHA" ]
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
