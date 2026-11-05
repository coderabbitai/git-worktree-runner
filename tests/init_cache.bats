#!/usr/bin/env bats
# Security regressions for executable shell-integration caches.

load test_helper

setup() {
  source "$PROJECT_ROOT/lib/commands/init.sh"
  CACHE_FIXTURE=$(cd "$(mktemp -d)" && pwd -P)
  export XDG_CACHE_HOME="$CACHE_FIXTURE/cache"
  export GTR_VERSION=test
  unset GTR_INIT_CACHE_VERSION
}

teardown() {
  chmod -R u+rwX "$CACHE_FIXTURE"
  rm -rf "$CACHE_FIXTURE"
}

seed_cache_payload() {
  mkdir -p "$XDG_CACHE_HOME/gtr"
  printf '%s\n%s\n' '# gtr-cache: version=test init=10 func=gtr shell=bash' \
    'touch "$XDG_CACHE_HOME/executed"' > "$XDG_CACHE_HOME/gtr/init-gtr.bash"
}

assert_cache_bypassed() {
  local expected original
  expected=$(_init_bash | sed 's/__FUNC__/gtr/g')
  original=$(cat "$XDG_CACHE_HOME/gtr/init-gtr.bash")
  run cmd_init bash
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
  [ "$(cat "$XDG_CACHE_HOME/gtr/init-gtr.bash")" = "$original" ]
  eval "$output"
  declare -F gtr >/dev/null
  [ ! -e "$XDG_CACHE_HOME/executed" ]
}

@test "matching-stamp writable cache cannot inject evaluated shell code" {
  seed_cache_payload
  chmod 666 "$XDG_CACHE_HOME/gtr/init-gtr.bash"
  assert_cache_bypassed
}

@test "writable cache directory or ancestor bypasses reads and writes" {
  local path mode
  seed_cache_payload
  for path in "$XDG_CACHE_HOME/gtr" "$XDG_CACHE_HOME" "$CACHE_FIXTURE"; do
    for mode in 775 777; do
      chmod "$mode" "$path"
      assert_cache_bypassed
      chmod 700 "$path"
    done
  done
  # The cache directory itself must not use the sticky-parent exception.
  chmod 1777 "$XDG_CACHE_HOME/gtr"
  assert_cache_bypassed
}

@test "new caches remain private under a permissive umask" {
  run bash -c '
    set -e
    source "$1/lib/commands/init.sh"
    umask 000
    cmd_init bash >/dev/null
    [ "$(umask)" = 0000 ]
  ' -- "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  local path mode
  for path in "$XDG_CACHE_HOME" "$XDG_CACHE_HOME/gtr" "$XDG_CACHE_HOME/gtr/init-gtr.bash"; do
    mode=$(stat -c '%a' "$path" 2>/dev/null) || mode=$(stat -f '%Lp' "$path")
    if [ -d "$path" ]; then [ "$mode" = 700 ]; else [ "$mode" = 600 ]; fi
  done
}

@test "safe cache is reused without running the generator" {
  cmd_init bash >/dev/null
  local expected
  expected=$(tail -n +2 "$XDG_CACHE_HOME/gtr/init-gtr.bash")
  _init_bash() { printf 'unexpected regeneration\n'; return 1; }
  run cmd_init bash
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
}

@test "safe legacy cache modes remain supported" {
  cmd_init bash >/dev/null
  chmod 755 "$XDG_CACHE_HOME" "$XDG_CACHE_HOME/gtr"
  chmod 644 "$XDG_CACHE_HOME/gtr/init-gtr.bash"
  _init_bash() { printf 'unexpected regeneration\n'; return 1; }
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *'gtr()'* ]]
}

@test "cache file symlinks are neither read nor overwritten" {
  seed_cache_payload
  mv "$XDG_CACHE_HOME/gtr/init-gtr.bash" "$CACHE_FIXTURE/payload"
  ln -s "$CACHE_FIXTURE/payload" "$XDG_CACHE_HOME/gtr/init-gtr.bash"
  assert_cache_bypassed
  rm "$CACHE_FIXTURE/payload"
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *'gtr()'* ]]
  [ -L "$XDG_CACHE_HOME/gtr/init-gtr.bash" ]
  [ ! -e "$CACHE_FIXTURE/payload" ]
}

@test "gtr cache directory symlinks are neither read nor written" {
  seed_cache_payload
  mv "$XDG_CACHE_HOME/gtr" "$CACHE_FIXTURE/payload-dir"
  ln -s "$CACHE_FIXTURE/payload-dir" "$XDG_CACHE_HOME/gtr"
  assert_cache_bypassed
  rm "$CACHE_FIXTURE/payload-dir/init-gtr.bash"
  run cmd_init bash
  [ "$status" -eq 0 ]
  [ ! -e "$CACHE_FIXTURE/payload-dir/init-gtr.bash" ]
}

@test "safe XDG paths with spaces and symlinked parents retain caching" {
  mkdir "$CACHE_FIXTURE/real cache"
  ln -s "$CACHE_FIXTURE/real cache" "$CACHE_FIXTURE/cache alias"
  export XDG_CACHE_HOME="$CACHE_FIXTURE/cache alias/nested cache"
  run cmd_init bash
  [ "$status" -eq 0 ]
  [ -f "$CACHE_FIXTURE/real cache/nested cache/gtr/init-gtr.bash" ]
  _init_bash() { printf 'unexpected regeneration\n'; return 1; }
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *'gtr()'* ]]
}

@test "default HOME cache and relative XDG paths retain caching" {
  export HOME="$CACHE_FIXTURE/home"
  mkdir "$HOME"
  unset XDG_CACHE_HOME
  run cmd_init bash
  [ "$status" -eq 0 ]
  [ -f "$HOME/.cache/gtr/init-gtr.bash" ]
  cd "$CACHE_FIXTURE"
  export XDG_CACHE_HOME='relative cache'
  run cmd_init bash
  [ "$status" -eq 0 ]
  [ -f "$CACHE_FIXTURE/relative cache/gtr/init-gtr.bash" ]
}

@test "unsafe symlink targets and link parents bypass the cache" {
  seed_cache_payload
  mv "$XDG_CACHE_HOME" "$CACHE_FIXTURE/target"
  ln -s "$CACHE_FIXTURE/target" "$XDG_CACHE_HOME"
  chmod 777 "$CACHE_FIXTURE/target"
  assert_cache_bypassed
  chmod 700 "$CACHE_FIXTURE/target"
  mkdir "$CACHE_FIXTURE/unsafe"
  mv "$XDG_CACHE_HOME" "$CACHE_FIXTURE/unsafe/cache-link"
  export XDG_CACHE_HOME="$CACHE_FIXTURE/unsafe/cache-link"
  chmod 777 "$CACHE_FIXTURE/unsafe"
  assert_cache_bypassed
}

@test "cache bypass preserves output and success under set -e for every shell" {
  mkdir "$XDG_CACHE_HOME"
  chmod 777 "$XDG_CACHE_HOME"
  local shell_name expected
  for shell_name in bash zsh fish; do
    expected=$("_init_$shell_name" | sed 's/__FUNC__/custom_gtr/g')
    run bash -c '
      set -e
      source "$1/lib/commands/init.sh"
      cmd_init "$2" --as custom_gtr
    ' -- "$PROJECT_ROOT" "$shell_name"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected" ]
    [ ! -e "$XDG_CACHE_HOME/gtr" ]
  done
}

@test "non-directory cache paths and non-regular cache files are left untouched" {
  mkdir -p "$XDG_CACHE_HOME/gtr/init-gtr.bash"
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *'gtr()'* ]]
  [ -d "$XDG_CACHE_HOME/gtr/init-gtr.bash" ]
  rmdir "$XDG_CACHE_HOME/gtr/init-gtr.bash"
  mkfifo "$XDG_CACHE_HOME/gtr/init-gtr.bash"
  run cmd_init bash
  [ "$status" -eq 0 ]
  [ -p "$XDG_CACHE_HOME/gtr/init-gtr.bash" ]
  rm "$XDG_CACHE_HOME/gtr/init-gtr.bash"
  rmdir "$XDG_CACHE_HOME/gtr"
  printf 'keep\n' > "$XDG_CACHE_HOME/gtr"
  run cmd_init bash
  [ "$status" -eq 0 ]
  [ "$(cat "$XDG_CACHE_HOME/gtr")" = keep ]
}

@test "cache validation failures are silent cache misses" {
  seed_cache_payload
  stat() { return 1; }
  assert_cache_bypassed
}

@test "failed cache publication preserves output and the previous cache" {
  cmd_init bash >/dev/null
  local expected original
  expected=$(_init_bash | sed 's/__FUNC__/gtr/g')
  original=$(cat "$XDG_CACHE_HOME/gtr/init-gtr.bash")
  export GTR_VERSION=new-version
  mv() { return 1; }
  run cmd_init bash
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
  [ "$(cat "$XDG_CACHE_HOME/gtr/init-gtr.bash")" = "$original" ]
  [ -z "$(find "$XDG_CACHE_HOME/gtr" -name '.init.*' -print)" ]
}

@test "cache publication replaces a stale file without modifying its hard links" {
  seed_cache_payload
  ln "$XDG_CACHE_HOME/gtr/init-gtr.bash" "$CACHE_FIXTURE/original"
  local original
  original=$(cat "$CACHE_FIXTURE/original")
  export GTR_VERSION=new-version
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *'gtr()'* ]]
  [ "$(cat "$CACHE_FIXTURE/original")" = "$original" ]
  [[ "$(head -1 "$XDG_CACHE_HOME/gtr/init-gtr.bash")" == *'version=new-version '* ]]
}

@test "unsafe paths after missing components are checked before writing" {
  mkdir "$CACHE_FIXTURE/unsafe"
  chmod 777 "$CACHE_FIXTURE/unsafe"
  export XDG_CACHE_HOME="$CACHE_FIXTURE/missing/../unsafe/cache"
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *'gtr()'* ]]
  [ ! -e "$CACHE_FIXTURE/unsafe/cache" ]
}

@test "cache files and directories must belong to the current user" {
  seed_cache_payload
  local rejected
  for rejected in "$XDG_CACHE_HOME/gtr" "$XDG_CACHE_HOME/gtr/init-gtr.bash"; do
    # Exercise foreign ownership without requiring chown privileges in CI.
    stat() {
      if [ "${!#}" = "$rejected" ]; then
        printf '123456789 700\n'
      else
        command stat "$@"
      fi
    }
    assert_cache_bypassed
    unset -f stat
  done
}

@test "macOS write ACLs bypass the cache even with safe mode bits" {
  [ "$(uname -s)" = Darwin ] || skip "macOS ACL syntax"
  seed_cache_payload
  chmod +a 'everyone allow write,append' "$XDG_CACHE_HOME/gtr/init-gtr.bash"
  assert_cache_bypassed
}
