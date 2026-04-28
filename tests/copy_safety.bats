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

@test "_apply_directory_excludes supports node_modules/* patterns" {
  _test_tmpdir=$(mktemp -d)
  local dest="$_test_tmpdir/dest"
  mkdir -p "$dest/node_modules/.cache"
  touch "$dest/node_modules/.cache/file"

  _apply_directory_excludes "$dest" "node_modules" $'node_modules/*'

  [ ! -e "$dest/node_modules/.cache" ]
}

@test "_apply_directory_excludes skips patterns targeting .git metadata" {
  _test_tmpdir=$(mktemp -d)
  local dest="$_test_tmpdir/dest"
  mkdir -p "$dest/node_modules/.git"
  touch "$dest/node_modules/.git/config"

  _apply_directory_excludes "$dest" "node_modules" $'node_modules/.git'

  [ -e "$dest/node_modules/.git" ]
}

@test "_has_subdir_excludes returns true for child exclude" {
  _has_subdir_excludes ".claude" $'.claude/worktrees'
}

@test "_has_subdir_excludes returns false for unrelated exclude" {
  ! _has_subdir_excludes ".claude" $'node_modules\n.venv'
}

@test "_has_subdir_excludes returns false for exact parent exclude" {
  ! _has_subdir_excludes ".claude" ".claude"
}

@test "_has_subdir_excludes supports glob prefixes" {
  _has_subdir_excludes ".claude" $'*/worktrees'
}

@test "_has_subdir_excludes supports nested include paths" {
  _has_subdir_excludes "vendor/bundle" $'vendor/bundle/cache'
}

@test "_apply_directory_excludes supports nested include paths" {
  _test_tmpdir=$(mktemp -d)
  local dest="$_test_tmpdir/dest"
  mkdir -p "$dest/vendor/bundle/cache" "$dest/vendor/bundle/gems"
  touch "$dest/vendor/bundle/cache/blob"
  touch "$dest/vendor/bundle/gems/spec"

  _apply_directory_excludes "$dest" "vendor/bundle" $'vendor/bundle/cache'

  [ ! -e "$dest/vendor/bundle/cache" ]
  [ -f "$dest/vendor/bundle/gems/spec" ]
}

@test "_apply_directory_excludes supports nested glob prefixes" {
  _test_tmpdir=$(mktemp -d)
  local dest="$_test_tmpdir/dest"
  mkdir -p "$dest/vendor/bundle/cache" "$dest/vendor/bundle/gems"
  touch "$dest/vendor/bundle/cache/blob"
  touch "$dest/vendor/bundle/gems/spec"

  _apply_directory_excludes "$dest" "vendor/bundle" $'vendor/*/cache'

  [ ! -e "$dest/vendor/bundle/cache" ]
  [ -f "$dest/vendor/bundle/gems/spec" ]
}

@test "_apply_directory_excludes uses deepest matching glob prefix" {
  _test_tmpdir=$(mktemp -d)
  local dest="$_test_tmpdir/dest"
  mkdir -p "$dest/vendor/bundle/cache/tmp" "$dest/vendor/bundle/cache/keep"
  touch "$dest/vendor/bundle/cache/tmp/blob"
  touch "$dest/vendor/bundle/cache/keep/spec"

  _apply_directory_excludes "$dest" "vendor/bundle" $'*/bundle/cache/tmp'

  [ ! -e "$dest/vendor/bundle/cache/tmp" ]
  [ -f "$dest/vendor/bundle/cache/keep/spec" ]
}

@test "_selective_copy_dir skips excluded direct child" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src/.claude/settings" "$src/.claude/worktrees" "$dst"
  echo "keep" > "$src/.claude/settings/config.json"
  echo "skip" > "$src/.claude/worktrees/session.json"

  cd "$src"
  _selective_copy_dir ".claude" "$dst" $'.claude/worktrees'

  [ -f "$dst/.claude/settings/config.json" ]
  [ ! -e "$dst/.claude/worktrees" ]
}

@test "_selective_copy_dir skips trailing-slash excluded direct child" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src/.claude/settings" "$src/.claude/worktrees" "$dst"
  echo "keep" > "$src/.claude/settings/config.json"
  echo "skip" > "$src/.claude/worktrees/session.json"

  cd "$src"
  _selective_copy_dir ".claude" "$dst" $'.claude/worktrees/'

  [ -f "$dst/.claude/settings/config.json" ]
  [ ! -e "$dst/.claude/worktrees" ]
}

@test "_selective_copy_dir still applies deeper excludes after copy" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src/.claude/worktrees/cache" "$src/.claude/worktrees/keep" "$dst"
  echo "skip" > "$src/.claude/worktrees/cache/blob"
  echo "keep" > "$src/.claude/worktrees/keep/session.json"

  cd "$src"
  _selective_copy_dir ".claude" "$dst" $'.claude/worktrees/cache'

  [ ! -e "$dst/.claude/worktrees/cache" ]
  [ -f "$dst/.claude/worktrees/keep/session.json" ]
}

@test "copy_directories does not copy excluded direct child subtree" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst" copy_log="$_test_tmpdir/copy.log"
  mkdir -p "$src/.claude/settings" "$src/.claude/worktrees" "$dst"
  echo "keep" > "$src/.claude/settings/config.json"
  echo "skip" > "$src/.claude/worktrees/session.json"

  _fast_copy_dir() {
    printf '%s\n' "$1" >> "$copy_log"
    cp -RP "$1" "$2"
  }

  copy_directories "$src" "$dst" ".claude" $'.claude/worktrees'

  [ -f "$dst/.claude/settings/config.json" ]
  [ ! -e "$dst/.claude/worktrees" ]
  ! grep -qx ".claude/worktrees" "$copy_log"
}

@test "copy_directories does not copy excluded child under nested include path" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst" copy_log="$_test_tmpdir/copy.log"
  mkdir -p "$src/vendor/bundle/cache" "$src/vendor/bundle/gems" "$dst"
  echo "skip" > "$src/vendor/bundle/cache/blob"
  echo "keep" > "$src/vendor/bundle/gems/spec"

  _fast_copy_dir() {
    printf '%s\n' "$1" >> "$copy_log"
    cp -RP "$1" "$2"
  }

  copy_directories "$src" "$dst" "vendor/bundle" $'vendor/bundle/cache'

  [ -f "$dst/vendor/bundle/gems/spec" ]
  [ ! -e "$dst/vendor/bundle/cache" ]
  ! grep -qx "vendor/bundle/cache" "$copy_log"
}
