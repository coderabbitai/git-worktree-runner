#!/usr/bin/env bats
# Integration tests for cmd_create in lib/commands/create.sh

load test_helper

setup() {
  setup_integration_repo
  export XDG_CONFIG_HOME="$BATS_TMPDIR/gtr-create-config-$$"
  source_gtr_commands
}

teardown() {
  rm -rf "$XDG_CONFIG_HOME"
  teardown_integration_repo
}

_cmd_create_capture_stdout() {
  local stdout_file="$1"
  shift
  cmd_create "$@" > "$stdout_file"
}

# Note: --from HEAD is needed because test repos have no origin remote,
# so resolve_default_branch can't detect a default branch.

@test "cmd_create creates worktree with basic args" {
  cmd_create new-feature --from HEAD --no-fetch --yes
  [ -d "$TEST_WORKTREES_DIR/new-feature" ]
}

@test "cmd_create accepts an untrusted folder prefix with sanitized branch and custom names" {
  git config -f .gtrconfig worktrees.prefix dev-
  [ ! -d "$_GTR_TRUST_DIR" ]

  run "$PROJECT_ROOT/bin/gtr" new feature/auth --name backend --from HEAD --no-fetch --no-copy --no-hooks --yes
  [ "$status" -eq 0 ]
  [ -f "$TEST_WORKTREES_DIR/dev-feature-auth-backend/.git" ]

  run "$PROJECT_ROOT/bin/gtr" new review --folder chosen --from HEAD --no-fetch --no-copy --no-hooks --yes
  [ "$status" -eq 0 ]
  [ -f "$TEST_WORKTREES_DIR/dev-chosen/.git" ]
  [ ! -d "$_GTR_TRUST_DIR" ]
}

@test "cmd_create rejects traversal prefixes from shared local global and environment config" {
  local source base_dir="$TEST_REPO/prefix-fixture/trees"
  mkdir -p "$TEST_REPO/prefix-fixture"
  git config gtr.worktrees.dir "$base_dir"
  export GIT_CONFIG_GLOBAL="$TEST_REPO/prefix-global-config"
  for source in shared local global environment; do
    case "$source" in
      shared)
        git config -f .gtrconfig worktrees.prefix ../planted-
        git add .gtrconfig
        git commit -m "shared prefix" --quiet
        ;;
      local) git config gtr.worktrees.prefix ../planted- ;;
      global) git config --global gtr.worktrees.prefix ../planted- ;;
      environment) export GTR_WORKTREES_PREFIX=../planted- ;;
    esac

    run "$PROJECT_ROOT/bin/gtr" new rejected-prefix --from HEAD --no-fetch --no-copy --no-hooks --yes
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid gtr.worktrees.prefix"* ]]
    [ ! -e "$base_dir" ]
    [ ! -e "$TEST_REPO/prefix-fixture/planted-rejected-prefix" ]
    ! git show-ref --verify --quiet refs/heads/rejected-prefix
    [ ! -d "$_GTR_TRUST_DIR" ]

    case "$source" in
      shared) git config -f .gtrconfig --unset worktrees.prefix ;;
      local) git config --unset gtr.worktrees.prefix ;;
      global) git config --global --unset gtr.worktrees.prefix ;;
      environment) unset GTR_WORKTREES_PREFIX ;;
    esac
  done
}

@test "cmd_create validates the effective prefix after config precedence" {
  git config -f .gtrconfig worktrees.prefix ../planted-
  git config gtr.worktrees.prefix dev-

  run "$PROJECT_ROOT/bin/gtr" new safe-override --from HEAD --no-fetch --no-copy --no-hooks --yes

  [ "$status" -eq 0 ]
  [ -f "$TEST_WORKTREES_DIR/dev-safe-override/.git" ]
}

@test "cmd_create rejects invalid prefixes without emitting porcelain records" {
  git config gtr.worktrees.dir "$TEST_REPO/prefix-fixture/trees"
  git config gtr.worktrees.prefix '../planted-'
  local stdout_file="$TEST_REPO/prefix-stdout" stderr_file="$TEST_REPO/prefix-stderr"

  run bash -c '"$1" new rejected-prefix --from HEAD --no-fetch --porcelain >"$2" 2>"$3"' \
    _ "$PROJECT_ROOT/bin/gtr" "$stdout_file" "$stderr_file"

  [ "$status" -eq 1 ]
  [ ! -s "$stdout_file" ]
  grep -q "Invalid gtr.worktrees.prefix" "$stderr_file"
  ! git show-ref --verify --quiet refs/heads/rejected-prefix
}

@test "cmd_create treats untrusted defaults.remote as a fetch operand" {
  # Every remote is local; --all must not cause an unrelated remote to be fetched.
  git remote add origin "$TEST_REPO"
  git remote add unrelated "$TEST_REPO"
  git config -f .gtrconfig defaults.remote --all
  git add .gtrconfig
  git commit -m "shared remote default" --quiet
  [ ! -d "$_GTR_TRUST_DIR" ]

  run "$PROJECT_ROOT/bin/gtr" new remote-operand --from HEAD --no-copy --no-hooks --yes

  [ "$status" -eq 0 ]
  [ -d "$TEST_WORKTREES_DIR/remote-operand" ]
  [[ "$output" == *"Could not fetch from --all"* ]]
  run git for-each-ref --format='%(refname)' refs/remotes/
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "cmd_create fetches the configured remote from untrusted defaults.remote" {
  git remote add upstream "$TEST_REPO"
  git branch remote-source HEAD
  git config -f .gtrconfig defaults.remote upstream

  run "$PROJECT_ROOT/bin/gtr" new normal-remote --from HEAD --no-copy --no-hooks --yes

  [ "$status" -eq 0 ]
  [ -d "$TEST_WORKTREES_DIR/normal-remote" ]
  [ "$(git rev-parse refs/remotes/upstream/remote-source)" = "$(git rev-parse HEAD)" ]
}

@test "_create_print_porcelain escapes record values" {
  local result expected
  result=$(_create_print_porcelain $'/tmp/a\tb\nc\\d' $'feature/a\tb' partial)
  expected=$'path\t/tmp/a\\tb\\nc\\\\d\nbranch\tfeature/a\\tb\nhook_status\tpartial'
  [ "$result" = "$expected" ]
}

@test "cmd_create --porcelain emits only stable records and implies --yes" {
  local stderr_file="$BATS_TMPDIR/create-porcelain-stderr-$$"
  local result expected_path
  result=$(cmd_create machine-feature --from HEAD --no-fetch --porcelain 2>"$stderr_file")
  expected_path=$(canonicalize_path "$TEST_WORKTREES_DIR/machine-feature")

  [ "$result" = $'path\t'"$expected_path"$'\nbranch\tmachine-feature\nhook_status\tnone' ]
  [ -d "$TEST_WORKTREES_DIR/machine-feature" ]
  grep -q "Worktree created" "$stderr_file"
}

@test "cmd_create --porcelain keeps hook stdout off the record stream" {
  local stderr_file="$BATS_TMPDIR/create-hook-stderr-$$"
  local result expected_path
  git config --add gtr.hook.postCreate "echo hook-noise"

  result=$(cmd_create machine-hook --from HEAD --no-fetch --porcelain 2>"$stderr_file")
  expected_path=$(canonicalize_path "$TEST_WORKTREES_DIR/machine-hook")

  [ "$result" = $'path\t'"$expected_path"$'\nbranch\tmachine-hook\nhook_status\tran' ]
  grep -q "hook-noise" "$stderr_file"
}

@test "cmd_create --porcelain reports untrusted hooks as skipped" {
  local stderr_file="$BATS_TMPDIR/create-untrusted-stderr-$$"
  local result expected_path
  git config -f "$TEST_REPO/.gtrconfig" --add hooks.postCreate "touch should-not-run"

  result=$(cmd_create machine-untrusted --from HEAD --no-fetch --porcelain 2>"$stderr_file")
  expected_path=$(canonicalize_path "$TEST_WORKTREES_DIR/machine-untrusted")

  [ "$result" = $'path\t'"$expected_path"$'\nbranch\tmachine-untrusted\nhook_status\tskipped-untrusted' ]
  [ ! -e "$TEST_WORKTREES_DIR/machine-untrusted/should-not-run" ]
  grep -q "Untrusted .gtrconfig hooks" "$stderr_file"
}

@test "cmd_create --porcelain reports disabled hooks with --no-hooks" {
  local result expected_path
  git config --add gtr.hook.postCreate "touch should-not-run"

  result=$(cmd_create machine-no-hooks --from HEAD --no-fetch --no-hooks --porcelain 2>/dev/null)
  expected_path=$(canonicalize_path "$TEST_WORKTREES_DIR/machine-no-hooks")

  [ "$result" = $'path\t'"$expected_path"$'\nbranch\tmachine-no-hooks\nhook_status\tdisabled' ]
  [ ! -e "$TEST_WORKTREES_DIR/machine-no-hooks/should-not-run" ]
}

@test "cmd_create rejects interactive launches in porcelain mode" {
  run cmd_create machine-editor --from HEAD --no-fetch --porcelain --editor
  [ "$status" -eq 1 ]
  [ ! -d "$TEST_WORKTREES_DIR/machine-editor" ]
}

@test "cmd_create --porcelain does not emit success records when a hook fails" {
  local stdout_file="$BATS_TMPDIR/create-failed-stdout-$$"
  git config --add gtr.hook.postCreate "exit 7"

  run _cmd_create_capture_stdout "$stdout_file" machine-failed --from HEAD --no-fetch --porcelain

  [ "$status" -eq 1 ]
  [ ! -s "$stdout_file" ]
}

@test "cmd_create stops before hooks when a directory publication races with a symlink" {
  mkdir -p "$TEST_REPO/deps" "$TEST_REPO/outside"
  printf 'echo expected > hook-marker\n' > "$TEST_REPO/deps/tool"
  printf 'echo redirected > hook-marker\n' > "$TEST_REPO/outside/tool"
  git config --add gtr.copy.includeDirs deps
  git config --add gtr.hook.postCreate 'sh deps/tool'
  local race_worktree="$TEST_WORKTREES_DIR/copy-race"
  local stdout_file="$TEST_REPO/create-stdout"
  mv() {
    local last
    for last in "$@"; do :; done
    if [ "$last" = "$race_worktree/deps" ]; then
      ln -s "$TEST_REPO/outside" "$race_worktree/deps"
    fi
    command mv "$@"
  }

  run _cmd_create_capture_stdout "$stdout_file" copy-race --from HEAD --no-fetch --porcelain

  [ "$status" -ne 0 ]
  [ -L "$race_worktree/deps" ]
  [ ! -e "$race_worktree/hook-marker" ]
  [ ! -e "$TEST_REPO/outside/deps" ]
  [ ! -s "$stdout_file" ]
  [[ "$output" == *"copying failed"* ]]
}

@test "new CLI stops after a file copy failure without hooks or porcelain success records" {
  mkdir -p "$TEST_REPO/config"
  echo tracked > "$TEST_REPO/config/keep"
  git add config/keep
  git commit -m "directory at copy destination" --quiet
  # The source worktree has a file where the new checkout will have a directory.
  rm -rf "$TEST_REPO/config"
  echo local > "$TEST_REPO/config"
  git config gtr.copy.include config
  git config gtr.hook.postCreate 'touch hook-marker'
  local stdout_file="$BATS_TEST_TMPDIR/stdout" stderr_file="$BATS_TEST_TMPDIR/stderr"

  run bash -c '"$1" new copy-failed --from HEAD --no-fetch --porcelain >"$2" 2>"$3"' \
    _ "$PROJECT_ROOT/bin/gtr" "$stdout_file" "$stderr_file"

  [ "$status" -eq 1 ]
  [ -f "$TEST_WORKTREES_DIR/copy-failed/config/keep" ]
  [ ! -e "$TEST_WORKTREES_DIR/copy-failed/hook-marker" ]
  [ ! -s "$stdout_file" ]
  grep -q 'copying failed' "$stderr_file"
  ! grep -q 'Worktree created:' "$stderr_file"
}

@test "new CLI copies included files, skips exclusions, and reports porcelain success" {
  echo value > "$TEST_REPO/keep.txt"
  echo excluded > "$TEST_REPO/skip.txt"
  git config gtr.copy.include '*.txt'
  git config gtr.copy.exclude skip.txt
  git config gtr.hook.postCreate 'cat keep.txt >> hook-marker'
  local stdout_file="$BATS_TEST_TMPDIR/stdout" stderr_file="$BATS_TEST_TMPDIR/stderr"

  run bash -c '"$1" new copy-success --from HEAD --no-fetch --porcelain >"$2" 2>"$3"' \
    _ "$PROJECT_ROOT/bin/gtr" "$stdout_file" "$stderr_file"

  [ "$status" -eq 0 ]
  local expected_path
  expected_path=$(canonicalize_path "$TEST_WORKTREES_DIR/copy-success")
  [ "$(cat "$stdout_file")" = $'path\t'"$expected_path"$'\nbranch\tcopy-success\nhook_status\tran' ]
  [ "$(cat "$expected_path/keep.txt")" = value ]
  [ "$(cat "$expected_path/hook-marker")" = value ]
  [ ! -e "$expected_path/skip.txt" ]
}

@test "cmd_create runs a copied tool once after successful directory publication" {
  mkdir -p "$TEST_REPO/deps"
  printf 'echo expected >> hook-marker\n' > "$TEST_REPO/deps/tool"
  git config --add gtr.copy.includeDirs deps
  git config --add gtr.hook.postCreate 'sh deps/tool'

  run cmd_create copy-success --from HEAD --no-fetch --porcelain

  [ "$status" -eq 0 ]
  [ ! -L "$TEST_WORKTREES_DIR/copy-success/deps" ]
  [ "$(cat "$TEST_WORKTREES_DIR/copy-success/hook-marker")" = expected ]
  [[ "$output" == *$'hook_status\tran'* ]]
}

@test "cmd_create creates worktree with --track none" {
  cmd_create track-none --from HEAD --track none --no-fetch --yes
  [ -d "$TEST_WORKTREES_DIR/track-none" ]
}

@test "cmd_create --remote uses selected remote default branch" {
  local old_sha expected_sha actual_sha
  old_sha=$(git rev-parse HEAD)
  git update-ref refs/remotes/origin/main "$old_sha"

  git commit --allow-empty -m "upstream main" --quiet
  expected_sha=$(git rev-parse HEAD)
  git update-ref refs/remotes/upstream/main "$expected_sha"

  cmd_create remote-default --remote upstream --track none --no-fetch --yes

  actual_sha=$(git -C "$TEST_WORKTREES_DIR/remote-default" rev-parse HEAD)
  [ "$actual_sha" = "$expected_sha" ]
}

@test "cmd_create creates worktree with --name suffix" {
  cmd_create named-branch --from HEAD --name backend --no-fetch --yes
  [ -d "$TEST_WORKTREES_DIR/named-branch-backend" ]
}

@test "cmd_create creates worktree with --folder override" {
  cmd_create folder-branch --from HEAD --folder my-custom --no-fetch --yes
  [ -d "$TEST_WORKTREES_DIR/my-custom" ]
}

@test "cmd_create rejects --folder + --name together" {
  run cmd_create test --folder a --name b --no-fetch --yes
  [ "$status" -eq 1 ]
}

@test "cmd_create rejects --force without --name or --folder" {
  run cmd_create test --force --no-fetch --yes
  [ "$status" -eq 1 ]
}

@test "cmd_create --no-copy skips file copying" {
  git config --add gtr.copy.include ".env"
  echo "secret" > "$TEST_REPO/.env"
  cmd_create no-copy-test --from HEAD --no-copy --no-fetch --yes
  [ ! -f "$TEST_WORKTREES_DIR/no-copy-test/.env" ]
}

@test "new CLI applies shared globstar exclusions to root and nested files" {
  mkdir -p "$TEST_REPO/data"
  echo "excluded root fixture" > "$TEST_REPO/.env.production"
  echo "excluded nested fixture" > "$TEST_REPO/data/.env.production"
  echo "included fixture" > "$TEST_REPO/.env.example"
  git config -f "$TEST_REPO/.gtrconfig" --add copy.include "**/.env.*"
  git config -f "$TEST_REPO/.gtrconfig" --add copy.exclude "**/.env.production"

  run "$PROJECT_ROOT/bin/gtr" new excluded-copy --from HEAD --no-fetch --no-hooks --yes
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_WORKTREES_DIR/excluded-copy/.env.production" ]
  [ ! -e "$TEST_WORKTREES_DIR/excluded-copy/data/.env.production" ]
  [ "$(cat "$TEST_WORKTREES_DIR/excluded-copy/.env.example")" = "included fixture" ]
}

@test "cmd_create --no-hooks skips post-create hooks" {
  git config --add gtr.hook.postCreate "touch hook-ran"
  cmd_create no-hook-test --from HEAD --no-hooks --no-fetch --yes
  [ ! -f "$TEST_WORKTREES_DIR/no-hook-test/hook-ran" ]
}

@test "cmd_create runs post-create hooks when enabled" {
  git config --add gtr.hook.postCreate 'touch "$WORKTREE_PATH/hook-ran"'
  cmd_create hook-test --from HEAD --no-fetch --yes
  [ -f "$TEST_WORKTREES_DIR/hook-test/hook-ran" ]
}

@test "cmd_create sanitizes slashed branch name for folder" {
  cmd_create feature/deep --from HEAD --no-fetch --yes
  [ -d "$TEST_WORKTREES_DIR/feature-deep" ]
}

@test "cmd_create confines untrusted config exclusions around committed symlinks" {
  # Both the repository and the external sentinel live in disposable fixtures.
  local outside="$TEST_WORKTREES_DIR/external-fixture"
  mkdir -p "$outside/cache" "$TEST_REPO/deps/nested"
  echo "sentinel" > "$outside/cache/keep"
  echo "remove" > "$TEST_REPO/deps/nested/remove"
  ln -s "$outside" "$TEST_REPO/deps/nested/link"
  git config -f "$TEST_REPO/.gtrconfig" --add copy.includeDirs deps
  git config -f "$TEST_REPO/.gtrconfig" --add copy.excludeDirs 'deps/*/link/*/*'
  git config -f "$TEST_REPO/.gtrconfig" --add copy.excludeDirs 'deps/nested/remove'
  git add .gtrconfig deps
  git commit -m "fixture copy configuration and symlink" --quiet

  cmd_create confined-copy --from HEAD --no-fetch --yes --no-hooks

  [ "$(cat "$outside/cache/keep")" = sentinel ]
  [ -L "$TEST_WORKTREES_DIR/confined-copy/deps/nested/link" ]
  [ ! -e "$TEST_WORKTREES_DIR/confined-copy/deps/nested/remove" ]
}

@test "cmd_create normalizes trailing-slash directory includes from shared config" {
  mkdir -p "$TEST_REPO/vendor/cache"
  echo replacement > "$TEST_REPO/vendor/marker"
  echo excluded > "$TEST_REPO/vendor/cache/marker"
  echo sentinel > "$TEST_REPO/marker"
  echo vendor/ > "$TEST_REPO/.gitignore"
  git config -f "$TEST_REPO/.gtrconfig" copy.includeDirs vendor///
  git config -f "$TEST_REPO/.gtrconfig" copy.excludeDirs vendor/cache/
  git add .gtrconfig .gitignore marker
  git commit -m "fixture directory copy configuration" --quiet

  run "$PROJECT_ROOT/bin/gtr" new normalized-copy --from HEAD --no-fetch --yes --no-hooks

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_WORKTREES_DIR/normalized-copy/marker")" = sentinel ]
  [ "$(cat "$TEST_WORKTREES_DIR/normalized-copy/vendor/marker")" = replacement ]
  [ ! -e "$TEST_WORKTREES_DIR/normalized-copy/vendor/cache" ]
  [ ! -e "$TEST_WORKTREES_DIR/normalized-copy/cache" ]
}

@test "cmd_create applies file exclusions inside ignored includeDirs" {
  mkdir -p "$TEST_REPO/vendor/sub" "$TEST_REPO/vendor/cache"
  echo fixture > "$TEST_REPO/vendor/root.pem"
  echo fixture > "$TEST_REPO/vendor/sub/nested.pem"
  echo keep > "$TEST_REPO/vendor/sub/keep.txt"
  echo excluded > "$TEST_REPO/vendor/cache/marker"
  echo vendor/ > "$TEST_REPO/.gitignore"
  git config -f "$TEST_REPO/.gtrconfig" copy.exclude '*.pem'
  git config -f "$TEST_REPO/.gtrconfig" copy.excludeDirs vendor/cache/
  git add .gitignore .gtrconfig
  git commit -m "fixture copy exclusions" --quiet
  git check-ignore vendor/root.pem vendor/sub/nested.pem
  [ -z "$(git ls-files vendor)" ]

  # File-pattern copying is the control; both paths must honor copy.exclude.
  local mode
  for mode in files directories; do
    if [ "$mode" = files ]; then
      git config gtr.copy.include 'vendor/**/*'
    else
      git config --unset gtr.copy.include
      git config gtr.copy.includeDirs vendor
    fi
    run "$PROJECT_ROOT/bin/gtr" new "$mode" --from HEAD --no-fetch --no-hooks --porcelain
    [ "$status" -eq 0 ]
    [ "$(cat "$TEST_WORKTREES_DIR/$mode/vendor/sub/keep.txt")" = keep ]
    [ ! -e "$TEST_WORKTREES_DIR/$mode/vendor/root.pem" ]
    [ ! -e "$TEST_WORKTREES_DIR/$mode/vendor/sub/nested.pem" ]
  done
  [ ! -e "$TEST_WORKTREES_DIR/directories/vendor/cache" ]
}
