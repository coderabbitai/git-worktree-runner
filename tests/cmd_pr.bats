#!/usr/bin/env bats
# Integration tests for cmd_pr in lib/commands/pr.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
  TEST_REMOTE_REPO=$(mktemp -d)
  TEST_OTHER_REMOTE_ROOT=$(mktemp -d)
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
  rm -rf "$TEST_REMOTE_REPO" "$TEST_OTHER_REMOTE_ROOT" "$TEST_MOCK_BIN"
}

@test "cmd_pr creates worktree from GitHub pull request ref" {
  cmd_pr 123 --remote origin --no-copy --no-hooks --yes

  [ -d "$TEST_WORKTREES_DIR/feature-from-pr" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/feature-from-pr" rev-parse HEAD)" = "$TEST_PR_SHA" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/feature-from-pr" rev-parse --abbrev-ref HEAD)" = "feature/from-pr" ]
  [ "$(git config branch.feature/from-pr.remote)" = "https://github.com/octo/example.git" ]
  [ "$(git config branch.feature/from-pr.pushRemote)" = "https://github.com/octo/example.git" ]
  [ "$(git config branch.feature/from-pr.merge)" = "refs/heads/feature/from-pr" ]
}

@test "cmd_pr supports custom local branch and folder" {
  cmd_pr 123 --branch review/pr-123 --folder review-123 --remote origin --no-copy --no-hooks --yes

  [ -d "$TEST_WORKTREES_DIR/review-123" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/review-123" rev-parse HEAD)" = "$TEST_PR_SHA" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/review-123" rev-parse --abbrev-ref HEAD)" = "review/pr-123" ]
  [ "$(git config branch.review/pr-123.merge)" = "refs/heads/feature/from-pr" ]
}

@test "cmd_pr reuses ssh remote matching resolved PR base repository" {
  git remote add upstream git@github.com:base/example.git

  [ "$(_pr_remote_for_url https://github.com/base/example.git)" = "upstream" ]
}

@test "cmd_pr fetches the resolved PR base repository by default" {
  local other_remote other_sha
  other_remote="$TEST_OTHER_REMOTE_ROOT/other.git"
  git init --bare "$other_remote" --quiet
  git commit --allow-empty -m "other pr head" --quiet
  other_sha=$(git rev-parse HEAD)
  git push "$other_remote" HEAD:refs/pull/999/head --quiet
  git push origin HEAD~1:refs/pull/999/head --quiet
  cat > "$TEST_MOCK_BIN/gh" <<SCRIPT
#!/usr/bin/env bash
printf '999\tfeature/from-other\tocto\texample\tfile://$other_remote/pull/999\n'
SCRIPT
  chmod +x "$TEST_MOCK_BIN/gh"

  cmd_pr 999 --branch other/pr --folder other-pr --no-copy --no-hooks --yes

  [ -d "$TEST_WORKTREES_DIR/other-pr" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/other-pr" rev-parse HEAD)" = "$other_sha" ]
  [ "$(git remote get-url gtr-pr-999-base)" = "file://$other_remote" ]
  [ "$(git config remote.gtr-pr-999-base.gh-resolved)" = "base" ]
}

@test "cmd_pr preserves existing branch metadata" {
  git branch feature/from-pr "$TEST_PR_SHA"
  git config branch.feature/from-pr.remote keep-remote
  git config branch.feature/from-pr.pushRemote keep-push
  git config branch.feature/from-pr.merge refs/heads/keep

  cmd_pr 123 --remote origin --folder reused-pr --no-copy --no-hooks --yes

  [ "$(git config branch.feature/from-pr.remote)" = "keep-remote" ]
  [ "$(git config branch.feature/from-pr.pushRemote)" = "keep-push" ]
  [ "$(git config branch.feature/from-pr.merge)" = "refs/heads/keep" ]
}

@test "cmd_pr sanitizes custom name suffix" {
  cmd_pr 123 --remote origin --name "../review/path" --no-copy --no-hooks --yes

  [ -d "$TEST_WORKTREES_DIR/feature-from-pr-..-review-path" ]
}

@test "cmd_pr rejects existing local branch at a different commit" {
  git branch feature/from-pr HEAD~1

  run cmd_pr 123 --remote origin --no-copy --no-hooks --yes

  [ "$status" -eq 1 ]
  [ ! -d "$TEST_WORKTREES_DIR/feature-from-pr" ]
  [ "$(git rev-parse feature/from-pr)" != "$TEST_PR_SHA" ]
}

@test "cmd_pr rejects missing selector in non-interactive mode" {
  run cmd_pr --yes
  [ "$status" -eq 1 ]
}

@test "cmd_pr rejects force without a distinct folder" {
  run cmd_pr 123 --force --remote origin --no-copy --no-hooks --yes
  [ "$status" -eq 1 ]
}

@test "cmd_pr requires GitHub CLI" {
  local old_path no_gh_bin tool
  old_path="$PATH"
  no_gh_bin=$(mktemp -d)
  for tool in bash git basename dirname grep sed mktemp cat rm; do
    ln -s "$(command -v "$tool")" "$no_gh_bin/$tool"
  done

  PATH="$no_gh_bin" run cmd_pr 123 --remote origin --no-copy --no-hooks --yes
  PATH="$old_path"
  rm -rf "$no_gh_bin"

  [ "$status" -eq 1 ]
  [[ "$output" == *"gh is required"* ]]
}
