#!/usr/bin/env bats
# Tests for lib/hooks.sh

load test_helper

setup() {
  setup_integration_repo
  export XDG_CONFIG_HOME="$BATS_TMPDIR/gtr-hooks-config-$$"
  source_gtr_libs
}

teardown() {
  rm -rf "$XDG_CONFIG_HOME" "$BATS_TMPDIR/no-shasum-bin-$$"
  teardown_integration_repo
}

@test "run_hooks returns 0 when no hooks configured" {
  run run_hooks postCreate REPO_ROOT="$TEST_REPO"
  [ "$status" -eq 0 ]
}

@test "_hooks_phase_status reports none without configured hooks" {
  [ "$(_hooks_phase_status postCreate)" = "none" ]
}

@test "_hooks_phase_status reports ran for trusted git config hooks" {
  git config --add gtr.hook.postCreate "echo local"
  [ "$(_hooks_phase_status postCreate)" = "ran" ]
}

@test "_hooks_phase_status reports skipped-untrusted for untrusted file hooks" {
  git config -f "$TEST_REPO/.gtrconfig" --add hooks.postCreate "echo shared"
  [ "$(_hooks_phase_status postCreate)" = "skipped-untrusted" ]
}

@test "_hooks_phase_status reports ran for trusted file hooks" {
  git config -f "$TEST_REPO/.gtrconfig" --add hooks.postCreate "echo shared"
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  [ "$(_hooks_phase_status postCreate)" = "ran" ]
}

@test "_hooks_phase_status reports partial for runnable and untrusted hooks" {
  git config --add gtr.hook.postCreate "echo local"
  git config -f "$TEST_REPO/.gtrconfig" --add hooks.postCreate "echo shared"
  [ "$(_hooks_phase_status postCreate)" = "partial" ]
}

@test "_hooks_file_hash matches the init wrapper trust hash" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[hooks]
  postCd = echo hi
EOF

  local expected
  expected="$(git config -f "$TEST_REPO/.gtrconfig" -z --get-regexp '^hooks\.|^defaults\.editor$|^defaults\.ai$' 2>/dev/null | od -An -v -tx1 | tr -d ' \n' | { encoded=$(cat); printf '%s\n' "$encoded"; } | shasum -a 256 | cut -d' ' -f1)"

  [ "$(_hooks_file_hash "$TEST_REPO/.gtrconfig")" = "$expected" ]
}

@test "_hooks_file_hash includes executable defaults" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[defaults]
  ai = npx --package=./malicious evilbin
EOF

  local expected
  expected="$(git config -f "$TEST_REPO/.gtrconfig" -z --get-regexp '^hooks\.|^defaults\.editor$|^defaults\.ai$' 2>/dev/null | od -An -v -tx1 | tr -d ' \n' | { encoded=$(cat); printf '%s\n' "$encoded"; } | shasum -a 256 | cut -d' ' -f1)"

  [ "$(_hooks_file_hash "$TEST_REPO/.gtrconfig")" = "$expected" ]
}

@test "trust markers work when shasum is not installed" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[hooks]
  postCd = echo hi
EOF

  local expected
  expected="$(_hooks_file_hash "$TEST_REPO/.gtrconfig")"

  local no_shasum_path
  no_shasum_path="$(path_without_command "$BATS_TMPDIR/no-shasum-bin-$$" shasum)"

  (
    PATH="$no_shasum_path"
    if command -v shasum >/dev/null 2>&1; then
      exit 1
    fi

    [ "$(_hooks_file_hash "$TEST_REPO/.gtrconfig")" = "$expected" ]
    _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
    _hooks_are_trusted "$TEST_REPO/.gtrconfig"
  )
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

@test "_hooks_are_trusted treats configs without trusted command definitions as trusted" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[copy]
  include = .env
EOF

  _hooks_are_trusted "$TEST_REPO/.gtrconfig"
}

@test "_hooks_are_trusted requires trust for executable defaults" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[defaults]
  editor = npx --package=./malicious evilbin
EOF

  run _hooks_are_trusted "$TEST_REPO/.gtrconfig"
  [ "$status" -eq 1 ]
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
  git -C "$second_repo" init --quiet

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

@test "replacement repository cannot reuse trust for identical definitions and changed delegated code" {
  git config -f "$TEST_REPO/.gtrconfig" hooks.postCreate 'sh ./bootstrap.sh'
  printf 'echo original > hook-result\n' > "$TEST_REPO/bootstrap.sh"
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  local original_hash original_path
  original_hash=$(_hooks_file_hash "$TEST_REPO/.gtrconfig")
  original_path=$(_hooks_trust_path "$TEST_REPO/.gtrconfig")
  run_hooks_in postCreate "$TEST_REPO"
  [ "$(cat "$TEST_REPO/hook-result")" = original ]

  # Keep the old Git directory alive so this fixture cannot reuse its inode.
  mv "$TEST_REPO/.git" "$TEST_REPO/original-git"
  git -C "$TEST_REPO" init --quiet
  printf 'echo replacement > hook-result\n' > "$TEST_REPO/bootstrap.sh"
  rm "$TEST_REPO/hook-result"
  [ "$(_hooks_file_hash "$TEST_REPO/.gtrconfig")" = "$original_hash" ]
  run_hooks_in postCreate "$TEST_REPO"
  [ ! -f "$TEST_REPO/hook-result" ]
  [ "$(_hooks_trust_path "$TEST_REPO/.gtrconfig")" != "$original_path" ]
  ! _hooks_are_trusted "$TEST_REPO/.gtrconfig"
}

@test "legacy path-only approval cannot approve a repository instance" {
  git config -f "$TEST_REPO/.gtrconfig" hooks.postCd 'echo harmless'
  local legacy_key
  legacy_key=$(printf '%s\n%s\n' "$TEST_REPO" "$(_hooks_file_hash "$TEST_REPO/.gtrconfig")" |
    shasum -a 256 | cut -d' ' -f1)
  mkdir -p "$_GTR_TRUST_DIR"
  printf '%s\n' "$TEST_REPO/.gtrconfig" > "$_GTR_TRUST_DIR/$legacy_key"
  ! _hooks_are_trusted "$TEST_REPO/.gtrconfig"
}

@test "deleting and recreating the Git directory cannot reuse approval" {
  git config -f "$TEST_REPO/.gtrconfig" hooks.postCd 'sh ./bootstrap.sh'
  printf 'echo original\n' > "$TEST_REPO/bootstrap.sh"
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  local original_identity iteration=0
  original_identity=$(_hooks_repo_identity "$TEST_REPO")
  while [ "$iteration" -lt 10 ]; do
    rm -rf "$TEST_REPO/.git"
    git -C "$TEST_REPO" init --quiet
    printf 'echo replacement\n' > "$TEST_REPO/bootstrap.sh"
    [ "$(_hooks_repo_identity "$TEST_REPO")" != "$original_identity" ]
    ! _hooks_are_trusted "$TEST_REPO/.gtrconfig"
    iteration=$((iteration + 1))
  done
}

@test "unknown or unavailable Git directory birth times fail closed" {
  git config -f "$TEST_REPO/.gtrconfig" hooks.postCd 'echo harmless'
  stat() { printf '%s\n' "$fixture_stat"; }
  local fixture_stat
  for fixture_stat in '1:2:0.000000000' '1:2:0' '1:2:-' '1:2:-1.000000000'; do
    ! _hooks_repo_identity "$TEST_REPO"
    ! _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  done
}

@test "definition trust survives delegated script changes in the same repository" {
  git config -f "$TEST_REPO/.gtrconfig" hooks.postCreate 'sh ./bootstrap.sh'
  printf 'echo original\n' > "$TEST_REPO/bootstrap.sh"
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  printf 'echo updated\n' > "$TEST_REPO/bootstrap.sh"
  _hooks_are_trusted "$TEST_REPO/.gtrconfig"
}

@test "repository identity stays stable across commits and linked worktrees" {
  git config -f "$TEST_REPO/.gtrconfig" hooks.postCreate 'echo harmless'
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  git -C "$TEST_REPO" commit --allow-empty -m second --quiet
  create_test_worktree identity-test
  (cd "$TEST_WT_PATH" && _hooks_are_trusted "$TEST_REPO/.gtrconfig")
}

@test "trust fails closed when repository identity cannot be resolved" {
  git config -f "$TEST_REPO/.gtrconfig" hooks.postCd 'echo harmless'
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  _hooks_repo_identity() { return 1; }
  ! _hooks_are_trusted "$TEST_REPO/.gtrconfig"
  ! _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
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

@test "trust encoding distinguishes multiline defaults from added hook records" {
  git config -f "$TEST_REPO/.gtrconfig" defaults.ai $'echo safe\nhooks.postcd echo attacker'
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  git config -f "$TEST_REPO/.gtrconfig" defaults.ai 'echo safe'
  git config -f "$TEST_REPO/.gtrconfig" hooks.postCd 'echo attacker'
  ! _hooks_are_trusted "$TEST_REPO/.gtrconfig"
}

@test "hook execution uses the captured definitions after config replacement" {
  git config -f "$TEST_REPO/.gtrconfig" hooks.postCd 'echo approved'
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  eval "$(declare -f _hooks_snapshot_is_trusted | sed '1s/_hooks_snapshot_is_trusted/_original_snapshot_is_trusted/')"
  _hooks_snapshot_is_trusted() {
    _original_snapshot_is_trusted "$@" || return 1
    git config -f "$1" hooks.postCd 'echo attacker'
  }
  run _hooks_get_trusted postCd
  [ "$status" -eq 0 ]
  [ "$output" = 'echo approved' ]
}

@test "trusted defaults are selected from the snapshot whose marker is checked" {
  git config -f "$TEST_REPO/.gtrconfig" defaults.ai 'echo approved'
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  eval "$(declare -f _hooks_snapshot_is_trusted | sed '1s/_hooks_snapshot_is_trusted/_original_snapshot_is_trusted/')"
  _hooks_snapshot_is_trusted() {
    git config -f "$1" defaults.ai 'echo attacker'
    _original_snapshot_is_trusted "$@"
  }
  run cfg_default_trusted_file gtr.ai.default GTR_AI_DEFAULT fallback defaults.ai
  [ "$status" -eq 0 ]
  [ "$output" = 'echo approved' ]
}

@test "generated shells hash and extract the same multiline snapshot" {
  source "$PROJECT_ROOT/lib/commands/init.sh"
  git config -f "$TEST_REPO/.gtrconfig" defaults.ai $'echo safe\n\n'
  git config -f "$TEST_REPO/.gtrconfig" hooks.postCd 'echo approved'
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  local snapshot expected shell script
  snapshot=$(_hooks_read_definitions "$TEST_REPO/.gtrconfig")
  expected=$(_hooks_current_trust_key "$TEST_REPO/.gtrconfig")
  for shell in bash zsh fish; do
    command -v "$shell" >/dev/null || continue
    script="$BATS_TEST_TMPDIR/helpers.$shell"
    if [ "$shell" = fish ]; then
      _init_emit_fish_trust_helpers | sed 's/__FUNC__/gtr/g' > "$script"
      printf '\ngtr_hooks_current_trust_key "$argv[1]"\ngtr_hooks_definitions_get "$argv[2]" hooks.postCd\n' >> "$script"
    else
      _init_emit_posix_trust_helpers '' | sed 's/__FUNC__/gtr/g' > "$script"
      printf '\ngtr_hooks_current_trust_key "$1"\ngtr_hooks_definitions_get "$2" hooks.postCd\n' >> "$script"
    fi
    run "$shell" "$script" "$TEST_REPO/.gtrconfig" "$snapshot"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected"$'\n''echo approved' ]
  done
}

@test "snapshot defaults retain git config last-value and boolean semantics" {
  git config -f "$TEST_REPO/.gtrconfig" --add defaults.ai first
  git config -f "$TEST_REPO/.gtrconfig" --add defaults.ai last
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  [ "$(cfg_default_trusted_file gtr.ai.default '' fallback defaults.ai)" = last ]
  printf '[defaults]\n ai\n' > "$TEST_REPO/.gtrconfig"
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  [ "$(cfg_default_trusted_file gtr.ai.default '' fallback defaults.ai)" = fallback ]
}

@test "GNU repository identity retains birth nanoseconds within the same second" {
  local birth_fraction=123456789 first second
  stat() {
    case "$*" in
      *%W:%w*) printf '1:2:1793140000:2026-10-27 23:00:00.%s +0000\n' "$birth_fraction" ;;
      *) printf '1:2:1793140000.000000000\n' ;;
    esac
  }
  first=$(_hooks_repo_identity "$TEST_REPO")
  birth_fraction=987654321
  second=$(_hooks_repo_identity "$TEST_REPO")
  [ "$first" != "$second" ]
}
