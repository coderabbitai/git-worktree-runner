#!/usr/bin/env bats

setup() {
  load test_helper
  _fast_copy_os=""
  source "$PROJECT_ROOT/lib/platform.sh"
  source "$PROJECT_ROOT/lib/copy.sh"
}

teardown() {
  if [ -n "${_test_tmpdir:-}" ]; then
    rm -rf "$_test_tmpdir"
  fi
}

# --- _is_unsafe_path tests ---

@test "absolute path is unsafe" {
  _is_unsafe_path "/etc/passwd"
}

@test "relative path is safe" {
  ! _is_unsafe_path "src/main.js"
}

@test "parent traversal at start is unsafe" {
  _is_unsafe_path "../secret"
}

@test "parent traversal in middle is unsafe" {
  _is_unsafe_path "foo/../../etc/passwd"
}

@test "parent traversal at end is unsafe" {
  _is_unsafe_path "foo/.."
}

@test "bare double-dot is unsafe" {
  _is_unsafe_path ".."
}

@test "dotfile is safe" {
  ! _is_unsafe_path ".env"
}

@test "nested relative path is safe" {
  ! _is_unsafe_path "src/lib/utils.js"
}

@test "glob pattern is safe" {
  ! _is_unsafe_path "*.txt"
}

@test "double-star glob is safe" {
  ! _is_unsafe_path "**/*.js"
}

# --- is_excluded tests ---

@test "exact match is excluded" {
  is_excluded "node_modules" "node_modules"
}

@test "non-matching path is not excluded" {
  ! is_excluded "src/index.js" "node_modules"
}

@test "glob pattern excludes matching path" {
  is_excluded "build/output.js" "build/*"
}

@test "empty excludes means nothing excluded" {
  ! is_excluded "anything" ""
}

@test "multiple excludes work" {
  local excludes
  excludes=$(printf '%s\n' "*.log" "dist/*" "node_modules")
  is_excluded "error.log" "$excludes"
}

@test "multiple excludes check all patterns" {
  local excludes
  excludes=$(printf '%s\n' "*.log" "dist/*" "node_modules")
  is_excluded "dist/bundle.js" "$excludes"
}

@test "non-matching against multiple excludes" {
  local excludes
  excludes=$(printf '%s\n' "*.log" "dist/*")
  ! is_excluded "src/app.js" "$excludes"
}

# --- _fast_copy_dir tests ---

@test "_fast_copy_dir copies directory contents" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src" "$dst"
  mkdir -p "$src/mydir/sub"
  echo "hello" > "$src/mydir/sub/file.txt"

  _fast_copy_dir "$src/mydir" "$dst/"

  [ -f "$dst/mydir/sub/file.txt" ]
  [ "$(cat "$dst/mydir/sub/file.txt")" = "hello" ]
}

@test "_fast_copy_dir preserves symlinks" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src" "$dst"
  mkdir -p "$src/mydir"
  echo "target" > "$src/mydir/real.txt"
  ln -s real.txt "$src/mydir/link.txt"

  _fast_copy_dir "$src/mydir" "$dst/"

  [ -L "$dst/mydir/link.txt" ]
  [ "$(readlink "$dst/mydir/link.txt")" = "real.txt" ]
}

@test "_fast_copy_dir fails on nonexistent source" {
  _test_tmpdir=$(mktemp -d)
  ! _fast_copy_dir "/nonexistent/path" "$_test_tmpdir/"
}

# --- _expand_and_copy_pattern find-fallback tests ---
# These test the Bash 3.2 fallback path (have_globstar=0)

@test "find fallback: empty results don't cause failures" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src" "$dst"

  cd "$src"
  local count
  count=$(_expand_and_copy_pattern "**/.nonexistent*" "$dst" "" "true" "false" "0")
  [ "$count" -eq 0 ]
}

@test "find fallback: **/ pattern matches root-level files" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src" "$dst"
  echo "secret" > "$src/.env"
  echo "local" > "$src/.env.local"

  cd "$src"
  local count
  count=$(_expand_and_copy_pattern "**/.env*" "$dst" "" "true" "false" "0")
  [ "$count" -eq 2 ]
  [ -f "$dst/.env" ]
  [ -f "$dst/.env.local" ]
}

@test "find fallback: **/ pattern matches nested files" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src/subdir" "$dst"
  echo "nested" > "$src/subdir/.env"

  cd "$src"
  local count
  count=$(_expand_and_copy_pattern "**/.env" "$dst" "" "true" "false" "0")
  [ "$count" -eq 1 ]
  [ -f "$dst/subdir/.env" ]
}

@test "find fallback: **/ pattern matches both root and nested files" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src/config" "$dst"
  echo "root" > "$src/CLAUDE.md"
  echo "nested" > "$src/config/CLAUDE.md"

  cd "$src"
  local count
  count=$(_expand_and_copy_pattern "**/CLAUDE.md" "$dst" "" "true" "false" "0")
  [ "$count" -eq 2 ]
  [ -f "$dst/CLAUDE.md" ]
  [ -f "$dst/config/CLAUDE.md" ]
}
