#!/usr/bin/env bats
# Tests for create_worktree and its helpers in lib/core.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_libs
}

teardown() {
  teardown_integration_repo
}

# ── _resolve_folder_name ────────────────────────────────────────────────────

@test "_resolve_folder_name sanitizes branch name" {
  local result
  result=$(_resolve_folder_name "feature/auth")
  [ "$result" = "feature-auth" ]
}

@test "_resolve_folder_name appends custom name" {
  local result
  result=$(_resolve_folder_name "feature/auth" "backend")
  [ "$result" = "feature-auth-backend" ]
}

@test "_resolve_folder_name sanitizes custom name" {
  local result
  result=$(_resolve_folder_name "feature/auth" "../backend/api")
  [ "$result" = "feature-auth-..-backend-api" ]
}

@test "_resolve_folder_name rejects empty custom name result" {
  run _resolve_folder_name "feature/auth" "/"
  [ "$status" -eq 1 ]
}

@test "_resolve_folder_name uses folder override" {
  local result
  result=$(_resolve_folder_name "feature/auth" "" "my-folder")
  [ "$result" = "my-folder" ]
}

@test "_resolve_folder_name rejects empty result" {
  run _resolve_folder_name ""
  [ "$status" -eq 1 ]
}

@test "_resolve_folder_name rejects dot" {
  run _resolve_folder_name "."
  [ "$status" -eq 1 ]
}

@test "_resolve_folder_name rejects double-dot" {
  run _resolve_folder_name ".."
  [ "$status" -eq 1 ]
}

# ── default remote/branch resolution ─────────────────────────────────────────

@test "resolve_default_remote reads gtr.defaultRemote" {
  git config gtr.defaultRemote upstream

  local result
  result=$(resolve_default_remote)
  [ "$result" = "upstream" ]
}

@test "resolve_default_branch detects branch from selected remote" {
  git update-ref refs/remotes/upstream/main HEAD

  local result
  result=$(resolve_default_branch "$TEST_REPO" "upstream")
  [ "$result" = "main" ]
}

# ── _check_branch_refs ──────────────────────────────────────────────────────

@test "_check_branch_refs detects local branch" {
  git branch local-only HEAD
  _check_branch_refs "local-only"
  [ "$_wt_local_exists" -eq 1 ]
  [ "$_wt_remote_exists" -eq 0 ]
}

@test "_check_branch_refs sets both to 0 for unknown branch" {
  _check_branch_refs "nonexistent-branch"
  [ "$_wt_local_exists" -eq 0 ]
  [ "$_wt_remote_exists" -eq 0 ]
}

@test "_check_branch_refs detects selected remote branch" {
  git update-ref refs/remotes/upstream/remote-only HEAD

  _check_branch_refs "remote-only" "upstream"
  [ "$_wt_remote_exists" -eq 1 ]
  [ "$_wt_local_exists" -eq 0 ]
}

# ── create_worktree ─────────────────────────────────────────────────────────

@test "create_worktree creates directory with track=none" {
  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "new-branch" "HEAD" "none" "1")
  [ -d "$wt_path" ]
  [ "$wt_path" = "$TEST_WORKTREES_DIR/new-branch" ]
}

@test "create_worktree uses local branch with track=local" {
  git branch local-branch HEAD
  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "local-branch" "HEAD" "local" "1")
  [ -d "$wt_path" ]
}

@test "create_worktree fails for missing local branch with track=local" {
  run create_worktree "$TEST_WORKTREES_DIR" "" "nope" "HEAD" "local" "1"
  [ "$status" -eq 1 ]
}

@test "create_worktree fails for missing remote branch with track=remote" {
  git branch nope HEAD
  run create_worktree "$TEST_WORKTREES_DIR" "" "nope" "HEAD" "remote" "1"
  [ "$status" -eq 1 ]
  [[ "$output" == *"Remote branch origin/nope does not exist"* ]]
  [ ! -e "$TEST_WORKTREES_DIR/nope" ]
}

# A real local remote whose feature tip differs from the caller's HEAD.
_setup_track_remote() {
  local remote="${1:-origin}" base
  base=$(git rev-parse HEAD)
  git init --bare --quiet "$TEST_REPO/remote.git"
  git remote add "$remote" "$TEST_REPO/remote.git"
  echo remote > remote.txt
  git add remote.txt
  git commit -m "remote feature" --quiet
  TEST_REMOTE_TIP=$(git rev-parse HEAD)
  git push --quiet "$remote" HEAD:refs/heads/feature/auth HEAD:refs/heads/other
  git reset --hard "$base" --quiet
  git fetch --quiet "$remote"
}

_assert_remote_checkout() {
  local wt_path="$1" remote="${2:-origin}"
  [ "$(git -C "$wt_path" symbolic-ref HEAD)" = refs/heads/feature/auth ]
  [ "$(git -C "$wt_path" rev-parse HEAD)" = "$TEST_REMOTE_TIP" ]
  [ "$(git -C "$wt_path" config --get-all branch.feature/auth.remote)" = "$remote" ]
  [ "$(git -C "$wt_path" config --get-all branch.feature/auth.merge)" = refs/heads/feature/auth ]
  [ "$(git -C "$wt_path" rev-parse --symbolic-full-name '@{u}')" = "refs/remotes/$remote/feature/auth" ]
}

@test "create_worktree remote mode explicitly tracks new branches with autoSetupMerge disabled" {
  _setup_track_remote
  git config branch.autoSetupMerge false
  # A short remote ref must not accidentally resolve to a same-named tag.
  git tag origin/feature/auth HEAD

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" feature/auth HEAD remote 1)

  [ "$wt_path" = "$TEST_WORKTREES_DIR/feature-auth" ]
  _assert_remote_checkout "$wt_path"
  [ "$(cat "$wt_path/remote.txt")" = remote ]
}

@test "create_worktree remote mode reuses matching branches and ensures the selected upstream" {
  _setup_track_remote
  local upstream wt_path
  for upstream in missing correct different; do
    git branch --no-track feature/auth "$TEST_REMOTE_TIP"
    case "$upstream" in
      correct) git branch --set-upstream-to=origin/feature/auth feature/auth ;;
      different) git branch --set-upstream-to=origin/other feature/auth ;;
    esac

    wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" feature/auth HEAD remote 1)

    _assert_remote_checkout "$wt_path"
    [ "$(cat "$wt_path/remote.txt")" = remote ]
    git worktree remove "$wt_path"
    git branch -D feature/auth
  done
}

_assert_remote_tip_conflict() {
  local relation="$1" local_tip before_config before_worktrees force
  _setup_track_remote
  case "$relation" in
    ahead) local_tip=$(git commit-tree "$TEST_REMOTE_TIP^{tree}" -p "$TEST_REMOTE_TIP" -m ahead) ;;
    behind) local_tip=$(git rev-parse HEAD) ;;
    diverged) local_tip=$(git commit-tree 'HEAD^{tree}' -p HEAD -m diverged) ;;
  esac
  git branch --no-track feature/auth "$local_tip"
  if [ "$relation" = behind ]; then
    git branch --set-upstream-to=origin/feature/auth feature/auth
  elif [ "$relation" = diverged ]; then
    git branch --set-upstream-to=origin/other feature/auth
  fi
  before_config=$(git config --local --list)
  before_worktrees=$(git worktree list --porcelain)

  # --force permits duplicate checkouts, never a different remote-mode tip.
  for force in 0 1; do
    run create_worktree "$TEST_WORKTREES_DIR" "" feature/auth HEAD remote 1 "$force" review

    [ "$status" -eq 1 ]
    [[ "$output" == *"Local branch feature/auth differs from origin/feature/auth"* ]]
    [[ "$output" == *"--track local"* ]]
    [[ "$output" != *"Worktree created"* ]]
    [ ! -e "$TEST_WORKTREES_DIR/feature-auth-review" ]
    [ "$(git rev-parse refs/heads/feature/auth)" = "$local_tip" ]
    [ "$(git rev-parse refs/remotes/origin/feature/auth)" = "$TEST_REMOTE_TIP" ]
    [ "$(git config --local --list)" = "$before_config" ]
    [ "$(git worktree list --porcelain)" = "$before_worktrees" ]
  done
}

@test "create_worktree remote mode rejects an ahead local branch without changing it" {
  _assert_remote_tip_conflict ahead
}

@test "create_worktree remote mode rejects a behind local branch without fast-forwarding it" {
  _assert_remote_tip_conflict behind
}

@test "create_worktree remote mode rejects a diverged local branch without changing it" {
  _assert_remote_tip_conflict diverged
}

@test "create_worktree remote mode uses the selected remote for new and existing branches" {
  _setup_track_remote upstream
  git remote add origin "$TEST_REPO/remote.git"
  git fetch --quiet origin
  # origin has a different tip, but only the selected remote should matter.
  git update-ref refs/remotes/origin/feature/auth HEAD
  git config gtr.defaultRemote upstream

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" feature/auth HEAD remote 1)
  _assert_remote_checkout "$wt_path" upstream
  git worktree remove "$wt_path"
  git branch --set-upstream-to=origin/feature/auth feature/auth

  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" feature/auth HEAD remote 1 0 "" "" upstream)
  _assert_remote_checkout "$wt_path" upstream
}

@test "create_worktree remote mode reports upstream setup failure without claiming success" {
  _setup_track_remote
  local branch_state
  for branch_state in new existing; do
    if [ "$branch_state" = existing ]; then
      git branch --no-track feature/auth "$TEST_REMOTE_TIP"
    fi
    touch "$TEST_REPO/.git/config.lock"

    run create_worktree "$TEST_WORKTREES_DIR" "" feature/auth HEAD remote 1

    [ "$status" -eq 1 ]
    if [ "$branch_state" = existing ]; then
      [[ "$output" == *"Could not set upstream"* ]]
      [ "$(git rev-parse refs/heads/feature/auth)" = "$TEST_REMOTE_TIP" ]
    fi
    [[ "$output" != *"Worktree created"* ]]
    [[ "$output" != *"does not exist"* ]]
    [ ! -e "$TEST_WORKTREES_DIR/feature-auth" ]
    ! git config --get branch.feature/auth.remote
    rm "$TEST_REPO/.git/config.lock"
    if git show-ref --verify --quiet refs/heads/feature/auth; then
      git branch -D feature/auth
    fi
  done
}

@test "create_worktree remote mode preserves force and deferred checkout behavior" {
  _setup_track_remote
  git branch --track feature/auth origin/feature/auth
  git worktree add "$TEST_WORKTREES_DIR/first" feature/auth
  echo dirty > "$TEST_WORKTREES_DIR/first/remote.txt"

  run create_worktree "$TEST_WORKTREES_DIR" "" feature/auth HEAD remote 1 0 second
  [ "$status" -eq 1 ]
  [[ "$output" != *"does not exist"* ]]
  [[ "$output" != *"Worktree created"* ]]

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" feature/auth HEAD remote 1 1 second "" origin 1 "$TEST_REPO")
  _assert_remote_checkout "$wt_path"
  [ ! -e "$wt_path/remote.txt" ]
  [ "$(cat "$TEST_WORKTREES_DIR/first/remote.txt")" = dirty ]
}

@test "create_worktree auto and local modes keep a differing local tip and upstream" {
  _setup_track_remote
  git branch --no-track feature/auth HEAD
  git branch --set-upstream-to=origin/other feature/auth
  local mode wt_path before_config local_tip
  before_config=$(git config --local --list)
  local_tip=$(git rev-parse refs/heads/feature/auth)
  for mode in auto local; do
    wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" feature/auth HEAD "$mode" 1)
    [ "$(git -C "$wt_path" rev-parse HEAD)" = "$local_tip" ]
    [ "$(git -C "$wt_path" rev-parse --symbolic-full-name '@{u}')" = refs/remotes/origin/other ]
    [ "$(git config --local --list)" = "$before_config" ]
    git worktree remove "$wt_path"
  done
}

@test "create_worktree none mode uses from_ref even with a remote branch and rejects local reuse" {
  _setup_track_remote
  local wt_path local_tip
  local_tip=$(git rev-parse HEAD)
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" feature/auth HEAD none 1)
  [ "$(git -C "$wt_path" rev-parse HEAD)" = "$local_tip" ]
  ! git config --get branch.feature/auth.remote
  git worktree remove "$wt_path"

  run create_worktree "$TEST_WORKTREES_DIR" "" feature/auth HEAD none 1
  [ "$status" -eq 1 ]
  [ "$(git rev-parse refs/heads/feature/auth)" = "$local_tip" ]
  [ ! -e "$wt_path" ]
}

@test "new CLI remote conflict emits no porcelain records or hooks after fetching" {
  _setup_track_remote upstream
  # A stale matching remote ref must be refreshed before the comparison.
  git branch --no-track feature/auth HEAD
  git update-ref refs/remotes/upstream/feature/auth HEAD
  git config gtr.hook.postCreate 'touch hook-marker'
  local stdout_file="$BATS_TEST_TMPDIR/stdout" stderr_file="$BATS_TEST_TMPDIR/stderr"

  run bash -c '"$1" new feature/auth --from HEAD --remote upstream --track remote --porcelain >"$2" 2>"$3"' \
    _ "$PROJECT_ROOT/bin/gtr" "$stdout_file" "$stderr_file"

  [ "$status" -eq 1 ]
  [ ! -s "$stdout_file" ]
  grep -q 'Local branch feature/auth differs from upstream/feature/auth' "$stderr_file"
  ! grep -q 'Worktree created' "$stderr_file"
  [ "$(git rev-parse refs/remotes/upstream/feature/auth)" = "$TEST_REMOTE_TIP" ]
  [ "$(git rev-parse refs/heads/feature/auth)" = "$(git rev-parse HEAD)" ]
  [ ! -e "$TEST_WORKTREES_DIR/feature-auth" ]
  ! git config --get branch.feature/auth.remote
}

@test "new CLI remote mode emits porcelain success with the requested upstream" {
  _setup_track_remote upstream
  git branch --no-track feature/auth "$TEST_REMOTE_TIP"
  local stdout_file="$BATS_TEST_TMPDIR/stdout" stderr_file="$BATS_TEST_TMPDIR/stderr"

  run bash -c '"$1" new feature/auth --from HEAD --remote upstream --track remote --no-copy --no-hooks --porcelain >"$2" 2>"$3"' \
    _ "$PROJECT_ROOT/bin/gtr" "$stdout_file" "$stderr_file"

  [ "$status" -eq 0 ]
  [ "$(cat "$stdout_file")" = $'path\t'"$TEST_WORKTREES_DIR/feature-auth"$'\nbranch\tfeature/auth\nhook_status\tdisabled' ]
  _assert_remote_checkout "$TEST_WORKTREES_DIR/feature-auth" upstream
}

@test "create_worktree auto mode creates new branch when neither exists" {
  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "auto-new" "HEAD" "auto" "1")
  [ -d "$wt_path" ]
}

@test "create_worktree auto mode uses existing local branch" {
  git branch existing-local HEAD
  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "existing-local" "HEAD" "auto" "1")
  [ -d "$wt_path" ]
}

@test "create_worktree auto mode tracks selected remote branch" {
  git remote add upstream "$TEST_REPO" 2>/dev/null || true
  git branch selected-remote HEAD
  git fetch upstream --quiet
  git branch -D selected-remote >/dev/null

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "selected-remote" "HEAD" "auto" "1" "0" "" "" "upstream")
  [ -d "$wt_path" ]

  local upstream
  upstream=$(git -C "$wt_path" rev-parse --abbrev-ref --symbolic-full-name '@{u}')
  [ "$upstream" = "upstream/selected-remote" ]
}

@test "create_worktree rejects duplicate worktree" {
  create_worktree "$TEST_WORKTREES_DIR" "" "dup-test" "HEAD" "none" "1" >/dev/null
  run create_worktree "$TEST_WORKTREES_DIR" "" "dup-test" "HEAD" "none" "1"
  [ "$status" -eq 1 ]
}

@test "create_worktree applies prefix to folder name" {
  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "wt-" "prefixed" "HEAD" "none" "1")
  [ "$wt_path" = "$TEST_WORKTREES_DIR/wt-prefixed" ]
  [ -d "$wt_path" ]
}

@test "create_worktree preserves empty dotted and spaced folder prefixes" {
  local prefix wt_path index=0
  for prefix in "" "dev-" "." ".." "my team-"; do
    wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "$prefix" "prefix-$index" "HEAD" "none" "1")
    [ "$wt_path" = "$TEST_WORKTREES_DIR/${prefix}prefix-$index" ]
    [ -f "$wt_path/.git" ]
    index=$((index + 1))
  done
}

@test "create_worktree rejects prefix path separators before creating directories or branches" {
  # Even a regression can only create destinations inside this disposable repo.
  local base_dir="$TEST_REPO/prefix-fixture/trees" prefix
  mkdir -p "$TEST_REPO/prefix-fixture"
  for prefix in "../planted-" "group/../../planted-" "group/dev-" "/absolute-" \
      '..\planted-' 'group\dev-' 'C:\dev-'; do
    run create_worktree "$base_dir" "$prefix" "rejected-prefix" "HEAD" "none" "1"
    [ "$status" -eq 1 ]
    [[ "$output" == *"Invalid gtr.worktrees.prefix"* ]]
    [ ! -e "$base_dir" ]
    [ ! -e "$TEST_REPO/prefix-fixture/planted-rejected-prefix" ]
    ! git show-ref --verify --quiet refs/heads/rejected-prefix
  done
}

@test "create_worktree applies custom name suffix" {
  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "feature" "HEAD" "none" "1" "0" "backend")
  [ "$wt_path" = "$TEST_WORKTREES_DIR/feature-backend" ]
}

@test "create_worktree applies folder override" {
  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "any-branch" "HEAD" "none" "1" "0" "" "custom-dir")
  [ "$wt_path" = "$TEST_WORKTREES_DIR/custom-dir" ]
}

@test "create_worktree creates base dir if needed" {
  local nested="$TEST_WORKTREES_DIR/sub/trees"
  local wt_path
  wt_path=$(create_worktree "$nested" "" "nest-test" "HEAD" "none" "1")
  [ -d "$nested" ]
  [ -d "$wt_path" ]
}

@test "create_worktree sanitizes slashed branch for folder" {
  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "feature/deep/path" "HEAD" "none" "1")
  [ "$wt_path" = "$TEST_WORKTREES_DIR/feature-deep-path" ]
}

# ── from_ref handling ──────────────────────────────────────────────────────

@test "create_worktree from local branch starts at that branch's commit" {
  git commit --allow-empty -m "second" --quiet
  local expected_sha
  expected_sha=$(git rev-parse HEAD)

  git branch from-source HEAD
  git reset --hard HEAD~1 --quiet

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "from-local" "from-source" "none" "1")
  [ -d "$wt_path" ]

  local actual_sha
  actual_sha=$(git -C "$wt_path" rev-parse HEAD)
  [ "$actual_sha" = "$expected_sha" ]
}

@test "create_worktree from lightweight tag starts at the tagged commit" {
  git commit --allow-empty -m "tagged commit" --quiet
  local expected_sha
  expected_sha=$(git rev-parse HEAD)
  git tag v1.0.0

  git commit --allow-empty -m "after tag" --quiet

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "from-light-tag" "v1.0.0" "none" "1")
  [ -d "$wt_path" ]

  local actual_sha
  actual_sha=$(git -C "$wt_path" rev-parse HEAD)
  [ "$actual_sha" = "$expected_sha" ]
}

@test "create_worktree from annotated tag starts at the tagged commit" {
  git commit --allow-empty -m "tagged commit" --quiet
  local expected_sha
  expected_sha=$(git rev-parse HEAD)
  git tag -a v2.0.0 -m "v2.0.0"

  git commit --allow-empty -m "after tag" --quiet

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "from-ann-tag" "v2.0.0" "none" "1")
  [ -d "$wt_path" ]

  local actual_sha
  actual_sha=$(git -C "$wt_path" rev-parse HEAD)
  [ "$actual_sha" = "$expected_sha" ]
}

@test "create_worktree from commit SHA starts at that commit" {
  git commit --allow-empty -m "target commit" --quiet
  local expected_sha
  expected_sha=$(git rev-parse HEAD)

  git commit --allow-empty -m "later commit" --quiet

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "from-sha" "$expected_sha" "none" "1")
  [ -d "$wt_path" ]

  local actual_sha
  actual_sha=$(git -C "$wt_path" rev-parse HEAD)
  [ "$actual_sha" = "$expected_sha" ]
}

@test "create_worktree from remote branch uses the requested branch name not the remote name" {
  # Set up a "remote" by using the test repo as its own remote
  git remote add origin "$TEST_REPO" 2>/dev/null || true
  git branch remote-feature HEAD
  git fetch origin --quiet

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "my-branch" "remote-feature" "none" "1")
  [ -d "$wt_path" ]

  # The worktree branch must be our requested name, not the remote branch name
  local actual_branch
  actual_branch=$(git -C "$wt_path" rev-parse --abbrev-ref HEAD)
  [ "$actual_branch" = "my-branch" ]
}

@test "create_worktree from remote branch starts at the correct commit" {
  git commit --allow-empty -m "remote target" --quiet
  local expected_sha
  expected_sha=$(git rev-parse HEAD)

  git remote add origin "$TEST_REPO" 2>/dev/null || true
  git branch remote-source HEAD
  git fetch origin --quiet

  git commit --allow-empty -m "moved on" --quiet

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "from-remote-ref" "remote-source" "none" "1")
  [ -d "$wt_path" ]

  local actual_sha
  actual_sha=$(git -C "$wt_path" rev-parse HEAD)
  [ "$actual_sha" = "$expected_sha" ]
}

@test "create_worktree auto mode from local branch starts at that commit" {
  git commit --allow-empty -m "auto target" --quiet
  local expected_sha
  expected_sha=$(git rev-parse HEAD)

  git branch auto-source HEAD
  git reset --hard HEAD~1 --quiet

  local wt_path
  wt_path=$(create_worktree "$TEST_WORKTREES_DIR" "" "auto-from-local" "auto-source" "auto" "1")
  [ -d "$wt_path" ]

  local actual_sha
  actual_sha=$(git -C "$wt_path" rev-parse HEAD)
  [ "$actual_sha" = "$expected_sha" ]
}

@test "create_worktree fails with invalid from_ref" {
  run create_worktree "$TEST_WORKTREES_DIR" "" "bad-ref" "nonexistent-ref-xyz" "none" "1"
  [ "$status" -eq 1 ]
}
