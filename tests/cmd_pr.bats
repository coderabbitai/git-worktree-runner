#!/usr/bin/env bats
# Integration tests for cmd_pr in lib/commands/pr.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
  TEST_REMOTE_REPO=$(mktemp -d)
  TEST_OTHER_REMOTE_ROOT=$(mktemp -d)
  git -C "$TEST_REMOTE_REPO" init --bare --quiet
  git remote add origin "$TEST_REMOTE_REPO"
  git push origin HEAD:refs/heads/main --quiet
  git commit --allow-empty -m "pr head" --quiet
  TEST_PR_SHA=$(git rev-parse HEAD)
  export TEST_PR_SHA TEST_WORKTREES_DIR
  git push origin HEAD:refs/pull/123/head --quiet
  TEST_MOCK_BIN=$(mktemp -d)
  cat > "$TEST_MOCK_BIN/gh" <<'SCRIPT'
#!/usr/bin/env bash
printf '123\tfeature/from-pr\tocto\texample\thttps://github.com/base/example/pull/123\ttrue\ttrue\n'
SCRIPT
  chmod +x "$TEST_MOCK_BIN/gh"
  export PATH="$TEST_MOCK_BIN:$PATH"
}

teardown() {
  teardown_integration_repo
  rm -rf "$TEST_REMOTE_REPO" "$TEST_OTHER_REMOTE_ROOT" "$TEST_MOCK_BIN"
}

# Interleave real fetches in the invoking worktree, or fail after writing the
# PR ref, before cmd_pr can inspect its result. No sleeps or GitHub access.
interleave_pr_fetch() {
  export TEST_REAL_GIT TEST_PR_FETCH_LOG
  TEST_REAL_GIT=$(command -v git)
  TEST_PR_FETCH_LOG="$TEST_MOCK_BIN/pr-fetch.log"
  cat > "$TEST_MOCK_BIN/git" <<'SCRIPT'
#!/usr/bin/env bash
if [ "${TEST_PR_FETCH_ACTION:-}" = resolve-failure ] && [ "$1" = rev-parse ]; then
  case "${3:-}" in refs/gtr/pr/*) exit 1 ;; esac
fi
if [ "$1" = fetch ]; then
  for arg in "$@"; do
    case "$arg" in
      refs/pull/*/head|refs/pull/*/head:*)
        "$TEST_REAL_GIT" "$@" || exit $?
        printf '%s\n' "$arg" >> "$TEST_PR_FETCH_LOG"
        case "${TEST_PR_FETCH_ACTION:-fetch}" in
          fetch) "$TEST_REAL_GIT" fetch -- origin main || exit $? ;;
          fetch-failure) exit 1 ;;
          nested)
            TEST_PR_FETCH_ACTION=none TEST_GH_PR_NUMBER=456 \
              "$GTR_DIR/bin/gtr" pr 456 --remote origin --branch nested-pr \
              --no-copy --no-hooks --yes >&2 || exit $?
            # The inner invocation must not remove the outer one's live ref.
            "$TEST_REAL_GIT" rev-parse --verify "${arg#*:}" > "$TEST_PR_FETCH_LOG.outer" || exit $?
            ;;
        esac
        exit 0
        ;;
    esac
  done
fi
exec "$TEST_REAL_GIT" "$@"
SCRIPT
  chmod +x "$TEST_MOCK_BIN/git"
}

assert_pr_fetch_cleaned_up() {
  [ -z "$(git for-each-ref --format='%(refname)' refs/gtr/pr)" ]
  local reservation common_dir
  common_dir=$(git rev-parse --git-common-dir)
  for reservation in "$common_dir"/gtr-pr.*; do
    [ ! -e "$reservation" ]
  done
}

@test "pr CLI creates the PR branch despite an intervening fetch in the same worktree" {
  interleave_pr_fetch

  run "$PROJECT_ROOT/bin/gtr" pr 123 --remote origin --no-copy --no-hooks --yes

  [ "$status" -eq 0 ]
  [ "$(git rev-parse FETCH_HEAD)" = "$(git rev-parse HEAD~1)" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/feature-from-pr" rev-parse HEAD)" = "$TEST_PR_SHA" ]
  assert_pr_fetch_cleaned_up
}

@test "pr CLI accepts a matching branch despite an intervening fetch in the same worktree" {
  git branch feature/from-pr "$TEST_PR_SHA"
  interleave_pr_fetch

  run "$PROJECT_ROOT/bin/gtr" pr 123 --remote origin --no-copy --no-hooks --yes

  [ "$status" -eq 0 ]
  [ "$(git rev-parse FETCH_HEAD)" = "$(git rev-parse HEAD~1)" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/feature-from-pr" rev-parse HEAD)" = "$TEST_PR_SHA" ]
  assert_pr_fetch_cleaned_up
}

@test "pr CLI rejects a mismatching branch even when an intervening fetch matches it" {
  local original_tip
  original_tip=$(git rev-parse HEAD~1)
  git branch feature/from-pr "$original_tip"
  interleave_pr_fetch

  run "$PROJECT_ROOT/bin/gtr" pr 123 --remote origin --force --folder review --no-copy --no-hooks --yes

  [ "$status" -eq 1 ]
  [ "$(git rev-parse FETCH_HEAD)" = "$original_tip" ]
  [ "$(git rev-parse feature/from-pr)" = "$original_tip" ]
  [ ! -e "$TEST_WORKTREES_DIR/review" ]
  [[ "$output" == *"differs from pull request"* ]]
  assert_pr_fetch_cleaned_up
}

@test "pr CLI force reuses a checked out matching branch despite an intervening fetch" {
  git worktree add --quiet -b feature/from-pr "$TEST_WORKTREES_DIR/existing" "$TEST_PR_SHA"
  interleave_pr_fetch

  run "$PROJECT_ROOT/bin/gtr" pr 123 --remote origin --force --folder review --no-copy --no-hooks --yes

  [ "$status" -eq 0 ]
  [ "$(git -C "$TEST_WORKTREES_DIR/review" rev-parse HEAD)" = "$TEST_PR_SHA" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/existing" rev-parse HEAD)" = "$TEST_PR_SHA" ]
  assert_pr_fetch_cleaned_up
}

@test "pr CLI isolates the fetch identity when invoked from a linked worktree" {
  git fetch -- origin refs/pull/123/head
  git worktree add --quiet --detach "$TEST_WORKTREES_DIR/invoking" HEAD
  cd "$TEST_WORKTREES_DIR/invoking"
  interleave_pr_fetch

  run "$PROJECT_ROOT/bin/gtr" pr 123 --remote origin --no-copy --no-hooks --yes

  [ "$status" -eq 0 ]
  [ "$(git rev-parse FETCH_HEAD)" = "$(git rev-parse HEAD~1)" ]
  [ "$(git -C "$TEST_REPO" rev-parse FETCH_HEAD)" = "$TEST_PR_SHA" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/feature-from-pr" rev-parse HEAD)" = "$TEST_PR_SHA" ]
  assert_pr_fetch_cleaned_up
}

@test "cmd_pr uses the captured commit when another fetch runs just before creation" {
  eval "$(declare -f create_worktree | sed '1s/create_worktree/original_create_worktree/')"
  create_worktree() {
    git fetch -- origin main >&2 || return 1
    original_create_worktree "$@"
  }

  run cmd_pr 123 --remote origin --no-copy --no-hooks --yes

  [ "$status" -eq 0 ]
  [ "$(git rev-parse FETCH_HEAD)" = "$(git rev-parse HEAD~1)" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/feature-from-pr" rev-parse HEAD)" = "$TEST_PR_SHA" ]
  assert_pr_fetch_cleaned_up
}

@test "pr CLI isolates temporary refs across overlapping PR invocations" {
  local nested_sha outer_ref inner_ref
  nested_sha=$(git rev-parse HEAD~1)
  git push origin "$nested_sha:refs/pull/456/head" --quiet
  cat > "$TEST_MOCK_BIN/gh" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\tfeature/from-pr\tocto\texample\thttps://github.com/base/example/pull/%s\ttrue\ttrue\n' \
  "${TEST_GH_PR_NUMBER:-123}" "${TEST_GH_PR_NUMBER:-123}"
SCRIPT
  interleave_pr_fetch
  export TEST_PR_FETCH_ACTION=nested

  run "$PROJECT_ROOT/bin/gtr" pr 123 --remote origin --no-copy --no-hooks --yes

  [ "$status" -eq 0 ]
  [ "$(git -C "$TEST_WORKTREES_DIR/feature-from-pr" rev-parse HEAD)" = "$TEST_PR_SHA" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/nested-pr" rev-parse HEAD)" = "$nested_sha" ]
  [ "$(cat "$TEST_PR_FETCH_LOG.outer")" = "$TEST_PR_SHA" ]
  outer_ref=$(sed -n '1s/.*://p' "$TEST_PR_FETCH_LOG")
  inner_ref=$(sed -n '2s/.*://p' "$TEST_PR_FETCH_LOG")
  [ -n "$outer_ref" ]
  [ -n "$inner_ref" ]
  [ "$outer_ref" != "$inner_ref" ]
  assert_pr_fetch_cleaned_up
}

@test "pr CLI cleans temporary refs after fetch and commit resolution failures" {
  interleave_pr_fetch
  local mode
  for mode in fetch-failure resolve-failure; do
    export TEST_PR_FETCH_ACTION="$mode"
    # A different invocation's ref must survive our failure cleanup.
    git update-ref refs/gtr/pr/other-invocation "$TEST_PR_SHA"

    run "$PROJECT_ROOT/bin/gtr" pr 123 --remote origin --no-copy --no-hooks --yes

    [ "$status" -eq 1 ]
    [ ! -e "$TEST_WORKTREES_DIR/feature-from-pr" ]
    ! git show-ref --verify --quiet refs/heads/feature/from-pr
    [ "$(git rev-parse refs/gtr/pr/other-invocation)" = "$TEST_PR_SHA" ]
    git update-ref -d refs/gtr/pr/other-invocation
    assert_pr_fetch_cleaned_up
  done
}

@test "pr CLI cleans temporary refs when the remote PR ref is missing" {
  git --git-dir="$TEST_REMOTE_REPO" update-ref -d refs/pull/123/head

  run "$PROJECT_ROOT/bin/gtr" pr 123 --remote origin --no-copy --no-hooks --yes

  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not fetch pull request"* ]]
  assert_pr_fetch_cleaned_up
}

@test "pr CLI cleans temporary refs when worktree creation fails" {
  mkdir -p "$TEST_WORKTREES_DIR"
  printf 'keep me\n' > "$TEST_WORKTREES_DIR/feature-from-pr"

  run "$PROJECT_ROOT/bin/gtr" pr 123 --remote origin --no-copy --no-hooks --yes

  [ "$status" -eq 1 ]
  [ "$(cat "$TEST_WORKTREES_DIR/feature-from-pr")" = 'keep me' ]
  assert_pr_fetch_cleaned_up
}

@test "PR fetch cleanup preserves caller traps on success and failure" {
  run bash -c '
    set -e
    source "$1/tests/test_helper.bash"
    source_gtr_commands
    trap '\''printf "caller exit\n" >> "$2"'\'' EXIT
    trap : HUP INT TERM
    saved_traps=$(trap -p EXIT HUP INT TERM)
    _pr_fetch_commit origin 123 > "$2.oid"
    [ "$(cat "$2.oid")" = "$TEST_PR_SHA" ]
    [ "$(trap -p EXIT HUP INT TERM)" = "$saved_traps" ]
    if _pr_fetch_commit origin 999; then exit 1; fi
    [ "$(trap -p EXIT HUP INT TERM)" = "$saved_traps" ]
  ' _ "$PROJECT_ROOT" "$TEST_MOCK_BIN/exit-marker"

  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_MOCK_BIN/exit-marker")" = 'caller exit' ]
  assert_pr_fetch_cleaned_up
}

@test "cmd_pr creates worktree from GitHub pull request ref" {
  cmd_pr 123 --remote origin --no-copy --no-hooks --yes

  [ -d "$TEST_WORKTREES_DIR/feature-from-pr" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/feature-from-pr" rev-parse HEAD)" = "$TEST_PR_SHA" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/feature-from-pr" rev-parse --abbrev-ref HEAD)" = "feature/from-pr" ]
  [ "$(git config branch.feature/from-pr.remote)" = "https://github.com/octo/example.git" ]
  [ "$(git config branch.feature/from-pr.pushRemote)" = "https://github.com/octo/example.git" ]
  [ "$(git config branch.feature/from-pr.merge)" = "refs/heads/feature/from-pr" ]
}

@test "cmd_pr does not run postCreate after a directory copy fails" {
  mkdir -p "$TEST_REPO/deps"
  echo value > "$TEST_REPO/deps/file"
  git config --add gtr.copy.includeDirs deps
  git config --add gtr.hook.postCreate 'touch hook-marker'
  mv() { return 1; }

  run cmd_pr 123 --remote origin --yes

  [ "$status" -ne 0 ]
  [ -d "$TEST_WORKTREES_DIR/feature-from-pr" ]
  [ ! -e "$TEST_WORKTREES_DIR/feature-from-pr/hook-marker" ]
  [[ "$output" == *"copying failed"* ]]
}

@test "pr CLI stops before hooks and success output after a file copy fails" {
  mkdir -p "$TEST_REPO/config"
  echo tracked > "$TEST_REPO/config/keep"
  git add config/keep
  git commit -m "directory at copy destination" --quiet
  git push origin HEAD:refs/pull/123/head --quiet
  rm -rf "$TEST_REPO/config"
  echo local > "$TEST_REPO/config"
  git config gtr.copy.include config
  git config gtr.hook.postCreate 'touch hook-marker'

  run "$PROJECT_ROOT/bin/gtr" pr 123 --remote origin --yes

  [ "$status" -eq 1 ]
  [ -f "$TEST_WORKTREES_DIR/feature-from-pr/config/keep" ]
  [ ! -e "$TEST_WORKTREES_DIR/feature-from-pr/hook-marker" ]
  [[ "$output" == *"copying failed"* ]]
  [[ "$output" != *"Worktree created:"* ]]
  [[ "$output" != *"Next steps:"* ]]
}

@test "cmd_pr treats an option-shaped remote as a fetch operand" {
  # Configure the name directly because `git remote add` rejects leading dashes.
  git config remote.--all.url "$TEST_REMOTE_REPO"

  run cmd_pr 123 --remote --all --no-copy --no-hooks --yes

  [ "$status" -eq 0 ]
  [ -d "$TEST_WORKTREES_DIR/feature-from-pr" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/feature-from-pr" rev-parse HEAD)" = "$TEST_PR_SHA" ]
}

@test "cmd_pr supports custom local branch and folder" {
  cmd_pr 123 --branch review/pr-123 --folder review-123 --remote origin --no-copy --no-hooks --yes

  [ -d "$TEST_WORKTREES_DIR/review-123" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/review-123" rev-parse HEAD)" = "$TEST_PR_SHA" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/review-123" rev-parse --abbrev-ref HEAD)" = "review/pr-123" ]
  [ "$(git config branch.review/pr-123.merge)" = "refs/heads/feature/from-pr" ]
}

@test "cmd_pr fallback applies an ordinary folder prefix" {
  git config -f .gtrconfig worktrees.prefix dev-

  cmd_pr 123 --remote origin --no-copy --no-hooks --yes

  [ -f "$TEST_WORKTREES_DIR/dev-feature-from-pr/.git" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/dev-feature-from-pr" rev-parse HEAD)" = "$TEST_PR_SHA" ]
}

@test "cmd_pr rejects traversal prefixes before native checkout or fallback fetch" {
  git config gtr.worktrees.dir "$TEST_REPO/prefix-fixture/trees"
  git config -f .gtrconfig worktrees.prefix ../planted-
  export TEST_GH_LOG="$TEST_MOCK_BIN/gh.log"
  cat > "$TEST_MOCK_BIN/gh" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_GH_LOG"
if [ "$1" = "pr" ] && [ "$2" = "checkout" ] && [ "$3" = "--help" ]; then
  printf '      --worktree path\n'
elif [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  printf '123\tfeature/from-pr\tocto\texample\thttps://github.com/base/example/pull/123\ttrue\ttrue\n'
fi
SCRIPT
  local mode
  for mode in native fallback; do
    local args=()
    [ "$mode" = "fallback" ] && args=(--remote origin)

    run "$PROJECT_ROOT/bin/gtr" pr 123 "${args[@]}" --no-copy --no-hooks --yes

    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid gtr.worktrees.prefix"* ]]
    [ ! -e "$TEST_GH_LOG" ]
    [ ! -e "$TEST_REPO/prefix-fixture" ]
    [ ! -e "$TEST_REPO/.git/FETCH_HEAD" ]
    ! git show-ref --verify --quiet refs/heads/feature/from-pr
  done
}

@test "cmd_pr reuses ssh remote matching resolved PR base repository" {
  git remote add upstream git@github.com:base/example.git

  [ "$(_pr_remote_for_url https://github.com/base/example.git)" = "upstream" ]
}

@test "cmd_pr fetches through an existing SSH base remote by default" {
  git config url."$TEST_REMOTE_REPO".insteadOf git@github.com:base/example.git
  git remote add upstream git@github.com:base/example.git

  cmd_pr 123 --no-copy --no-hooks --yes

  [ -d "$TEST_WORKTREES_DIR/feature-from-pr" ]
  [ "$(git config remote.upstream.gh-resolved)" = "base" ]
  ! git remote get-url gtr-pr-123-base >/dev/null 2>&1
}

@test "cmd_pr respects gh SSH protocol and avoids unwritable fork push metadata" {
  git config url."$TEST_REMOTE_REPO".insteadOf git@github.com:base/example.git
  cat > "$TEST_MOCK_BIN/gh" <<'SCRIPT'
#!/usr/bin/env bash
if [ "$1" = "config" ]; then
  printf 'ssh\n'
elif [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  printf '123\tfeature/from-pr\tocto\texample\thttps://github.com/base/example/pull/123\tfalse\ttrue\n'
fi
SCRIPT
  chmod +x "$TEST_MOCK_BIN/gh"

  cmd_pr 123 --no-copy --no-hooks --yes

  [ "$(git config --get remote.gtr-pr-123-base.url)" = "git@github.com:base/example.git" ]
  [ "$(git config branch.feature/from-pr.remote)" = "git@github.com:base/example.git" ]
  [ "$(git config branch.feature/from-pr.merge)" = "refs/pull/123/head" ]
  ! git config --get branch.feature/from-pr.pushRemote >/dev/null 2>&1
}

@test "cmd_pr uses an existing fork remote even when maintainer edits are disabled" {
  git remote add contributor git@github.com:octo/example.git
  cat > "$TEST_MOCK_BIN/gh" <<'SCRIPT'
#!/usr/bin/env bash
if [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  printf '123\tfeature/from-pr\tocto\texample\thttps://github.com/base/example/pull/123\tfalse\ttrue\n'
fi
SCRIPT
  chmod +x "$TEST_MOCK_BIN/gh"

  cmd_pr 123 --remote origin --no-copy --no-hooks --yes

  [ "$(git config branch.feature/from-pr.remote)" = "contributor" ]
  [ "$(git config branch.feature/from-pr.pushRemote)" = "contributor" ]
  [ "$(git config branch.feature/from-pr.merge)" = "refs/heads/feature/from-pr" ]
}

@test "cmd_pr delegates worktree creation to gh when supported" {
  git config gtr.worktrees.prefix dev-
  export TEST_GH_LOG="$TEST_MOCK_BIN/gh.log"
  cat > "$TEST_MOCK_BIN/gh" <<'SCRIPT'
#!/usr/bin/env bash
if [ "$1" = "config" ]; then
  printf 'https\n'
elif [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  printf '123\tfeature/from-pr\tocto\texample\thttps://github.com/base/example/pull/123\ttrue\ttrue\n'
elif [ "$1" = "pr" ] && [ "$2" = "checkout" ] && [ "$3" = "--help" ]; then
  printf '      --worktree path\n'
elif [ "$1" = "pr" ] && [ "$2" = "checkout" ]; then
  shift 3
  worktree_path=""
  branch_name=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --worktree) worktree_path="$2"; shift 2 ;;
      --branch) branch_name="$2"; shift 2 ;;
      --repo) shift 2 ;;
      *) shift ;;
    esac
  done
  printf '%s\t%s\n' "$worktree_path" "$branch_name" > "$TEST_GH_LOG"
  git worktree add --quiet -b "$branch_name" "$worktree_path" "$TEST_PR_SHA"
fi
SCRIPT
  chmod +x "$TEST_MOCK_BIN/gh"

  cmd_pr 123 --no-copy --no-hooks --yes

  [ -d "$TEST_WORKTREES_DIR/dev-feature-from-pr" ]
  local logged_path logged_branch
  IFS=$'\t' read -r logged_path logged_branch < "$TEST_GH_LOG"
  [ "${logged_path##*/}" = "dev-feature-from-pr" ]
  [ "$logged_branch" = "feature/from-pr" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/dev-feature-from-pr" rev-parse HEAD)" = "$TEST_PR_SHA" ]
}

@test "cmd_pr fetches the resolved PR base repository by default" {
  local other_remote other_sha
  other_remote="$TEST_OTHER_REMOTE_ROOT/other.git"
  git init --bare "$other_remote" --quiet
  git commit --allow-empty -m "other pr head" --quiet
  other_sha=$(git rev-parse HEAD)
  git push "$other_remote" HEAD:refs/pull/999/head --quiet
  git push origin HEAD~1:refs/pull/999/head --quiet
  cat > "$TEST_MOCK_BIN/gh" <<SCRIPT
#!/usr/bin/env bash
printf '999\tfeature/from-other\tocto\texample\tfile://$other_remote/pull/999\tfalse\ttrue\n'
SCRIPT
  chmod +x "$TEST_MOCK_BIN/gh"

  cmd_pr 999 --branch other/pr --folder other-pr --no-copy --no-hooks --yes

  [ -d "$TEST_WORKTREES_DIR/other-pr" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/other-pr" rev-parse HEAD)" = "$other_sha" ]
  [ "$(git remote get-url gtr-pr-999-base)" = "file://$other_remote" ]
  [ "$(git config remote.gtr-pr-999-base.gh-resolved)" = "base" ]
}

mock_failed_native_checkout() {
  git config url."$TEST_REMOTE_REPO".insteadOf https://github.com/base/example.git
  cat > "$TEST_MOCK_BIN/gh" <<'SCRIPT'
#!/usr/bin/env bash
if [ "$1" = "config" ]; then
  printf 'https\n'
elif [ "$1" = "pr" ] && [ "$2" = "view" ]; then
  printf '123\tfeature/from-pr\tocto\texample\thttps://github.com/base/example/pull/123\ttrue\ttrue\n'
elif [ "$1" = "pr" ] && [ "$2" = "checkout" ] && [ "$3" = "--help" ]; then
  printf '      --worktree path\n'
elif [ "$1" = "pr" ] && [ "$2" = "checkout" ]; then
  destination="$TEST_WORKTREES_DIR/feature-from-pr"
  case "${NATIVE_CHECKOUT_FAILURE:-}" in
    directory) mkdir "$destination"; printf 'preserve me\n' > "$destination/partial" ;;
    file) printf 'preserve me\n' > "$destination" ;;
    symlink) ln -s "$destination-missing" "$destination" ;;
  esac
  printf "fatal: couldn't find remote ref refs/heads/feature/from-pr\n" >&2
  exit 1
fi
SCRIPT
}

@test "pr CLI falls back to the pull request ref when native checkout fails" {
  mock_failed_native_checkout
  interleave_pr_fetch

  run "$PROJECT_ROOT/bin/gtr" pr 123 --no-copy --no-hooks --yes

  [ "$status" -eq 0 ]
  [ "$(git -C "$TEST_WORKTREES_DIR/feature-from-pr" rev-parse HEAD)" = "$TEST_PR_SHA" ]
  [ "$(git config remote.gtr-pr-123-base.gh-resolved)" = base ]
  [[ "$output" == *"retrying with the pull request ref"* ]]
  assert_pr_fetch_cleaned_up
}

@test "pr CLI fallback preserves an existing branch at a different commit" {
  mock_failed_native_checkout
  local original_tip
  original_tip=$(git rev-parse HEAD~1)
  git branch feature/from-pr "$original_tip"

  run "$PROJECT_ROOT/bin/gtr" pr 123 --no-copy --no-hooks --yes

  [ "$status" -eq 1 ]
  [ ! -e "$TEST_WORKTREES_DIR/feature-from-pr" ]
  [ "$(git rev-parse feature/from-pr)" = "$original_tip" ]
  [[ "$output" == *"differs from pull request"* ]]
}

@test "pr CLI preserves partial native checkout destinations without falling back" {
  mock_failed_native_checkout
  local mode destination="$TEST_WORKTREES_DIR/feature-from-pr"
  for mode in directory file symlink; do
    export NATIVE_CHECKOUT_FAILURE="$mode"

    run "$PROJECT_ROOT/bin/gtr" pr 123 --no-copy --no-hooks --yes

    [ "$status" -eq 1 ]
    [ ! -e "$TEST_REPO/.git/FETCH_HEAD" ]
    case "$mode" in
      directory) [ "$(cat "$destination/partial")" = 'preserve me' ]; rm -r "$destination" ;;
      file) [ "$(cat "$destination")" = 'preserve me' ]; rm "$destination" ;;
      symlink) [ -L "$destination" ]; rm "$destination" ;;
    esac
  done
}

@test "cmd_pr preserves existing branch metadata" {
  git branch feature/from-pr "$TEST_PR_SHA"
  git config branch.feature/from-pr.remote keep-remote
  git config branch.feature/from-pr.pushRemote keep-push
  git config branch.feature/from-pr.merge refs/heads/keep

  cmd_pr 123 --remote origin --folder reused-pr --no-copy --no-hooks --yes

  [ "$(git config branch.feature/from-pr.remote)" = "keep-remote" ]
  [ "$(git config branch.feature/from-pr.pushRemote)" = "keep-push" ]
  [ "$(git config branch.feature/from-pr.merge)" = "refs/heads/keep" ]
}

@test "cmd_pr sanitizes custom name suffix" {
  cmd_pr 123 --remote origin --name "../review/path" --no-copy --no-hooks --yes

  [ -d "$TEST_WORKTREES_DIR/feature-from-pr-..-review-path" ]
}

@test "cmd_pr rejects existing local branch at a different commit" {
  git branch feature/from-pr HEAD~1

  run cmd_pr 123 --remote origin --no-copy --no-hooks --yes

  [ "$status" -eq 1 ]
  [ ! -d "$TEST_WORKTREES_DIR/feature-from-pr" ]
  [ "$(git rev-parse feature/from-pr)" != "$TEST_PR_SHA" ]
}

@test "cmd_pr rejects missing selector in non-interactive mode" {
  run cmd_pr --yes
  [ "$status" -eq 1 ]
}

@test "cmd_pr rejects force without a distinct folder" {
  run cmd_pr 123 --force --remote origin --no-copy --no-hooks --yes
  [ "$status" -eq 1 ]
}

@test "cmd_pr requires GitHub CLI" {
  local old_path no_gh_bin tool
  old_path="$PATH"
  no_gh_bin=$(mktemp -d)
  for tool in bash git basename dirname grep sed mktemp cat rm; do
    ln -s "$(command -v "$tool")" "$no_gh_bin/$tool"
  done

  PATH="$no_gh_bin" run cmd_pr 123 --remote origin --no-copy --no-hooks --yes
  PATH="$old_path"
  rm -rf "$no_gh_bin"

  [ "$status" -eq 1 ]
  [[ "$output" == *"gh is required"* ]]
}
