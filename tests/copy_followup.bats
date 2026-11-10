#!/usr/bin/env bats

load test_helper

setup() {
  setup_integration_repo
  export XDG_CONFIG_HOME="$TEST_REPO/private-config"
  source_gtr_commands
}

teardown() {
  teardown_integration_repo
}

# A committed relative symlink resolves differently in the source checkout and
# its sibling worktree. Uncommitted regular source files supply the copy bytes.
# Both the existing sentinel and absent target are outside the new worktree.
relative_link_copy_case() {
  local kind="$1" state="$2" target=payload relative
  mkdir outside
  if [ "$state" = existing ]; then
    printf 'sentinel\n' > outside/payload
  fi
  relative="../../${TEST_REPO##*/}/outside"
  git config -f .gtrconfig worktrees.dir "../${TEST_WORKTREES_DIR##*/}"
  if [ "$kind" = leaf ]; then
    ln -s "$relative/payload" payload
    git config -f .gtrconfig copy.include payload
  else
    ln -s "$relative" redirect
    git config -f .gtrconfig copy.include redirect/payload
    target=redirect/payload
  fi
  git add .gtrconfig "${target%%/*}"
  git commit --quiet -m 'relative destination link fixture'
  rm "${target%%/*}"
  if [ "$kind" = parent ]; then mkdir redirect; fi
  printf 'replacement\n' > "$target"
  [ ! -d "$XDG_CONFIG_HOME/gtr/trusted" ]

  run "$PROJECT_ROOT/bin/gtr" new feature/followup --from HEAD --no-fetch --yes
  [ "$status" -eq 0 ]
  [ -L "$TEST_WORKTREES_DIR/feature-followup/${target%%/*}" ]
  # Confirm that following the checkout's link really would reach the fixture.
  if [ "$state" = existing ]; then
    [ "$(cat "$TEST_WORKTREES_DIR/feature-followup/$target")" = sentinel ]
    [ "$(cat outside/payload)" = sentinel ]
  else
    [ ! -e outside/payload ]
  fi
  [ ! -d "$XDG_CONFIG_HOME/gtr/trusted" ]
}

@test "unapproved configured copy cannot overwrite through a committed relative leaf link" {
  relative_link_copy_case leaf existing
}

@test "unapproved configured copy cannot create through a dangling relative leaf link" {
  relative_link_copy_case leaf absent
}

@test "repository naming and worktrees.dir cannot overwrite through a relative parent link" {
  relative_link_copy_case parent existing
}

@test "repository naming and worktrees.dir cannot create through a relative parent link" {
  relative_link_copy_case parent absent
}
