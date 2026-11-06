#!/usr/bin/env bats

load test_helper
load copy_discovery_helper

setup() {
  setup_integration_repo
  mkdir -p vendor pkg/vendor
  echo tracked > vendor/tracked
  git add vendor/tracked
  git commit -m 'copy destination fixture' --quiet
  echo local > vendor/local.txt
  echo local > pkg/vendor/local.txt
  echo local > root.txt
  install_copy_find_stub "$TEST_REPO/mock-bin"
  # Force the supported Bash 3.2 fallback when running tests on newer Bash too.
  shopt() {
    [ "$*" != '-s globstar' ] || return 1
    builtin shopt "$@"
  }
  export -f shopt
  export TEST_COPY_TOOLS_LOG="$TEST_REPO/tools.log"
  cat > "$TEST_REPO/mock-bin/copy-test-tool" <<'SCRIPT'
#!/usr/bin/env bash
echo launched >> "$TEST_COPY_TOOLS_LOG"
SCRIPT
  chmod +x "$TEST_REPO/mock-bin/copy-test-tool"
  git config gtr.editor.default copy-test-tool
  git config gtr.ai.default copy-test-tool
  git config gtr.hook.postCreate 'touch hook-marker'
  git config gtr.hook.postCd 'touch postcd-marker'
}

teardown() {
  teardown_integration_repo
}

# Select a real copy path, injecting failure only into that path's discovery.
# Usage: configure_discovery_failure <files|directories|merge|selective> <empty|partial>
configure_discovery_failure() {
  git config --unset-all gtr.copy.include || true
  git config --unset-all gtr.copy.includeDirs || true
  git config --unset-all gtr.copy.exclude || true
  case "$1" in
    files)
      git config gtr.copy.include '**/*.txt'
      TEST_COPY_FIND_ARGS='. -maxdepth 1 -path ./*.txt -type f -print0'
      TEST_COPY_FIND_RECORD='./root.txt'
      ;;
    directories)
      git config gtr.copy.includeDirs 'pkg/*'
      TEST_COPY_FIND_ARGS='. -maxdepth 2 -type d ( -path ./pkg/* ) -print0'
      TEST_COPY_FIND_RECORD='./pkg/vendor'
      ;;
    merge|selective)
      git config gtr.copy.includeDirs vendor
      [ "$1" != selective ] || git config gtr.copy.exclude '*.pem'
      TEST_COPY_FIND_ARGS='vendor -mindepth 1 -maxdepth 1 -print0'
      TEST_COPY_FIND_RECORD='vendor/local.txt'
      ;;
  esac
  [ "$2" != empty ] || TEST_COPY_FIND_RECORD=''
  rm -f "$TEST_COPY_FIND_HIT"
}

@test "copy CLI reports discovery failures for files directories merges and selective copies" {
  local mode partial
  git worktree add -b target "$TEST_WORKTREES_DIR/target" HEAD --quiet
  for mode in files directories merge selective; do
    for partial in empty partial; do
      configure_discovery_failure "$mode" "$partial"
      run "$PROJECT_ROOT/bin/gtr" copy --all
      [ "$status" -eq 1 ]
      [ -s "$TEST_COPY_FIND_HIT" ]
      [[ "$output" == *Failed* ]]
      [ "$(cat "$TEST_WORKTREES_DIR/target/vendor/tracked")" = tracked ]
    done
  done
}

@test "new CLI stops hooks and requested tools after discovery fails with or without partial output" {
  local mode partial branch
  for mode in files directories merge selective; do
    for partial in empty partial; do
      configure_discovery_failure "$mode" "$partial"
      branch="failed-$mode-$partial"
      run "$PROJECT_ROOT/bin/gtr" new "$branch" --from HEAD --no-fetch --yes --editor --ai
      [ "$status" -eq 1 ]
      [ -s "$TEST_COPY_FIND_HIT" ]
      [ -d "$TEST_WORKTREES_DIR/$branch" ]
      [ ! -e "$TEST_WORKTREES_DIR/$branch/hook-marker" ]
      [ ! -e "$TEST_WORKTREES_DIR/$branch/postcd-marker" ]
      [ ! -e "$TEST_COPY_TOOLS_LOG" ]
      [[ "$output" == *"copying failed"* ]]
      [[ "$output" != *"Next steps:"* ]]
    done
  done
  # Positive control: these hooks and tools really do run when discovery succeeds.
  TEST_COPY_FIND_ARGS=''
  run "$PROJECT_ROOT/bin/gtr" new success --from HEAD --no-fetch --yes --editor --ai
  [ "$status" -eq 0 ]
  [ -f "$TEST_WORKTREES_DIR/success/hook-marker" ]
  [ -f "$TEST_WORKTREES_DIR/success/postcd-marker" ]
  [ "$(wc -l < "$TEST_COPY_TOOLS_LOG" | tr -d ' ')" -eq 2 ]
}

@test "new porcelain emits no success records after partial discovery fails" {
  configure_discovery_failure directories partial
  run bash -c '"$1" new failed --from HEAD --no-fetch --porcelain >"$2" 2>"$3"' \
    _ "$PROJECT_ROOT/bin/gtr" "$TEST_REPO/stdout" "$TEST_REPO/stderr"
  [ "$status" -eq 1 ]
  [ -s "$TEST_COPY_FIND_HIT" ]
  [ ! -s "$TEST_REPO/stdout" ]
  grep -q 'copying failed' "$TEST_REPO/stderr"
  [ ! -e "$TEST_WORKTREES_DIR/failed/hook-marker" ]
}

@test "pr CLI stops hooks and requested tools after discovery fails with or without partial output" {
  local mode partial branch
  git init --bare "$TEST_REPO/remote.git" --quiet
  git remote add origin "$TEST_REPO/remote.git"
  git push origin HEAD:refs/pull/123/head --quiet
  cat > "$TEST_REPO/mock-bin/gh" <<'SCRIPT'
#!/usr/bin/env bash
printf '123\tfeature/from-pr\tocto\texample\thttps://github.com/base/example/pull/123\ttrue\ttrue\n'
SCRIPT
  chmod +x "$TEST_REPO/mock-bin/gh"
  for mode in files directories merge selective; do
    for partial in empty partial; do
      configure_discovery_failure "$mode" "$partial"
      branch="failed-$mode-$partial"
      run "$PROJECT_ROOT/bin/gtr" pr 123 --remote origin --branch "$branch" --yes --editor --ai
      [ "$status" -eq 1 ]
      [ -s "$TEST_COPY_FIND_HIT" ]
      [ -d "$TEST_WORKTREES_DIR/$branch" ]
      [ ! -e "$TEST_WORKTREES_DIR/$branch/hook-marker" ]
      [ ! -e "$TEST_WORKTREES_DIR/$branch/postcd-marker" ]
      [ ! -e "$TEST_COPY_TOOLS_LOG" ]
      [[ "$output" == *"copying failed"* ]]
      [[ "$output" != *"Worktree created:"* ]]
      [[ "$output" != *"Next steps:"* ]]
    done
  done
}
