#!/usr/bin/env bats
# Fixture commits must not depend on a developer's signing key or agent.

load test_helper

setup() {
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/global.gitconfig"
  export FIXTURE_SIGNER_LOG="$BATS_TEST_TMPDIR/signer.log"
  local signer="$BATS_TEST_TMPDIR/failing-signer"
  cat > "$signer" <<'SCRIPT'
#!/usr/bin/env bash
printf 'invoked\n' >> "$FIXTURE_SIGNER_LOG"
exit 1
SCRIPT
  chmod +x "$signer"
  git config --file "$GIT_CONFIG_GLOBAL" commit.gpgsign true
  git config --file "$GIT_CONFIG_GLOBAL" gpg.format openpgp
  git config --file "$GIT_CONFIG_GLOBAL" gpg.program "$signer"
  git config --file "$GIT_CONFIG_GLOBAL" gpg.openpgp.program "$signer"
  git config --file "$GIT_CONFIG_GLOBAL" user.signingkey fixture-only
  git config --file "$GIT_CONFIG_GLOBAL" test.inherited preserved
  cp "$GIT_CONFIG_GLOBAL" "$BATS_TEST_TMPDIR/global.before"
}

teardown() {
  if [ -n "${TEST_REPO:-}" ]; then
    teardown_integration_repo
  fi
  cmp "$BATS_TEST_TMPDIR/global.before" "$GIT_CONFIG_GLOBAL"
}

@test "signing control invokes only the harmless failing signer" {
  local repo="$BATS_TEST_TMPDIR/control"
  git init --quiet "$repo"

  run git -C "$repo" -c user.name=Test -c user.email=test@example.com \
    commit --allow-empty --quiet -m control

  [ "$status" -ne 0 ]
  [ "$(cat "$FIXTURE_SIGNER_LOG")" = invoked ]
  run git -C "$repo" rev-parse --verify HEAD
  [ "$status" -ne 0 ]
}

@test "integration fixture creates initial and subsequent commits without signing" {
  setup_integration_repo
  [ "$(git log -1 --format=%s)" = init ]

  git commit --allow-empty --quiet -m subsequent

  [ "$(git rev-list --count HEAD)" -eq 2 ]
  [ "$(git log -1 --format=%s)" = subsequent ]
  [ "$(git config --global --get commit.gpgsign)" = true ]
  [ "$(git config --get test.inherited)" = preserved ]
  [ ! -e "$FIXTURE_SIGNER_LOG" ]
}

@test "linked fixture worktrees inherit unsigned commits" {
  setup_integration_repo
  source_gtr_libs
  create_test_worktree fixture-branch

  git -C "$TEST_WT_PATH" commit --allow-empty --quiet -m linked

  [ "$(git -C "$TEST_WT_PATH" rev-list --count HEAD)" -eq 2 ]
  [ "$(git -C "$TEST_WT_PATH" log -1 --format=%s)" = linked ]
  [ "$(git rev-list --count HEAD)" -eq 1 ]
  [ ! -e "$FIXTURE_SIGNER_LOG" ]
}
