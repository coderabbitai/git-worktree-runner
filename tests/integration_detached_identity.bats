#!/usr/bin/env bats
# Detached HEAD must never impersonate the legal branch name '(detached)'.

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
  git branch '(detached)'
  git worktree add --detach "$TEST_WORKTREES_DIR/loose" HEAD >/dev/null
  ORIGINAL_REFS=$(git show-ref --heads)
  ORIGINAL_TIP=$(git rev-parse HEAD)
}

teardown() {
  teardown_integration_repo
}

attach_named_branch() {
  git worktree add "$TEST_WORKTREES_DIR/real-branch" '(detached)' >/dev/null
}

assert_loose_detached() {
  [ -f "$TEST_WORKTREES_DIR/loose/.git" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/loose" rev-parse HEAD)" = "$ORIGINAL_TIP" ]
  ! git -C "$TEST_WORKTREES_DIR/loose" symbolic-ref --quiet HEAD
  git worktree list --porcelain | grep -Fx "worktree $TEST_WORKTREES_DIR/loose"
}

@test "removing detached worktree with branch deletion preserves every real ref" {
  git config gtr.hook.preRemove 'printf "pre:<%s>\n" "$BRANCH" >> "$REPO_ROOT/hook-branches"'
  git config gtr.hook.postRemove 'printf "post:<%s>\n" "$BRANCH" >> "$REPO_ROOT/hook-branches"'

  run "$PROJECT_ROOT/bin/gtr" rm loose --delete-branch --yes

  [ "$status" -eq 0 ]
  [ ! -e "$TEST_WORKTREES_DIR/loose" ]
  ! git worktree list --porcelain | grep -Fx "worktree $TEST_WORKTREES_DIR/loose"
  [ "$(git show-ref --heads)" = "$ORIGINAL_REFS" ]
  [ "$(cat "$TEST_REPO/hook-branches")" = $'pre:<>\npost:<>' ]
}

@test "both rename aliases reject detached worktrees before changing refs or paths" {
  local rename_command
  for rename_command in mv rename; do
    run "$PROJECT_ROOT/bin/gtr" "$rename_command" loose renamed --force --yes

    [ "$status" -eq 1 ]
    [[ "$output" == *"Cannot rename a detached worktree"* ]]
    assert_loose_detached
    [ ! -e "$TEST_WORKTREES_DIR/renamed" ]
    [ "$(git show-ref --heads)" = "$ORIGINAL_REFS" ]
  done
}

@test "real detached-named branch resolves to its attached checkout and can be deleted" {
  attach_named_branch
  git config gtr.hook.preRemove 'printf "<%s>\n" "$BRANCH" > "$REPO_ROOT/hook-branch"'

  resolve_worktree '(detached)' "$TEST_REPO" "$TEST_WORKTREES_DIR" ""
  [ "$_ctx_worktree_path" = "$TEST_WORKTREES_DIR/real-branch" ]
  [ "$_ctx_branch" = '(detached)' ]
  [ "$_ctx_detached" -eq 0 ]
  [ "$(_worktree_path_for_ref '(detached)')" = "$TEST_WORKTREES_DIR/real-branch" ]

  run "$PROJECT_ROOT/bin/gtr" rm '(detached)' --delete-branch --yes
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_WORKTREES_DIR/real-branch" ]
  ! git show-ref --verify --quiet 'refs/heads/(detached)'
  assert_loose_detached
  [ "$(cat "$TEST_REPO/hook-branch")" = '<(detached)>' ]
}

@test "real detached-named branch can be renamed without touching detached checkout" {
  attach_named_branch

  run "$PROJECT_ROOT/bin/gtr" mv '(detached)' renamed --yes

  [ "$status" -eq 0 ]
  [ ! -e "$TEST_WORKTREES_DIR/real-branch" ]
  [ -f "$TEST_WORKTREES_DIR/renamed/.git" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/renamed" symbolic-ref HEAD)" = refs/heads/renamed ]
  [ "$(git rev-parse refs/heads/renamed)" = "$ORIGINAL_TIP" ]
  ! git show-ref --verify --quiet 'refs/heads/(detached)'
  assert_loose_detached
}

@test "detached checkout is not a branch-name match for an unchecked-out real branch" {
  run resolve_worktree '(detached)' "$TEST_REPO" "$TEST_WORKTREES_DIR" ""
  [ "$status" -eq 1 ]
  [ -z "$(_worktree_path_for_ref '(detached)')" ]
  [ "$(git show-ref --heads)" = "$ORIGINAL_REFS" ]
  assert_loose_detached
}

@test "detached state survives locked status path resolution and old Git parsing" {
  attach_named_branch
  git worktree lock "$TEST_WORKTREES_DIR/loose"
  git() {
    case "$*" in *"worktree list --porcelain -z") return 1 ;; esac
    command git "$@"
  }
  # Git 2.17 can lock a worktree but does not expose locked in porcelain.
  if command git worktree list --porcelain | grep -Fxq locked; then
    [ "$(worktree_status "$TEST_WORKTREES_DIR/loose")" = locked ]
  else
    [ "$(worktree_status "$TEST_WORKTREES_DIR/loose")" = detached ]
  fi
  resolve_worktree "path:$TEST_WORKTREES_DIR/loose" "$TEST_REPO" "$TEST_WORKTREES_DIR" ""
  [ "$_ctx_worktree_path" = "$TEST_WORKTREES_DIR/loose" ]
  [ -z "$_ctx_branch" ]
  [ "$_ctx_detached" -eq 1 ]
  resolve_worktree '(detached)' "$TEST_REPO" "$TEST_WORKTREES_DIR" ""
  [ "$_ctx_branch" = '(detached)' ]
  [ "$_ctx_detached" -eq 0 ]
  [ "$(list_worktree_branches "$TEST_WORKTREES_DIR" "" "$TEST_REPO")" = '(detached)' ]
  command git worktree unlock "$TEST_WORKTREES_DIR/loose"
}

@test "main ID and path identity agree on detached state including old Git fallback" {
  git checkout --quiet --detach HEAD
  local identity
  for identity in 1 "path:$TEST_REPO"; do
    resolve_worktree "$identity" "$TEST_REPO" "$TEST_WORKTREES_DIR" ""
    [ "$_ctx_is_main" -eq 1 ]
    [ -z "$_ctx_branch" ]
    [ "$_ctx_detached" -eq 1 ]
  done
  git() {
    case "$*" in *"branch --show-current") return 1 ;; esac
    command git "$@"
  }
  resolve_worktree 1 "$TEST_REPO" "$TEST_WORKTREES_DIR" ""
  [ -z "$_ctx_branch" ]
  [ "$_ctx_detached" -eq 1 ]
}

@test "main checkout on real detached-named branch keeps attached identity" {
  git checkout --quiet '(detached)'
  local identity
  for identity in 1 "path:$TEST_REPO" '(detached)'; do
    resolve_worktree "$identity" "$TEST_REPO" "$TEST_WORKTREES_DIR" ""
    [ "$_ctx_is_main" -eq 1 ]
    [ "$_ctx_worktree_path" = "$TEST_REPO" ]
    [ "$_ctx_branch" = '(detached)' ]
    [ "$_ctx_detached" -eq 0 ]
  done
}

@test "detached path identity preserves trailing newlines during rename and removal" {
  git worktree list --porcelain -z >/dev/null 2>&1 || skip "NUL worktree listing is unavailable"
  local path="$TEST_WORKTREES_DIR/loose"$'\n\n' identity
  git worktree move "$TEST_WORKTREES_DIR/loose" "$path"
  mkdir "$TEST_WORKTREES_DIR/loose"
  printf 'keep\n' > "$TEST_WORKTREES_DIR/loose/marker"
  identity="path:$(_tsv_escape_field "$path")"
  resolve_worktree "$identity" "$TEST_REPO" "$TEST_WORKTREES_DIR" ""
  [ "$_ctx_worktree_path" = "$path" ]
  [ -z "$_ctx_branch" ]
  [ "$_ctx_detached" -eq 1 ]

  run "$PROJECT_ROOT/bin/gtr" mv "$identity" renamed --yes
  [ "$status" -eq 1 ]
  [ -f "$path/.git" ]
  [ ! -e "$TEST_WORKTREES_DIR/renamed" ]
  [ "$(git show-ref --heads)" = "$ORIGINAL_REFS" ]

  run "$PROJECT_ROOT/bin/gtr" rm "$identity" --delete-branch --yes
  [ "$status" -eq 0 ]
  [ ! -e "$path" ]
  [ "$(cat "$TEST_WORKTREES_DIR/loose/marker")" = keep ]
  [ "$(git show-ref --heads)" = "$ORIGINAL_REFS" ]
  [ "$(git worktree list --porcelain | grep -c '^worktree ')" -eq 1 ]
}

# Stub only the external provider boundary. Cleanup, tip checks, hooks, Git
# removal and ref deletion all run through the real CLI in a disposable repo.
setup_cleanup_provider() {
  git config gtr.provider github
  export DETACHED_TEST_CALLS="$TEST_REPO/provider-calls"
  mkdir "$TEST_REPO/mock-bin"
  cat > "$TEST_REPO/mock-bin/gh" <<'SH'
#!/usr/bin/env bash
if [ "$1 $2" = 'repo view' ]; then exit 0; fi
printf '%s\n' "$*" >> "$DETACHED_TEST_CALLS"
# gh --jq returns the count of matching PRs, not the raw commit.
printf '1\n'
SH
  chmod +x "$TEST_REPO/mock-bin/gh"
  export PATH="$TEST_REPO/mock-bin:$PATH"
}

assert_cleanup_identity() {
  local mode="$1"
  attach_named_branch
  setup_cleanup_provider

  run "$PROJECT_ROOT/bin/gtr" clean "$mode" --force --yes --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Would remove: (detached)"* ]]
  [ -f "$TEST_WORKTREES_DIR/real-branch/.git" ]
  [ "$(git show-ref --heads)" = "$ORIGINAL_REFS" ]
  assert_loose_detached

  run "$PROJECT_ROOT/bin/gtr" clean "$mode" --force --yes
  printf '%s\n' "$output"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_WORKTREES_DIR/real-branch" ]
  ! git worktree list --porcelain | grep -Fx "worktree $TEST_WORKTREES_DIR/real-branch"
  ! git show-ref --verify --quiet 'refs/heads/(detached)'
  assert_loose_detached
  [ "$(wc -l < "$DETACHED_TEST_CALLS" | tr -d ' ')" -eq 2 ]
  ! grep -vF -- '--head (detached)' "$DETACHED_TEST_CALLS"
  ! grep -vF -- "$ORIGINAL_TIP" "$DETACHED_TEST_CALLS"
}

@test "merged cleanup handles detached state separately from real branch identity" {
  assert_cleanup_identity --merged
}

@test "closed cleanup handles detached state separately from real branch identity" {
  assert_cleanup_identity --closed
}

@test "cleanup processes real detached-named branch when main is detached too" {
  git checkout --quiet --detach HEAD
  assert_cleanup_identity --merged
}

@test "cleanup never queries an unchecked-out branch through a detached worktree" {
  setup_cleanup_provider
  run "$PROJECT_ROOT/bin/gtr" clean --merged --closed --force --yes
  [ "$status" -eq 0 ]
  [ ! -e "$DETACHED_TEST_CALLS" ]
  [ "$(git show-ref --heads)" = "$ORIGINAL_REFS" ]
  assert_loose_detached
}

@test "list preserves public labels and pickers select exact identities despite identical labels" {
  attach_named_branch
  local mode detached_row attached_row identity
  for mode in --porcelain --ids; do
    run "$PROJECT_ROOT/bin/gtr" list "$mode"
    [ "$status" -eq 0 ]
    detached_row="$TEST_WORKTREES_DIR/loose"$'\t(detached)\tdetached'
    attached_row="$TEST_WORKTREES_DIR/real-branch"$'\t(detached)\tok'
    [ "$mode" != --ids ] || detached_row="path:$detached_row"
    [ "$mode" != --ids ] || attached_row="path:$attached_row"
    [[ "$output" == *"$detached_row"* ]]
    [[ "$output" == *"$attached_row"* ]]
  done
  identity="${detached_row%%$'\t'*}"
  run "$PROJECT_ROOT/bin/gtr" rm "$identity" --delete-branch --yes
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_WORKTREES_DIR/loose" ]
  [ -f "$TEST_WORKTREES_DIR/real-branch/.git" ]
  [ "$(git show-ref --heads)" = "$ORIGINAL_REFS" ]
}

@test "copy targets real branch independently and --all still copies to detached checkout" {
  attach_named_branch
  printf 'payload\n' > "$TEST_REPO/payload"
  run "$PROJECT_ROOT/bin/gtr" copy '(detached)' -- payload
  [ "$status" -eq 0 ]
  cmp "$TEST_REPO/payload" "$TEST_WORKTREES_DIR/real-branch/payload"
  [ ! -e "$TEST_WORKTREES_DIR/loose/payload" ]
  run "$PROJECT_ROOT/bin/gtr" copy --all -- payload
  [ "$status" -eq 0 ]
  cmp "$TEST_REPO/payload" "$TEST_WORKTREES_DIR/loose/payload"
  cmp "$TEST_REPO/payload" "$TEST_WORKTREES_DIR/real-branch/payload"
}

@test "AI hooks receive empty branch for detached targets and literal real branch identity" {
  attach_named_branch
  git config gtr.hook.postCd 'printf "<%s>\n" "$BRANCH" > "$WORKTREE_PATH/hook-branch"'
  run "$PROJECT_ROOT/bin/gtr" ai loose --ai true
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_WORKTREES_DIR/loose/hook-branch")" = '<>' ]
  run "$PROJECT_ROOT/bin/gtr" ai '(detached)' --ai true
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_WORKTREES_DIR/real-branch/hook-branch")" = '<(detached)>' ]
}
