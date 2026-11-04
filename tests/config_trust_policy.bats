#!/usr/bin/env bats
# Git configuration is user-controlled; .gtrconfig commands require approval.
# Fixture commands expand variables only when invoked by the child shell.
# BATS owns the status/output variables across its test functions.
# shellcheck disable=SC2016,SC2030,SC2031
load test_helper

setup() {
  POLICY_FIXTURE=$(cd -P "$(mktemp -d)" && pwd)
  export XDG_CONFIG_HOME="$POLICY_FIXTURE/config"
  export XDG_CACHE_HOME="$POLICY_FIXTURE/cache"
  export XDG_DATA_HOME="$POLICY_FIXTURE/data"
  export GIT_CONFIG_GLOBAL="$POLICY_FIXTURE/global.gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  export POLICY_EVENTS="$POLICY_FIXTURE/events"
  : > "$GIT_CONFIG_GLOBAL"
  setup_integration_repo
  source_gtr_commands
}

teardown() {
  teardown_integration_repo
  rm -rf "$POLICY_FIXTURE"
}

# Write globals by explicit filename so fixture setup cannot modify user config.
configure_policy_hooks() {
  local phase="$1"
  git config -f "$GIT_CONFIG_GLOBAL" --add "gtr.hook.$phase" \
    "printf '%s\\n' 'global.$phase' >> \"\$POLICY_EVENTS\""
  git config --local --add "gtr.hook.$phase" \
    "printf '%s\\n' 'local.$phase' >> \"\$POLICY_EVENTS\""
  git config -f "$TEST_REPO/.gtrconfig" --add "hooks.$phase" \
    "printf '%s\\n' 'untrusted.$phase' >> \"\$POLICY_EVENTS\""
}

check_policy_lifecycle() {
  local scope="$1" destination="$POLICY_FIXTURE/worktrees with spaces"
  local phase result
  for phase in postCreate preRemove postRemove; do
    configure_policy_hooks "$phase"
  done
  git config -f "$GIT_CONFIG_GLOBAL" gtr.worktrees.dir "$destination"
  if [ "$scope" = local ]; then
    # Local configuration must override both team and global destinations.
    git config -f "$GIT_CONFIG_GLOBAL" gtr.worktrees.dir "$POLICY_FIXTURE/global-unused"
    git config -f "$TEST_REPO/.gtrconfig" worktrees.dir "$POLICY_FIXTURE/team-unused"
    git config --local gtr.worktrees.dir "$destination"
  fi

  # Use the actual CLI (set -e), with all network operations disabled.
  result=$("$PROJECT_ROOT/bin/gtr" new policy-feature --from HEAD --no-fetch --no-copy \
    --porcelain 2> "$POLICY_FIXTURE/create.stderr")
  [ "$result" = $'path\t'"$destination/policy-feature"$'\nbranch\tpolicy-feature\nhook_status\tpartial' ]
  [ -d "$destination/policy-feature" ]
  [ ! -e "$POLICY_FIXTURE/global-unused" ]
  [ ! -e "$POLICY_FIXTURE/team-unused" ]
  [ "$(cat "$POLICY_EVENTS")" = $'global.postCreate\nlocal.postCreate' ]

  run "$PROJECT_ROOT/bin/gtr" rm policy-feature --yes
  [ "$status" -eq 0 ]
  [ ! -e "$destination/policy-feature" ]
  [ "$(cat "$POLICY_EVENTS")" = $'global.postCreate\nlocal.postCreate\nglobal.preRemove\nlocal.preRemove\nglobal.postRemove\nlocal.postRemove' ]
  [ ! -d "$_GTR_TRUST_DIR" ]
}

@test "local worktrees.dir and Git lifecycle hooks work while untrusted file hooks stay blocked" {
  check_policy_lifecycle local
}

@test "global worktrees.dir and Git lifecycle hooks work while untrusted file hooks stay blocked" {
  check_policy_lifecycle global
}

@test "untrusted worktrees.dir selects a literal destination without approving file hooks" {
  local destination="$POLICY_FIXTURE/"'$(touch should-not-run)'
  git config -f "$TEST_REPO/.gtrconfig" worktrees.dir "$destination"
  git config -f "$TEST_REPO/.gtrconfig" hooks.postCreate 'printf untrusted > "$POLICY_EVENTS"'

  run "$PROJECT_ROOT/bin/gtr" new literal-path --from HEAD --no-fetch --no-copy --porcelain
  [ "$status" -eq 0 ]
  [[ "$output" == *$'hook_status\tskipped-untrusted'* ]]
  [ -d "$destination/literal-path" ]
  [ ! -e "$TEST_REPO/should-not-run" ]
  [ ! -e "$POLICY_EVENTS" ]
  [ ! -d "$_GTR_TRUST_DIR" ]
}

@test "postCd export dispatcher runs Git hooks while untrusted file hooks stay blocked" {
  configure_policy_hooks postCd
  git config --local --add gtr.hook.postCd 'export POLICY_LOCAL_EXPORT=local'
  git config -f "$TEST_REPO/.gtrconfig" --add hooks.postCd 'export POLICY_LOCAL_EXPORT=untrusted'

  # Run with strict mode in a child shell, as used by the AI launch path.
  run bash -e -c '
    source "$GTR_DIR/lib/config.sh"
    source "$GTR_DIR/lib/hooks.sh"
    run_hooks_export postCd
    [ "$POLICY_LOCAL_EXPORT" = local ]
  '
  [ "$status" -eq 0 ]
  [ "$(cat "$POLICY_EVENTS")" = $'global.postCd\nlocal.postCd' ]
  [ ! -d "$_GTR_TRUST_DIR" ]
}

check_generated_policy_hooks() {
  local shell_name="$1"
  command -v "$shell_name" >/dev/null 2>&1 || skip "$shell_name is not installed"
  configure_policy_hooks postCd
  export POLICY_INIT="$POLICY_FIXTURE/init.$shell_name"
  export POLICY_WORKTREE="$POLICY_FIXTURE/linked worktree"
  git worktree add --quiet "$POLICY_WORKTREE" -b policy-cd HEAD
  "$PROJECT_ROOT/bin/gtr" init "$shell_name" > "$POLICY_INIT"

  run "$shell_name" -c 'source "$POLICY_INIT"; gtr_run_post_cd_hooks "$POLICY_WORKTREE"'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Untrusted .gtrconfig hooks skipped"* ]]
  [ "$(cat "$POLICY_EVENTS")" = $'global.postCd\nlocal.postCd' ]
  [ ! -d "$_GTR_TRUST_DIR" ]
}

@test "bash generated postCd runs Git hooks while untrusted file hooks stay blocked" {
  check_generated_policy_hooks bash
}

@test "zsh generated postCd runs Git hooks while untrusted file hooks stay blocked" {
  check_generated_policy_hooks zsh
}

@test "fish generated postCd runs Git hooks while untrusted file hooks stay blocked" {
  check_generated_policy_hooks fish
}
