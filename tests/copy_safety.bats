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

@test "literal directory patterns do not invoke find" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" find_log="$_test_tmpdir/find.log"
  mkdir -p "$src/build/generated" "$src/node_modules"

  find() {
    printf 'called\n' >> "$find_log"
    return 1
  }

  local resolved
  resolved=$(_resolve_directory_patterns "$src" $'build/generated\nnode_modules\nbuild/missing')

  [ "$resolved" = $'./build/generated\n./node_modules' ]
  [ ! -e "$find_log" ]
}

@test "missing basename retains recursive matching" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src"
  mkdir -p "$src/packages/a/vendor"

  local resolved
  resolved=$(_resolve_directory_patterns "$src" "vendor")

  [ "$resolved" = "./packages/a/vendor" ]
}

@test "copy_directories copies nested basename after root miss" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src/packages/a/vendor" "$dst"
  echo "nested" > "$src/packages/a/vendor/marker"

  copy_directories "$src" "$dst" "vendor" ""

  [ -f "$dst/packages/a/vendor/marker" ]
}

@test "missing basename patterns share one recursive scan" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" find_log="$_test_tmpdir/find.log"
  mkdir -p "$src/packages/a/vendor" "$src/packages/b/cache"

  find() {
    printf 'called\n' >> "$find_log"
    command find "$@"
  }

  local resolved
  resolved=$(_resolve_directory_patterns "$src" $'vendor\ncache')

  [ "$(wc -l < "$find_log" | tr -d ' ')" -eq 1 ]
  [ "$(printf '%s\n' "$resolved" | grep -c '^./packages/a/vendor$')" -eq 1 ]
  [ "$(printf '%s\n' "$resolved" | grep -c '^./packages/b/cache$')" -eq 1 ]
}

@test "missing basename glob retains recursive matching" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src"
  mkdir -p "$src/packages/a/vendor-cache"

  local resolved
  resolved=$(_resolve_directory_patterns "$src" "vendor-*")

  [ "$resolved" = "./packages/a/vendor-cache" ]
}

@test "single-star directory patterns are bounded to their explicit depth" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src"
  mkdir -p "$src/one/cache" "$src/one/deep/cache"

  local resolved
  resolved=$(_resolve_directory_patterns "$src" "*/cache")

  [ "$resolved" = "./one/cache" ]
}

@test "double-star directory patterns retain recursive matching" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src"
  mkdir -p "$src/one/cache" "$src/one/deep/cache"

  local resolved
  resolved=$(_resolve_directory_patterns "$src" "**/cache")

  [ "$(printf '%s\n' "$resolved" | grep -c '^./one/cache$')" -eq 1 ]
  [ "$(printf '%s\n' "$resolved" | grep -c '^./one/deep/cache$')" -eq 1 ]
  [ "$(printf '%s\n' "$resolved" | wc -l | tr -d ' ')" -eq 2 ]
}

@test "directory excludes never traverse copied symlinks" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst" outside="$_test_tmpdir/outside"
  mkdir -p "$src/deps/nested" "$dst" "$outside/cache"
  echo "sentinel" > "$outside/cache/keep"
  echo "remove" > "$src/deps/nested/remove"
  ln -s "$outside" "$src/deps/nested/link"

  copy_directories "$src" "$dst" deps $'deps/*/link/*/*\ndeps/nested/remove'

  [ "$(cat "$outside/cache/keep")" = sentinel ]
  [ -L "$dst/deps/nested/link" ]
  [ ! -e "$dst/deps/nested/remove" ]
}

@test "directory excludes reject symlinks in the exclusion root" {
  _test_tmpdir=$(mktemp -d)
  local dest="$_test_tmpdir/dest" outside="$_test_tmpdir/outside"
  mkdir -p "$dest" "$outside/deps"
  echo "sentinel" > "$outside/deps/keep"
  ln -s "$outside" "$dest/vendor"
  ln -s "$outside/deps" "$dest/deps"

  _apply_directory_excludes "$dest" vendor/deps 'vendor/deps/*'
  _apply_directory_excludes "$dest" deps 'deps/*'

  [ "$(cat "$outside/deps/keep")" = sentinel ]
}

@test "directory excludes can unlink leaf symlinks including dangling links" {
  _test_tmpdir=$(mktemp -d)
  local dest="$_test_tmpdir/dest" outside="$_test_tmpdir/outside"
  mkdir -p "$dest/deps" "$outside"
  echo "sentinel" > "$outside/keep"
  ln -s "$outside" "$dest/deps/link"
  ln -s "$outside/missing" "$dest/deps/dangling"

  _apply_directory_excludes "$dest" deps $'deps/link/\ndeps/dangling'

  [ ! -L "$dest/deps/link" ]
  [ ! -L "$dest/deps/dangling" ]
  [ "$(cat "$outside/keep")" = sentinel ]
}

@test "directory excludes reject glob spellings of parent traversal and metadata" {
  _test_tmpdir=$(mktemp -d)
  local dest="$_test_tmpdir/dest"
  mkdir -p "$dest/deps/.git" "$dest/sibling"
  echo "metadata" > "$dest/deps/.git/config"
  echo "sentinel" > "$dest/sibling/keep"

  _apply_directory_excludes "$dest" deps $'deps/[.][.]/*\ndeps/[.]git/*\ndeps/./*'

  [ "$(cat "$dest/sibling/keep")" = sentinel ]
  [ "$(cat "$dest/deps/.git/config")" = metadata ]
}

@test "directory excludes preserve spaces and shell options" {
  _test_tmpdir=$(mktemp -d)
  local dest="$_test_tmpdir/dest"
  mkdir -p "$dest/deps/cache space/remove" "$dest/deps/cache space/keep"
  local options_before
  options_before=$(shopt -p nullglob dotglob globstar 2>/dev/null || true)

  _apply_directory_excludes "$dest" deps 'deps/cache space/remove'

  [ ! -e "$dest/deps/cache space/remove" ]
  [ -d "$dest/deps/cache space/keep" ]
  [ "$(shopt -p nullglob dotglob globstar 2>/dev/null || true)" = "$options_before" ]
}

@test "broad includes never overwrite worktree Git pointers or nested metadata" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src/nested/.git" "$dst"
  echo source > "$src/.git"
  echo secret > "$src/nested/.git/config"
  echo destination > "$dst/.git"
  copy_patterns "$src" "$dst" '*' ''
  copy_directories "$src" "$dst" nested ''
  [ "$(cat "$dst/.git")" = destination ]
  [ ! -e "$dst/nested/.git" ]
}

@test "expanded traversal cannot copy outside either root" {
  _test_tmpdir=$(mktemp -d)
  mkdir -p "$_test_tmpdir/src" "$_test_tmpdir/dst"
  echo secret > "$_test_tmpdir/victim"
  cd "$_test_tmpdir/src"
  ! _copy_pattern_file '../victim' "$_test_tmpdir/dst" '' true false
  ! _copy_pattern_file '././../victim' "$_test_tmpdir/dst" '' true false
  [ "$(cat "$_test_tmpdir/victim")" = secret ]
}

@test "file copies reject source links and destination leaf and ancestor links" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst" outside="$_test_tmpdir/outside"
  mkdir -p "$src/vendor" "$dst" "$outside"
  echo private > "$outside/secret"
  echo replacement > "$src/vendor/secret"
  ln -s "$outside/secret" "$src/leak"
  ln -s "$outside/secret" "$dst/leaf"
  ln -s "$outside" "$dst/vendor"
  echo replacement > "$src/leaf"
  copy_patterns "$src" "$dst" $'leak\nleaf\nvendor/*' ''
  [ ! -e "$dst/leak" ]
  [ "$(cat "$outside/secret")" = private ]
}

@test "directory copies reject destination links at every depth" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst" outside="$_test_tmpdir/outside"
  mkdir -p "$src/vendor/cache" "$dst/vendor" "$outside"
  echo private > "$outside/secret"
  echo replacement > "$src/vendor/cache/secret"
  ln -s "$outside" "$dst/vendor/cache"
  copy_directories "$src" "$dst" vendor ''
  [ "$(cat "$outside/secret")" = private ]
}

@test "newline discovery never reconstructs a parent traversal record" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src/"$'safe\n..' "$dst"
  echo private > "$_test_tmpdir/secret"
  copy_directories "$src" "$dst" '*' ''
  [ ! -e "$dst/secret" ]
  cd "$src"
  local count
  echo value > "$src/"$'safe\n..'"/file"
  count=$(_expand_and_copy_pattern '**/*' "$dst" '' true false 0)
  [ "$count" -eq 0 ]
}

@test "directory merge preserves destination-only files and hard-linked external data" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src/cache" "$dst/cache"
  echo private > "$_test_tmpdir/secret"
  ln "$_test_tmpdir/secret" "$dst/cache/value"
  echo replacement > "$src/cache/value"
  echo keep > "$dst/cache/keep"
  copy_directories "$src" "$dst" cache ''
  [ "$(cat "$dst/cache/keep")" = keep ]
  [ "$(cat "$_test_tmpdir/secret")" = private ]
  [ "$(cat "$dst/cache/value")" = replacement ]
}

@test "failed clone fallback only removes its own staging output" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src/cache" "$dst"
  echo value > "$src/cache/file"
  _fast_copy_os=darwin
  cp() {
    if [ "$1" = -cRP ]; then
      mkdir -p "$4/cache"
      echo partial > "$4/cache/partial"
      return 1
    fi
    command cp "$@"
  }
  _fast_copy_dir "$src/cache" "$dst/"
  [ "$(cat "$dst/cache/file")" = value ]
  [ ! -e "$dst/cache/partial" ]
  [ "$(find "$dst" -name '.gtr-copy.*' | wc -l | tr -d ' ')" -eq 0 ]
}

@test "staged directory merges preserve executable file permissions" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src/tools" "$dst/tools"
  printf '#!/bin/sh\necho executable\n' > "$src/tools/run"
  chmod +x "$src/tools/run"
  echo unrelated > "$dst/tools/existing"
  _fast_copy_dir "$src/tools" "$dst/"
  [ -x "$dst/tools/run" ]
  [ "$("$dst/tools/run")" = executable ]
}

@test "staged file copies respect a restrictive umask" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src" "$dst"
  echo secret > "$src/.env"
  chmod 644 "$src/.env"
  (umask 077; copy_patterns "$src" "$dst" .env '')
  local mode
  mode=$(stat -c '%a' "$dst/.env" 2>/dev/null) || mode=$(stat -f '%Lp' "$dst/.env")
  [ "$mode" = 600 ]
}

@test "staged replacements retain restrictive existing destination permissions" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src" "$dst"
  echo secret > "$src/.env"
  chmod 644 "$src/.env"
  echo old > "$dst/.env"
  chmod 600 "$dst/.env"
  (umask 022; copy_patterns "$src" "$dst" .env '')
  local mode
  mode=$(stat -c '%a' "$dst/.env" 2>/dev/null) || mode=$(stat -f '%Lp' "$dst/.env")
  [ "$mode" = 600 ]
  [ "$(cat "$dst/.env")" = secret ]
}

@test "preserved directory symlinks never chmod their external referents" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst" outside="$_test_tmpdir/secret"
  mkdir -p "$src/cache" "$dst/cache"
  echo private > "$outside"
  chmod 600 "$outside"
  ln -s "$outside" "$src/cache/link"
  echo old > "$dst/cache/link"
  chmod 644 "$dst/cache/link"
  copy_directories "$src" "$dst" cache ''
  [ -L "$dst/cache/link" ]
  local mode
  mode=$(stat -c '%a' "$outside" 2>/dev/null) || mode=$(stat -f '%Lp' "$outside")
  [ "$mode" = 600 ]
  [ "$(cat "$outside")" = private ]
}

@test "copy guards reject case variants of Git metadata on every platform" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src/nested/.GiT" "$dst"
  echo source > "$src/.GIT"
  echo metadata > "$src/nested/.GiT/config"
  echo destination > "$dst/.git"
  copy_patterns "$src" "$dst" '.GIT' ''
  copy_directories "$src" "$dst" nested ''
  [ "$(cat "$dst/.git")" = destination ]
  [ ! -e "$dst/.GIT" ] || [ "$(cat "$dst/.GIT")" = destination ]
  [ ! -e "$dst/nested/.GiT" ]
  mkdir -p "$dst/nested/.GiT"
  echo keep > "$dst/nested/.GiT/config"
  _apply_directory_excludes "$dst" nested 'nested/.GiT'
  [ "$(cat "$dst/nested/.GiT/config")" = keep ]
}

@test "directory staging is rejected if Git metadata removal fails" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst" mock_bin="$_test_tmpdir/bin"
  mkdir -p "$src/cache/.git" "$dst" "$mock_bin"
  echo metadata > "$src/cache/.git/config"
  cat > "$mock_bin/rm" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in */.git) exit 1 ;; esac
done
exec /bin/rm "$@"
SH
  chmod +x "$mock_bin/rm"
  PATH="$mock_bin:$PATH" run _fast_copy_dir "$src/cache" "$dst/"
  [ "$status" -ne 0 ]
  [ ! -e "$dst/cache" ]
  [ "$(find "$dst" -name '.gtr-copy.*' | wc -l | tr -d ' ')" -eq 0 ]
}

@test "directory staging is rejected when metadata verification cannot scan it" {
  _test_tmpdir=$(mktemp -d)
  local src="$_test_tmpdir/src" dst="$_test_tmpdir/dst"
  mkdir -p "$src/cache" "$dst"
  echo value > "$src/cache/file"
  find() {
    case "$*" in *'-print -quit'*) return 1 ;; esac
    command find "$@"
  }
  run _fast_copy_dir "$src/cache" "$dst/"
  [ "$status" -ne 0 ]
  [ ! -e "$dst/cache" ]
}
