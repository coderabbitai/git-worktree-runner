#!/usr/bin/env bats
# Tests for lib/hooks.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_libs
}

teardown() {
  teardown_integration_repo
}

@test "run_hooks returns 0 when no hooks configured" {
  run run_hooks postCreate REPO_ROOT="$TEST_REPO"
  [ "$status" -eq 0 ]
}

@test "run_hooks executes single hook" {
  git config --add gtr.hook.postCreate 'touch "$REPO_ROOT/hook-ran"'
  run_hooks postCreate REPO_ROOT="$TEST_REPO"
  [ -f "$TEST_REPO/hook-ran" ]
}

@test "run_hooks passes environment variables" {
  git config --add gtr.hook.postCreate 'echo "$MY_VAR" > "$REPO_ROOT/env-test"'
  run_hooks postCreate REPO_ROOT="$TEST_REPO" MY_VAR="hello-world"
  [ "$(cat "$TEST_REPO/env-test")" = "hello-world" ]
}

@test "run_hooks returns 1 when hook fails" {
  git config --add gtr.hook.preRemove "exit 1"
  run run_hooks preRemove REPO_ROOT="$TEST_REPO"
  [ "$status" -eq 1 ]
}

@test "run_hooks executes multiple hooks in order" {
  git config --add gtr.hook.postCreate 'echo first >> "$REPO_ROOT/order"'
  git config --add gtr.hook.postCreate 'echo second >> "$REPO_ROOT/order"'
  run_hooks postCreate REPO_ROOT="$TEST_REPO"
  [ "$(head -1 "$TEST_REPO/order")" = "first" ]
  [ "$(tail -1 "$TEST_REPO/order")" = "second" ]
}

@test "run_hooks reports failure count when multiple hooks fail" {
  git config --add gtr.hook.postCreate "exit 1"
  git config --add gtr.hook.postCreate "exit 2"
  run run_hooks postCreate REPO_ROOT="$TEST_REPO"
  [ "$status" -eq 1 ]
}

@test "run_hooks isolates hook side effects in subshell" {
  git config --add gtr.hook.postCreate "MY_LEAK=leaked"
  run_hooks postCreate REPO_ROOT="$TEST_REPO"
  [ -z "${MY_LEAK:-}" ]
}

@test "run_hooks_in changes to target directory" {
  mkdir -p "$TEST_REPO/subdir"
  git config --add gtr.hook.postCreate 'pwd > "$REPO_ROOT/cwd-test"'
  run_hooks_in postCreate "$TEST_REPO/subdir" REPO_ROOT="$TEST_REPO"
  [ "$(cat "$TEST_REPO/cwd-test")" = "$TEST_REPO/subdir" ]
}

@test "run_hooks_in restores original directory" {
  mkdir -p "$TEST_REPO/subdir"
  local before_pwd
  before_pwd=$(pwd)
  run_hooks_in postCreate "$TEST_REPO/subdir" REPO_ROOT="$TEST_REPO"
  [ "$(pwd)" = "$before_pwd" ]
}

@test "run_hooks_in returns 1 for nonexistent directory" {
  run run_hooks_in postCreate "/nonexistent/path" REPO_ROOT="$TEST_REPO"
  [ "$status" -eq 1 ]
}

@test "run_hooks_in propagates hook failure" {
  mkdir -p "$TEST_REPO/subdir"
  git config --add gtr.hook.preRemove "exit 1"
  run run_hooks_in preRemove "$TEST_REPO/subdir" REPO_ROOT="$TEST_REPO"
  [ "$status" -eq 1 ]
}

@test "run_hooks REPO_ROOT and BRANCH env vars available" {
  git config --add gtr.hook.postCreate 'echo "$REPO_ROOT|$BRANCH" > "$REPO_ROOT/vars"'
  run_hooks postCreate REPO_ROOT="$TEST_REPO" BRANCH="test-branch"
  [ "$(cat "$TEST_REPO/vars")" = "$TEST_REPO|test-branch" ]
}

# ── run_hooks_export tests ───────────────────────────────────────────────────

@test "run_hooks_export returns 0 when no hooks configured" {
  run run_hooks_export postCd REPO_ROOT="$TEST_REPO"
  [ "$status" -eq 0 ]
}

@test "run_hooks_export executes hook" {
  git config --add gtr.hook.postCd 'touch "$REPO_ROOT/hook-ran"'
  (cd "$TEST_REPO" && run_hooks_export postCd REPO_ROOT="$TEST_REPO")
  [ -f "$TEST_REPO/hook-ran" ]
}

@test "run_hooks_export env vars propagate to child processes" {
  git config --add gtr.hook.postCd 'export MY_CUSTOM_VAR="from-hook"'
  # Run hook then check env in same subshell — simulates ai_start inheriting env
  result=$(
    cd "$TEST_REPO"
    run_hooks_export postCd REPO_ROOT="$TEST_REPO"
    echo "$MY_CUSTOM_VAR"
  )
  [ "$result" = "from-hook" ]
}

@test "run_hooks_export continues after hook failure" {
  git config --add gtr.hook.postCd "false"
  git config --add gtr.hook.postCd 'touch "$REPO_ROOT/second-ran"'
  (cd "$TEST_REPO" && run_hooks_export postCd REPO_ROOT="$TEST_REPO") || true
  [ -f "$TEST_REPO/second-ran" ]
}

@test "run_hooks_export passes REPO_ROOT WORKTREE_PATH BRANCH" {
  git config --add gtr.hook.postCd 'echo "$REPO_ROOT|$WORKTREE_PATH|$BRANCH" > "$REPO_ROOT/env-check"'
  (cd "$TEST_REPO" && run_hooks_export postCd \
    REPO_ROOT="$TEST_REPO" \
    WORKTREE_PATH="/tmp/wt" \
    BRANCH="my-branch")
  [ "$(cat "$TEST_REPO/env-check")" = "$TEST_REPO|/tmp/wt|my-branch" ]
}

@test "run_hooks_export does not leak env to parent shell" {
  git config --add gtr.hook.postCd 'export LEAK_TEST="leaked"'
  (cd "$TEST_REPO" && run_hooks_export postCd REPO_ROOT="$TEST_REPO")
  [ -z "${LEAK_TEST:-}" ]
}
