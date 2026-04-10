#!/usr/bin/env bats
# Tests for lib/hooks.sh

load test_helper

setup() {
  setup_integration_repo
  export XDG_CONFIG_HOME="$BATS_TMPDIR/gtr-hooks-config-$$"
  source_gtr_libs
}

teardown() {
  rm -rf "$XDG_CONFIG_HOME"
  teardown_integration_repo
}

@test "run_hooks returns 0 when no hooks configured" {
  run run_hooks postCreate REPO_ROOT="$TEST_REPO"
  [ "$status" -eq 0 ]
}

@test "_hooks_file_hash matches the init wrapper trust hash" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[hooks]
  postCd = echo hi
EOF

  local expected
  expected="$(git config -f "$TEST_REPO/.gtrconfig" --get-regexp '^hooks\.' 2>/dev/null | shasum -a 256 | cut -d' ' -f1)"

  [ "$(_hooks_file_hash "$TEST_REPO/.gtrconfig")" = "$expected" ]
}

@test "_hooks_mark_trusted creates a marker recognized by _hooks_are_trusted" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[hooks]
  postCd = echo hi
EOF

  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  _hooks_are_trusted "$TEST_REPO/.gtrconfig"
}

@test "_hooks_are_trusted rejects empty trust marker files" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[hooks]
  postCd = echo hi
EOF

  local trust_path
  trust_path="$(_hooks_trust_path "$TEST_REPO/.gtrconfig")"
  mkdir -p "$(dirname "$trust_path")"
  : > "$trust_path"

  run _hooks_are_trusted "$TEST_REPO/.gtrconfig"
  [ "$status" -eq 1 ]
}

@test "_hooks_are_trusted treats configs without hooks as trusted" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[copy]
  include = .env
EOF

  _hooks_are_trusted "$TEST_REPO/.gtrconfig"
}

@test "_hooks_are_trusted fails closed when trust path resolution errors" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[hooks]
  postCd = echo hi
EOF

  _hooks_reviewed_trust_path() { return 1; }

  ! _hooks_are_trusted "$TEST_REPO/.gtrconfig"
}

@test "_hooks_mark_trusted fails when trust path resolution errors" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[hooks]
  postCd = echo hi
EOF

  _hooks_reviewed_trust_path() { return 1; }

  ! _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
}

@test "repo-specific trust markers differ for the same hook content" {
  local second_repo="$BATS_TMPDIR/second-repo"
  mkdir -p "$second_repo"

  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[hooks]
  postCd = ./scripts/bootstrap
EOF

  cat > "$second_repo/.gtrconfig" <<'EOF'
[hooks]
  postCd = ./scripts/bootstrap
EOF

  local first_path second_path
  first_path="$(_hooks_trust_path "$TEST_REPO/.gtrconfig")"
  second_path="$(_hooks_trust_path "$second_repo/.gtrconfig")"

  [ "$first_path" != "$second_path" ]
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

@test "run_hooks continues after hook that reads stdin (postCreate)" {
  git config --add gtr.hook.postCreate 'echo first >> "$REPO_ROOT/order"'
  git config --add gtr.hook.postCreate 'cat'
  git config --add gtr.hook.postCreate 'echo third >> "$REPO_ROOT/order"'
  run_hooks postCreate REPO_ROOT="$TEST_REPO"
  [ "$(head -1 "$TEST_REPO/order")" = "first" ]
  [ "$(tail -1 "$TEST_REPO/order")" = "third" ]
}

@test "run_hooks continues after hook that reads stdin (preRemove)" {
  git config --add gtr.hook.preRemove 'echo first >> "$REPO_ROOT/order"'
  git config --add gtr.hook.preRemove 'cat'
  git config --add gtr.hook.preRemove 'echo third >> "$REPO_ROOT/order"'
  run_hooks preRemove REPO_ROOT="$TEST_REPO"
  [ "$(head -1 "$TEST_REPO/order")" = "first" ]
  [ "$(tail -1 "$TEST_REPO/order")" = "third" ]
}

@test "run_hooks continues after hook that reads stdin (postRemove)" {
  git config --add gtr.hook.postRemove 'echo first >> "$REPO_ROOT/order"'
  git config --add gtr.hook.postRemove 'cat'
  git config --add gtr.hook.postRemove 'echo third >> "$REPO_ROOT/order"'
  run_hooks postRemove REPO_ROOT="$TEST_REPO"
  [ "$(head -1 "$TEST_REPO/order")" = "first" ]
  [ "$(tail -1 "$TEST_REPO/order")" = "third" ]
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

@test "run_hooks_export continues after hook that reads stdin (postCd)" {
  git config --add gtr.hook.postCd 'echo first >> "$REPO_ROOT/order"'
  git config --add gtr.hook.postCd 'cat'
  git config --add gtr.hook.postCd 'echo third >> "$REPO_ROOT/order"'
  (cd "$TEST_REPO" && run_hooks_export postCd REPO_ROOT="$TEST_REPO")
  [ "$(head -1 "$TEST_REPO/order")" = "first" ]
  [ "$(tail -1 "$TEST_REPO/order")" = "third" ]
}
