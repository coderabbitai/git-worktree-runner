#!/usr/bin/env bats
# Public entry points must reject Git configuration writable by another user.
# BATS owns status/output across test functions.
# shellcheck disable=SC2016,SC2030,SC2031
load test_helper

setup() {
  SAFETY_FIXTURE=$(cd -P "$(mktemp -d)" && pwd)
  export XDG_CONFIG_HOME="$SAFETY_FIXTURE/config"
  export XDG_CACHE_HOME="$SAFETY_FIXTURE/cache"
  export XDG_DATA_HOME="$SAFETY_FIXTURE/data"
  export GIT_CONFIG_GLOBAL="$SAFETY_FIXTURE/global.gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  export SAFETY_MARKER="$SAFETY_FIXTURE/executed"
  : > "$GIT_CONFIG_GLOBAL"
  setup_integration_repo
  git config gtr.worktrees.dir "$SAFETY_FIXTURE/attacker destination"
  git config gtr.hook.postCreate 'printf executed > "$SAFETY_MARKER"'
  git config gtr.hook.postCd 'printf executed > "$SAFETY_MARKER"'
}

teardown() {
  teardown_integration_repo
  rm -rf "$SAFETY_FIXTURE"
}

# Exercise both injected settings through the real CLI, without network access.
assert_unsafe_create_blocked() {
  run "$PROJECT_ROOT/bin/gtr" new unsafe-config --from HEAD --no-fetch --no-copy
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsafe Git configuration"* ]]
  [ ! -e "$SAFETY_MARKER" ]
  [ ! -e "$SAFETY_FIXTURE/attacker destination" ]
  ! git show-ref --verify --quiet refs/heads/unsafe-config
}

@test "group-writable local Git config cannot execute hooks or redirect worktrees" {
  chmod 0660 "$TEST_REPO/.git/config"
  assert_unsafe_create_blocked
}

@test "normally protected Git config still supports hooks and worktrees.dir" {
  chmod 0600 "$TEST_REPO/.git/config"
  run "$PROJECT_ROOT/bin/gtr" new protected-config --from HEAD --no-fetch --no-copy
  [ "$status" -eq 0 ]
  [ -d "$SAFETY_FIXTURE/attacker destination/protected-config" ]
  [ "$(cat "$SAFETY_MARKER")" = executed ]
}

# Generate while safe, then change permissions: cached helpers must recheck.
assert_unsafe_shell_blocked() {
  local shell_name="$1" init_file="$SAFETY_FIXTURE/init"
  command -v "$shell_name" >/dev/null 2>&1 || skip "$shell_name is not installed"
  "$PROJECT_ROOT/bin/gtr" init "$shell_name" > "$init_file"
  chmod 0660 "$TEST_REPO/.git/config"
  export SAFETY_INIT="$init_file" SAFETY_REPO="$TEST_REPO"
  case "$shell_name" in
    bash|zsh)
      run "$shell_name" -f -c 'compdef() { :; }; source "$SAFETY_INIT"; gtr_run_post_cd_hooks "$SAFETY_REPO"'
      ;;
    fish)
      run fish --no-config -c 'source "$SAFETY_INIT"; gtr_run_post_cd_hooks "$SAFETY_REPO"'
      ;;
  esac
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsafe Git configuration"* ]]
  [ ! -e "$SAFETY_MARKER" ]
}

@test "cached bash postCd helper refuses newly writable Git config" {
  assert_unsafe_shell_blocked bash
}

@test "cached zsh postCd helper refuses newly writable Git config" {
  assert_unsafe_shell_blocked zsh
}

@test "cached fish postCd helper refuses newly writable Git config" {
  assert_unsafe_shell_blocked fish
}

@test "a read-only config in a group-writable Git directory is rejected" {
  chmod 0600 "$TEST_REPO/.git/config"
  chmod 0770 "$TEST_REPO/.git"
  assert_unsafe_create_blocked
}

@test "world-writable config is rejected" {
  chmod 0606 "$TEST_REPO/.git/config"
  assert_unsafe_create_blocked
}

@test "writable included config is rejected even through a relative include" {
  git config -f "$TEST_REPO/.git/shared config" gtr.hook.postCreate 'printf included > "$SAFETY_MARKER"'
  git config include.path 'shared config'
  chmod 0660 "$TEST_REPO/.git/shared config"
  assert_unsafe_create_blocked
}

@test "empty writable includes cannot acquire commands after validation" {
  : > "$TEST_REPO/.git/empty config"
  git config include.path 'empty config'
  chmod 0660 "$TEST_REPO/.git/empty config"
  assert_unsafe_create_blocked
}

@test "unsafe symlink targets and their parents are rejected" {
  mkdir "$SAFETY_FIXTURE/shared"
  git config -f "$SAFETY_FIXTURE/shared/included" gtr.hook.postCreate 'printf linked > "$SAFETY_MARKER"'
  ln -s "$SAFETY_FIXTURE/shared/included" "$TEST_REPO/.git/linked-config"
  git config include.path linked-config
  chmod 0770 "$SAFETY_FIXTURE/shared"
  assert_unsafe_create_blocked
}

@test "symlink parent permissions are checked before following a safe target" {
  mkdir "$SAFETY_FIXTURE/shared"
  git config -f "$SAFETY_FIXTURE/protected" gtr.hook.postCreate 'printf linked > "$SAFETY_MARKER"'
  ln -s "$SAFETY_FIXTURE/protected" "$SAFETY_FIXTURE/shared/link"
  git config include.path "$SAFETY_FIXTURE/shared/link"
  chmod 0770 "$SAFETY_FIXTURE/shared"
  assert_unsafe_create_blocked
}

@test "protected includes and symlinks preserve normal hook execution" {
  git config -f "$SAFETY_FIXTURE/protected" gtr.hook.postCreate 'printf included > "$SAFETY_MARKER"'
  ln -s "$SAFETY_FIXTURE/protected" "$TEST_REPO/.git/linked-config"
  git config include.path linked-config
  run "$PROJECT_ROOT/bin/gtr" new safe-includes --from HEAD --no-fetch --no-copy
  [ "$status" -eq 0 ]
  [ "$(cat "$SAFETY_MARKER")" = included ]
}

@test "group-writable global config is rejected" {
  chmod 0660 "$GIT_CONFIG_GLOBAL"
  assert_unsafe_create_blocked
}

@test "group-writable system config is rejected" {
  export GIT_CONFIG_NOSYSTEM=0 GIT_CONFIG_SYSTEM="$SAFETY_FIXTURE/system"
  : > "$GIT_CONFIG_SYSTEM"
  chmod 0660 "$GIT_CONFIG_SYSTEM"
  assert_unsafe_create_blocked
}

@test "linked worktree startup checks its common Git config" {
  git worktree add --quiet "$SAFETY_FIXTURE/linked" -b linked HEAD
  chmod 0660 "$TEST_REPO/.git/config"
  cd "$SAFETY_FIXTURE/linked"
  assert_unsafe_create_blocked
}

@test "hook dispatch rechecks the target worktree-specific config" {
  git config extensions.worktreeConfig true
  git worktree add --quiet "$SAFETY_FIXTURE/linked" -b linked HEAD
  git -C "$SAFETY_FIXTURE/linked" config --worktree gtr.hook.postCd 'printf worktree > "$SAFETY_MARKER"'
  local config_file
  config_file=$(git -C "$SAFETY_FIXTURE/linked" rev-parse --git-path config.worktree)
  chmod 0660 "$config_file"
  source_gtr_libs
  run run_hooks_in postCd "$SAFETY_FIXTURE/linked"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Unsafe Git configuration"* ]]
  [ ! -e "$SAFETY_MARKER" ]
}

@test "export dispatcher refuses unsafe Git config" {
  chmod 0660 "$TEST_REPO/.git/config"
  source_gtr_libs
  run run_hooks_export postCd
  [ "$status" -ne 0 ]
  [ ! -e "$SAFETY_MARKER" ]
}

@test "bare repository config is checked before creation" {
  git clone --quiet --bare "$TEST_REPO" "$SAFETY_FIXTURE/bare.git"
  git -C "$SAFETY_FIXTURE/bare.git" config gtr.worktrees.dir "$SAFETY_FIXTURE/attacker destination"
  chmod 0660 "$SAFETY_FIXTURE/bare.git/config"
  cd "$SAFETY_FIXTURE/bare.git"
  assert_unsafe_create_blocked
}

@test "macOS write ACLs cannot bypass mode-bit checks" {
  [ "$(uname -s)" = Darwin ] || skip "macOS ACL syntax"
  chmod +a 'everyone allow write' "$TEST_REPO/.git/config"
  assert_unsafe_create_blocked
}

@test "the null device can still disable global Git config" {
  export GIT_CONFIG_GLOBAL=/dev/null
  run "$PROJECT_ROOT/bin/gtr" new null-config --from HEAD --no-fetch --no-copy
  [ "$status" -eq 0 ]
  [ "$(cat "$SAFETY_MARKER")" = executed ]
}

@test "Git include expansion preserves a newline in the target filename" {
  local included="$SAFETY_FIXTURE/with newline"$'\n'
  git config -f "$included" gtr.hook.postCreate 'printf included > "$SAFETY_MARKER"'
  git config include.path "$included"
  chmod 0660 "$included"
  assert_unsafe_create_blocked
}
