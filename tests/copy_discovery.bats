#!/usr/bin/env bats

load test_helper
load copy_discovery_helper

setup() {
  source "$PROJECT_ROOT/lib/platform.sh"
  source "$PROJECT_ROOT/lib/copy.sh"
  _test_tmpdir=$(mktemp -d)
  install_copy_find_stub "$_test_tmpdir/bin"
  # Neither caller option setting may hide a producer failure or be changed.
  set +o pipefail
}

teardown() {
  cd /
  rm -rf "$_test_tmpdir"
}

@test "recursive merges retain find failure before or after NUL output and keep incomplete directories private" {
  local src="$_test_tmpdir/source space" dst="$_test_tmpdir/dest"
  local partial level target result
  mkdir -p "$src/cache/nested" "$dst"
  echo value > "$src/cache/nested/"$'line\nbreak'
  chmod 755 "$src/cache" "$src/cache/nested"
  for level in cache cache/nested; do
    TEST_COPY_FIND_ARGS="$src/$level -mindepth 1 -maxdepth 1 -print0"
    for partial in empty partial; do
      target="$dst/${level//\//-}-$partial"
      TEST_COPY_FIND_RECORD=""
      if [ "$partial" = partial ]; then
        if [ "$level" = cache ]; then
          TEST_COPY_FIND_RECORD="$src/cache/nested"
        else
          TEST_COPY_FIND_RECORD="$src/cache/nested/"$'line\nbreak'
        fi
      fi
      result=0
      _copy_tree_entry "$src/cache" "$target" || result=$?
      [ "$result" -ne 0 ]
      [ "$(stat -c '%a' "$target" 2>/dev/null || stat -f '%Lp' "$target")" = 700 ]
      if [ "$partial" = partial ]; then
        [ "$(cat "$target/nested/"$'line\nbreak')" = value ]
        [ ! -e "$target/nested/break" ]
      fi
      [[ ":$SHELLOPTS:" != *:pipefail:* ]]
    done
  done
  [ -s "$TEST_COPY_FIND_HIT" ]
}

@test "Bash 3.2 file discovery rejects failures in either globstar scan before copying partial matches" {
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst" scan partial
  mkdir -p "$src/nested" "$dst"
  echo value > "$src/root.txt"
  echo value > "$src/nested/file.txt"
  cd "$src"
  for scan in recursive root; do
    if [ "$scan" = recursive ]; then
      TEST_COPY_FIND_ARGS='. -path ./**/*.txt -type f -print0'
    else
      TEST_COPY_FIND_ARGS='. -maxdepth 1 -path ./*.txt -type f -print0'
    fi
    for partial in empty partial; do
      TEST_COPY_FIND_RECORD=""
      [ "$partial" = empty ] || TEST_COPY_FIND_RECORD='./root.txt'
      run _expand_and_copy_pattern '**/*.txt' "$dst" '' true false 0
      [ "$status" -ne 0 ]
      [ "$output" = 0 ]
      [ ! -e "$dst/root.txt" ]
      [ ! -e "$dst/nested" ]
    done
  done
  [ -s "$TEST_COPY_FIND_HIT" ]
}

@test "copy_patterns restores cwd and shell options after failed fallback discovery" {
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst" before_pwd before_options result=0
  mkdir -p "$src" "$dst"
  echo value > "$src/root.txt"
  # Exercise the old-Bash path even when BATS runs under modern Bash.
  shopt() {
    [ "$*" != '-s globstar' ] || return 1
    builtin shopt "$@"
  }
  TEST_COPY_FIND_ARGS='. -path ./**/*.txt -type f -print0'
  TEST_COPY_FIND_RECORD='./root.txt'
  before_pwd=$PWD
  before_options=$(set +o; shopt -p)
  copy_patterns "$src" "$dst" '**/*.txt' '' || result=$?
  [ "$result" -ne 0 ]
  [ "$PWD" = "$before_pwd" ]
  [ "$(set +o; shopt -p)" = "$before_options" ]
  [ ! -e "$dst/root.txt" ]
}

@test "directory discovery retains failures from shallow bounded and recursive batches through cwd restoration" {
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst" scan partial pattern result before_pwd
  mkdir -p "$src/vendor" "$src/pkg/vendor" "$src/pkg/cache" "$src/literal" "$dst"
  echo value > "$src/vendor/file"
  before_pwd=$PWD
  for scan in shallow bounded recursive; do
    case "$scan" in
      shallow)
        pattern='vendor*'
        TEST_COPY_FIND_ARGS='. -maxdepth 1 -type d -name vendor* -print0'
        ;;
      bounded)
        pattern=$'pkg/*\nmissing'
        TEST_COPY_FIND_ARGS='. -maxdepth 2 -type d ( -path ./pkg/* ) -print0'
        ;;
      recursive)
        pattern=$'**/vendor\ncache'
        TEST_COPY_FIND_ARGS='. -type d ( -path ./**/vendor -o -name cache ) -print0'
        ;;
    esac
    for partial in empty partial; do
      TEST_COPY_FIND_RECORD=""
      [ "$partial" = empty ] || TEST_COPY_FIND_RECORD='./vendor'
      result=0
      # A successful literal or later scan must not erase an earlier failure.
      _resolve_directory_patterns "$src" "$pattern"$'\nliteral' > "$_test_tmpdir/resolved" || result=$?
      [ "$result" -ne 0 ]
      [ "$PWD" = "$before_pwd" ]
      [[ ":$SHELLOPTS:" != *:pipefail:* ]]
      run copy_directories "$src" "$dst" "$pattern"$'\nliteral' ''
      [ "$status" -ne 0 ]
      [ ! -e "$dst/vendor" ]
      [ ! -e "$dst/literal" ]
    done
  done
  [ -s "$TEST_COPY_FIND_HIT" ]
}

@test "selective traversal rejects partial discovery and leaves directory permissions private" {
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src/vendor" "$dst"
  echo value > "$src/vendor/file"
  chmod 755 "$src/vendor"
  TEST_COPY_FIND_ARGS='vendor -mindepth 1 -maxdepth 1 -print0'
  TEST_COPY_FIND_RECORD='vendor/file'
  run copy_directories "$src" "$dst" vendor '' false '*.pem'
  [ "$status" -ne 0 ]
  [ ! -e "$dst/vendor/file" ]
  [ "$(stat -c '%a' "$dst/vendor" 2>/dev/null || stat -f '%Lp' "$dst/vendor")" = 700 ]
}

@test "staging cleanup scan failures abort publication even when later verification would succeed" {
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst" partial
  mkdir -p "$src/cache" "$dst"
  echo value > "$src/cache/file"
  find() {
    case "$*" in
      *'-prune -exec'*)
        [ "$partial" != partial ] || command find "$@"
        return 7
        ;;
    esac
    command find "$@"
  }
  for partial in empty partial; do
    run _fast_copy_dir "$src/cache" "$dst/"
    [ "$status" -ne 0 ]
    [ ! -e "$dst/cache" ]
    [ -z "$(command find "$dst" -name '.gtr-copy.*' -print)" ]
  done
}

@test "successful empty and excluded discovery remains successful with either pipefail setting" {
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst" option
  mkdir -p "$src/vendor" "$dst"
  echo value > "$src/root.txt"
  for option in off on; do
    [ "$option" = off ] || set -o pipefail
    run copy_directories "$src" "$dst" $'missing*\npkg/*\n**/missing\nvendor' vendor
    [ "$status" -eq 0 ]
    cd "$src"
    run _expand_and_copy_pattern '**/*.txt' "$dst" '*.txt' true false 0
    [ "$status" -eq 0 ]
    [ "$output" = 0 ]
    run _expand_and_copy_pattern '**/*.missing' "$dst" '' true false 0
    [ "$status" -eq 0 ]
    [ "$output" = 0 ]
    [ ! -e "$dst/vendor" ]
    [ ! -e "$dst/root.txt" ]
  done
}
