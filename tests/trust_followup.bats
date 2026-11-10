#!/usr/bin/env bats

load test_helper

setup() {
  setup_integration_repo
  export XDG_CONFIG_HOME="$TEST_REPO/private-config"
  export XDG_CACHE_HOME="$TEST_REPO/private-cache"
  export XDG_DATA_HOME="$TEST_REPO/private-data"
  source_gtr_commands
  export PATH="$PROJECT_ROOT/bin:$PATH"
}

teardown() {
  teardown_integration_repo
}

# Historical README setup bypassed the installed CLI entirely on an init=6
# cache hit. A binary upgrade cannot repair shell startup code it never runs.
legacy_setup_case() {
  local runtime="$1" snippet
  export LEGACY_CACHE_MARKER="$TEST_REPO/legacy-loaded"
  mkdir -p "$XDG_CACHE_HOME/gtr"
  printf '# gtr-cache: version=old init=6 func=gtr shell=%s\n' "$runtime" \
    > "$XDG_CACHE_HOME/gtr/init-gtr.$runtime"
  printf 'echo legacy > "$LEGACY_CACHE_MARKER"\n' \
    >> "$XDG_CACHE_HOME/gtr/init-gtr.$runtime"
  if [ "$runtime" = fish ]; then
    snippet='set -l _gtr_init "$XDG_CACHE_HOME/gtr/init-gtr.fish"
test -f "$_gtr_init"; and head -n 1 "$_gtr_init" | string match -q "* init=6 *"; or git gtr init fish >/dev/null 2>&1
source "$_gtr_init" 2>/dev/null'
  else
    export LEGACY_SHELL="$runtime"
    snippet='_gtr_init="$XDG_CACHE_HOME/gtr/init-gtr.$LEGACY_SHELL"
[[ -f "$_gtr_init" ]] && head -n 1 "$_gtr_init" | grep -q " init=6 " || eval "$(git gtr init "$LEGACY_SHELL")" || true
source "$_gtr_init" 2>/dev/null || true; unset _gtr_init'
  fi
  "$runtime" -c "$snippet"
  [ "$(cat "$LEGACY_CACHE_MARKER")" = legacy ]
  rm "$LEGACY_CACHE_MARKER"
  # Explicitly invoking the installed generator migrates the old cache.
  cmd_init "$runtime" >/dev/null
  "$runtime" -c "$snippet"
  [ ! -e "$LEGACY_CACHE_MARKER" ]
}

@test "legacy bash init=6 startup needs regeneration or startup migration" {
  legacy_setup_case bash
}

@test "legacy zsh init=6 startup needs regeneration or startup migration" {
  command -v zsh >/dev/null || skip "zsh unavailable"
  legacy_setup_case zsh
}

@test "legacy fish init=6 startup needs regeneration or startup migration" {
  command -v fish >/dev/null || skip "fish unavailable"
  legacy_setup_case fish
}
