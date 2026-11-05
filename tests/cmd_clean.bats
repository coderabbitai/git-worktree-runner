#!/usr/bin/env bats
# Tests for cmd_clean in lib/commands/clean.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
}

teardown() {
  teardown_integration_repo
}

# ── Basic clean (prune + empty dirs) ────────────────────────────────────────

@test "cmd_clean runs without errors" {
  run cmd_clean
  [ "$status" -eq 0 ]
}

@test "cmd_clean removes empty directories" {
  mkdir -p "$TEST_WORKTREES_DIR/empty-dir"
  cmd_clean
  [ ! -d "$TEST_WORKTREES_DIR/empty-dir" ]
}

@test "cmd_clean preserves non-empty directories" {
  create_test_worktree "keep-me"
  cmd_clean
  [ -d "$TEST_WORKTREES_DIR/keep-me" ]
}

@test "cmd_clean handles missing worktrees dir" {
  # Don't create any worktrees - base_dir doesn't exist
  run cmd_clean
  [ "$status" -eq 0 ]
}

# ── _clean_detect_provider ──────────────────────────────────────────────────

@test "_clean_detect_provider fails without remote" {
  run _clean_detect_provider
  [ "$status" -eq 1 ]
}

# ── _clean_should_skip ──────────────────────────────────────────────────────

@test "_clean_should_skip skips detached HEAD" {
  run _clean_should_skip "/some/dir" "(detached)"
  [ "$status" -eq 0 ]
}

@test "_clean_should_skip skips empty branch" {
  run _clean_should_skip "/some/dir" ""
  [ "$status" -eq 0 ]
}

@test "_clean_should_skip skips dirty worktree" {
  create_test_worktree "dirty-test"
  echo "dirty" > "$TEST_WORKTREES_DIR/dirty-test/untracked.txt"
  git -C "$TEST_WORKTREES_DIR/dirty-test" add untracked.txt
  run _clean_should_skip "$TEST_WORKTREES_DIR/dirty-test" "dirty-test"
  [ "$status" -eq 0 ]
}

@test "_clean_should_skip skips worktree with untracked files" {
  create_test_worktree "untracked-test"
  echo "new" > "$TEST_WORKTREES_DIR/untracked-test/newfile.txt"
  run _clean_should_skip "$TEST_WORKTREES_DIR/untracked-test" "untracked-test"
  [ "$status" -eq 0 ]
}

@test "_clean_should_skip does not skip clean worktree" {
  create_test_worktree "clean-wt"
  run _clean_should_skip "$TEST_WORKTREES_DIR/clean-wt" "clean-wt"
  [ "$status" -eq 1 ]  # 1 = don't skip
}

@test "_clean_should_skip with force=1 does not skip dirty worktree" {
  create_test_worktree "dirty-force"
  echo "dirty" > "$TEST_WORKTREES_DIR/dirty-force/untracked.txt"
  git -C "$TEST_WORKTREES_DIR/dirty-force" add untracked.txt
  run _clean_should_skip "$TEST_WORKTREES_DIR/dirty-force" "dirty-force" 1
  [ "$status" -eq 1 ]  # 1 = don't skip
}

@test "_clean_should_skip with force=1 does not skip worktree with untracked files" {
  create_test_worktree "untracked-force"
  echo "new" > "$TEST_WORKTREES_DIR/untracked-force/newfile.txt"
  run _clean_should_skip "$TEST_WORKTREES_DIR/untracked-force" "untracked-force" 1
  [ "$status" -eq 1 ]  # 1 = don't skip
}

@test "_clean_should_skip with force=1 still skips detached HEAD" {
  run _clean_should_skip "/some/dir" "(detached)" 1
  [ "$status" -eq 0 ]  # 0 = skip (protection maintained)
}

@test "_clean_should_skip with force=1 still skips empty branch" {
  run _clean_should_skip "/some/dir" "" 1
  [ "$status" -eq 0 ]  # 0 = skip (protection maintained)
}

@test "_clean_should_skip with force=1 still skips current active worktree" {
  create_test_worktree "active-force"
  run _clean_should_skip "$TEST_WORKTREES_DIR/active-force" "active-force" 1 "$TEST_WORKTREES_DIR/active-force"
  [ "$status" -eq 0 ]  # 0 = skip (protection maintained)
}

@test "_clean_should_skip with force=1 skips current active worktree via symlink path" {
  create_test_worktree "active-force-symlink"
  ln -s "$TEST_WORKTREES_DIR/active-force-symlink" "$TEST_REPO/active-force-link"
  run _clean_should_skip "$TEST_REPO/active-force-link" "active-force-symlink" 1 "$TEST_WORKTREES_DIR/active-force-symlink"
  [ "$status" -eq 0 ]  # 0 = skip (protection maintained)
}

@test "cmd_clean accepts --force and -f flags without error" {
  run cmd_clean --force
  [ "$status" -eq 0 ]

  run cmd_clean -f
  [ "$status" -eq 0 ]
}

@test "cmd_clean rejects --to without PR state filter" {
  run cmd_clean --to main
  [ "$status" -eq 1 ]
  [[ "$output" == *"--to can only be used with --merged or --closed"* ]]
}

@test "cmd_clean --merged --force removes dirty merged worktrees" {
  create_test_worktree "merged-force"
  echo "dirty" > "$TEST_WORKTREES_DIR/merged-force/dirty.txt"
  git -C "$TEST_WORKTREES_DIR/merged-force" add dirty.txt

  _clean_detect_provider() { printf "github"; }
  ensure_provider_cli() { return 0; }
  check_branch_merged() { [ "$2" = "merged-force" ] && [ -z "$3" ]; }
  run_hooks_in() { return 0; }
  run_hooks() { return 0; }

  run cmd_clean --merged --force --yes
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_WORKTREES_DIR/merged-force" ]
}

@test "cmd_clean --merged uses nested registered worktree path" {
  mkdir -p "$TEST_WORKTREES_DIR/jsmith"
  git -C "$TEST_REPO" worktree add "$TEST_WORKTREES_DIR/jsmith/my-feature" -b jsmith/my-feature --quiet

  _clean_detect_provider() { printf "github"; }
  ensure_provider_cli() { return 0; }
  check_branch_merged() {
    [ "$2" = "jsmith/my-feature" ]
  }
  run_hooks_in() {
    printf "preRemove:%s\n" "$2"
    return 0
  }
  run_hooks() { return 0; }

  run cmd_clean --merged --force --yes
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_WORKTREES_DIR/jsmith/my-feature" ]
  [[ "$output" == *"preRemove:$TEST_WORKTREES_DIR/jsmith/my-feature"* ]]
  [ ! -e "$TEST_WORKTREES_DIR/jsmith/.git" ]
}

@test "cmd_clean --merged --to filters by target ref" {
  create_test_worktree "merged-to-main"
  create_test_worktree "merged-to-feature"

  _clean_detect_provider() { printf "github"; }
  ensure_provider_cli() { return 0; }
  check_branch_merged() {
    [ "$3" = "main" ] && [ "$2" = "merged-to-main" ]
  }
  run_hooks_in() { return 0; }
  run_hooks() { return 0; }

  run cmd_clean --merged --to main --yes
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_WORKTREES_DIR/merged-to-main" ]
  [ -d "$TEST_WORKTREES_DIR/merged-to-feature" ]
}

@test "cmd_clean --closed --to removes closed worktrees" {
  create_test_worktree "closed-to-main"
  create_test_worktree "closed-to-feature"

  _clean_detect_provider() { printf "github"; }
  ensure_provider_cli() { return 0; }
  check_branch_closed() {
    [ "$3" = "main" ] && [ "$2" = "closed-to-main" ]
  }
  run_hooks_in() { return 0; }
  run_hooks() { return 0; }

  run cmd_clean --closed --to main --yes
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_WORKTREES_DIR/closed-to-main" ]
  [ -d "$TEST_WORKTREES_DIR/closed-to-feature" ]
}

@test "cmd_clean --merged --closed removes merged OR closed worktrees" {
  create_test_worktree "merged-match"
  create_test_worktree "closed-match"
  create_test_worktree "open-match"

  _clean_detect_provider() { printf "github"; }
  ensure_provider_cli() { return 0; }
  check_branch_merged() { [ "$2" = "merged-match" ]; }
  check_branch_closed() { [ "$2" = "closed-match" ]; }
  run_hooks_in() { return 0; }
  run_hooks() { return 0; }

  run cmd_clean --merged --closed --yes --force --to main
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_WORKTREES_DIR/merged-match" ]
  [ ! -d "$TEST_WORKTREES_DIR/closed-match" ]
  [ -d "$TEST_WORKTREES_DIR/open-match" ]
}

@test "cmd_clean passes current branch HEAD to merged check" {
  create_test_worktree "merged-tip"
  local branch_tip
  branch_tip=$(git -C "$TEST_WORKTREES_DIR/merged-tip" rev-parse HEAD)

  _clean_detect_provider() { printf "github"; }
  ensure_provider_cli() { return 0; }
  check_branch_merged() { [ "$2" = "merged-tip" ] && [ "$3" = "main" ] && [ "$4" = "$branch_tip" ]; }
  run_hooks_in() { return 0; }
  run_hooks() { return 0; }

  run cmd_clean --merged --to main --yes
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_WORKTREES_DIR/merged-tip" ]
}

# Keep Git and hook execution real; only stub the hosting service response.
setup_validated_tip_candidate() {
  create_test_worktree "validated-tip"
  git -C "$TEST_WT_PATH" commit --allow-empty -m "PR tip" --quiet
  CLEAN_VALIDATED_TIP=$(git -C "$TEST_WT_PATH" rev-parse HEAD)
  git config branch.validated-tip.description "Keep until branch deletion succeeds"
  git config gtr.hook.postRemove 'printf "post\n" >> "$REPO_ROOT/hook-order"'
  _clean_detect_provider() { printf "github"; }
  ensure_provider_cli() { return 0; }
  check_branch_merged() { [ "$2" = validated-tip ] && [ "$4" = "$CLEAN_VALIDATED_TIP" ]; }
  check_branch_closed() { check_branch_merged "$@"; }
}

assert_changed_candidate_is_preserved() {
  [ "$status" -eq 0 ]
  [ -d "$TEST_WT_PATH" ]
  [ "$(cat "$TEST_REPO/hook-order")" = pre ]
  [[ "$output" == *"Skipping validated-tip"* ]]
  [[ "$output" == *"after preRemove"* ]]
  [[ "$output" == *"Removed: 0, Skipped: 1"* ]]
}

assert_cleanup_preserves_hook_commit() {
  setup_validated_tip_candidate
  git config gtr.hook.preRemove \
    'printf "pre\n" >> "$REPO_ROOT/hook-order"; git commit --allow-empty -m "New unmatched work" --quiet'

  run run_clean_with_errexit "$@" --yes
  assert_changed_candidate_is_preserved
  [ "$(git rev-parse refs/heads/validated-tip)" != "$CLEAN_VALIDATED_TIP" ]
  [ -n "$(git config branch.validated-tip.description)" ]
}

@test "cmd_clean preserves a branch advanced by preRemove" {
  assert_cleanup_preserves_hook_commit --merged
}

@test "cmd_clean --closed --force cannot bypass the post-hook tip check" {
  assert_cleanup_preserves_hook_commit --closed --force
}

@test "cmd_clean skips a hook checkout even when both branches have the same tip" {
  setup_validated_tip_candidate
  git branch other-tip "$CLEAN_VALIDATED_TIP"
  git config gtr.hook.preRemove \
    'printf "pre\n" >> "$REPO_ROOT/hook-order"; git checkout --quiet other-tip'

  run run_clean_with_errexit --merged --force --yes
  assert_changed_candidate_is_preserved
  [ "$(git -C "$TEST_WT_PATH" symbolic-ref HEAD)" = refs/heads/other-tip ]
  [ "$(git rev-parse refs/heads/validated-tip)" = "$CLEAN_VALIDATED_TIP" ]
}

@test "cmd_clean skips a hook that detaches HEAD at the validated tip" {
  setup_validated_tip_candidate
  git config gtr.hook.preRemove \
    'printf "pre\n" >> "$REPO_ROOT/hook-order"; git checkout --quiet --detach HEAD'

  run run_clean_with_errexit --merged --force --yes
  assert_changed_candidate_is_preserved
  ! git -C "$TEST_WT_PATH" symbolic-ref --quiet HEAD
  [ "$(git rev-parse refs/heads/validated-tip)" = "$CLEAN_VALIDATED_TIP" ]
}

@test "cmd_clean skips a hook that renames the validated branch" {
  setup_validated_tip_candidate
  git config gtr.hook.preRemove \
    'printf "pre\n" >> "$REPO_ROOT/hook-order"; git branch -m renamed-tip'

  run run_clean_with_errexit --closed --force --yes
  assert_changed_candidate_is_preserved
  [ "$(git -C "$TEST_WT_PATH" symbolic-ref HEAD)" = refs/heads/renamed-tip ]
  [ "$(git rev-parse refs/heads/renamed-tip)" = "$CLEAN_VALIDATED_TIP" ]
  [ -n "$(git config branch.renamed-tip.description)" ]
}

@test "cmd_clean fails closed when post-hook branch state cannot be established" {
  setup_validated_tip_candidate
  git config gtr.hook.preRemove 'printf "pre\n" > "$REPO_ROOT/hook-order"'
  git() {
    if [ "$1" = -C ] && [ "$2" = "$TEST_WT_PATH" ] && \
       [ "$3" = "$CLEAN_FAIL_COMMAND" ] && [ -e "$TEST_REPO/hook-order" ]; then
      printf "%s" "$CLEAN_LOOKUP_OUTPUT"
      return "$CLEAN_LOOKUP_STATUS"
    fi
    command git "$@"
  }

  local CLEAN_FAIL_COMMAND CLEAN_LOOKUP_OUTPUT CLEAN_LOOKUP_STATUS
  for CLEAN_FAIL_COMMAND in symbolic-ref rev-parse; do
    # Failed lookups must fail closed even if they print the expected value.
    if [ "$CLEAN_FAIL_COMMAND" = symbolic-ref ]; then
      CLEAN_LOOKUP_OUTPUT=refs/heads/validated-tip
    else
      CLEAN_LOOKUP_OUTPUT="$CLEAN_VALIDATED_TIP"
    fi
    CLEAN_LOOKUP_STATUS=1
    run run_clean_with_errexit --merged --force --yes
    assert_changed_candidate_is_preserved
    rm "$TEST_REPO/hook-order"

    CLEAN_LOOKUP_OUTPUT=""
    CLEAN_LOOKUP_STATUS=0
    run run_clean_with_errexit --closed --force --yes
    assert_changed_candidate_is_preserved
    rm "$TEST_REPO/hook-order"
  done
  [ "$(command git rev-parse refs/heads/validated-tip)" = "$CLEAN_VALIDATED_TIP" ]
}

@test "cmd_clean removes unchanged validated tips and metadata after hooks" {
  local mode
  for mode in --merged --closed; do
    setup_validated_tip_candidate
    git config branch.validated-tip.remote origin
    git config branch.validated-tip.merge refs/heads/validated-tip
    git config gtr.hook.preRemove \
      'test -d "$WORKTREE_PATH" && printf "pre\n" > "$REPO_ROOT/hook-order"'
    git config gtr.hook.postRemove \
      'test ! -d "$WORKTREE_PATH" && ! git show-ref --verify --quiet "refs/heads/$BRANCH" && printf "post\n" >> "$REPO_ROOT/hook-order"'

    run run_clean_with_errexit "$mode" --yes
    [ "$status" -eq 0 ]
    [ ! -d "$TEST_WT_PATH" ]
    ! git show-ref --verify --quiet refs/heads/validated-tip
    ! git config --get-regexp '^branch\.validated-tip\.'
    [ "$(cat "$TEST_REPO/hook-order")" = $'pre\npost' ]
    [[ "$output" == *"Removed: 1, Skipped: 0"* ]]
    [[ "$output" != *"Post-remove hook failed"* ]]
  done
}

assert_cleanup_preserves_racing_tip() {
  setup_validated_tip_candidate
  local new_tip
  new_tip=$(printf "Concurrent work\n" | git commit-tree "$CLEAN_VALIDATED_TIP^{tree}" -p "$CLEAN_VALIDATED_TIP")
  git config gtr.hook.preRemove 'printf "pre\n" > "$REPO_ROOT/hook-order"'
  # Inject the update at the final deletion command, after all validation and
  # worktree removal. Run the actual Git deletion to exercise its atomic check.
  git() {
    local args=" $* "
    case "$args" in
      *" update-ref "*" -d refs/heads/validated-tip "*|*" branch -d validated-tip "*|*" branch -D validated-tip "*)
        command git -C "$TEST_REPO" update-ref refs/heads/validated-tip "$new_tip"
        printf "raced\n" > "$TEST_REPO/race-injected"
        ;;
    esac
    command git "$@"
  }

  run run_clean_with_errexit "$@" --yes
  [ "$status" -eq 0 ]
  [ -e "$TEST_REPO/race-injected" ]
  [ ! -d "$TEST_WT_PATH" ]
  [ "$(command git rev-parse refs/heads/validated-tip)" = "$new_tip" ]
  [ -n "$(command git config branch.validated-tip.description)" ]
  [ "$(cat "$TEST_REPO/hook-order")" = $'pre\npost' ]
  [[ "$output" == *"Kept branch validated-tip"* ]]
}

@test "cmd_clean preserves an update racing the final branch deletion" {
  assert_cleanup_preserves_racing_tip --merged
}

@test "cmd_clean --closed --force cannot bypass the atomic tip check" {
  assert_cleanup_preserves_racing_tip --closed --force
}

@test "cmd_clean keeps a validated branch still checked out in another worktree" {
  setup_validated_tip_candidate
  git worktree add --quiet --force "$TEST_WORKTREES_DIR/still-active" validated-tip
  cd "$TEST_WORKTREES_DIR/still-active"

  run run_clean_with_errexit --merged --force --yes
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_WT_PATH" ]
  [ -d "$TEST_WORKTREES_DIR/still-active" ]
  [ "$(git rev-parse refs/heads/validated-tip)" = "$CLEAN_VALIDATED_TIP" ]
  [ -n "$(git config branch.validated-tip.description)" ]
  [ "$(cat "$TEST_REPO/hook-order")" = post ]
  [[ "$output" == *"Kept branch validated-tip (still checked out"* ]]
}

@test "cmd_clean keeps branch metadata if remaining worktrees cannot be checked" {
  setup_validated_tip_candidate
  git() {
    if [ "$1" = -C ] && [ "$2" = "$TEST_REPO" ] && \
       [ "$3 $4" = "worktree list" ] && [ ! -d "$TEST_WT_PATH" ]; then
      return 1
    fi
    command git "$@"
  }

  run run_clean_with_errexit --closed --force --yes
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_WT_PATH" ]
  [ "$(command git rev-parse refs/heads/validated-tip)" = "$CLEAN_VALIDATED_TIP" ]
  [ -n "$(command git config branch.validated-tip.description)" ]
  [ "$(cat "$TEST_REPO/hook-order")" = post ]
  [[ "$output" == *"Kept branch validated-tip (could not verify remaining worktrees)"* ]]
}

assert_cleanup_preserves_in_progress_branch() {
  local state_file="$1" state_branch="$2" state_path
  setup_validated_tip_candidate
  git worktree add --quiet --detach "$TEST_WORKTREES_DIR/in-progress" "$CLEAN_VALIDATED_TIP"
  # Model Git's branch reservation while HEAD is detached by rebase/bisect.
  state_path=$(git -C "$TEST_WORKTREES_DIR/in-progress" rev-parse --git-path "$state_file")
  mkdir -p "$(dirname "$state_path")"
  printf '%s\n' "$state_branch" > "$state_path"

  run run_clean_with_errexit --merged --force --yes
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_WT_PATH" ]
  [ -d "$TEST_WORKTREES_DIR/in-progress" ]
  [ "$(git rev-parse refs/heads/validated-tip)" = "$CLEAN_VALIDATED_TIP" ]
  [ -n "$(git config branch.validated-tip.description)" ]
  [[ "$output" == *"Kept branch validated-tip (rebase or bisect in progress)"* ]]
}

@test "cmd_clean preserves branch protection during a merge-backend rebase" {
  assert_cleanup_preserves_in_progress_branch rebase-merge/head-name refs/heads/validated-tip
}

@test "cmd_clean preserves branch protection during an apply-backend rebase" {
  assert_cleanup_preserves_in_progress_branch rebase-apply/head-name refs/heads/validated-tip
}

@test "cmd_clean preserves branch protection during bisect" {
  assert_cleanup_preserves_in_progress_branch BISECT_START validated-tip
}

@test "cmd_clean never follows a symbolic branch ref during final deletion" {
  setup_validated_tip_candidate
  git branch other-tip "$CLEAN_VALIDATED_TIP"
  git() {
    case " $* " in
      *" update-ref "*" -d refs/heads/validated-tip "*)
        command git -C "$TEST_REPO" symbolic-ref refs/heads/validated-tip refs/heads/other-tip
        printf "raced\n" > "$TEST_REPO/race-injected"
        ;;
    esac
    command git "$@"
  }

  run run_clean_with_errexit --merged --force --yes
  [ "$status" -eq 0 ]
  [ -e "$TEST_REPO/race-injected" ]
  [ ! -d "$TEST_WT_PATH" ]
  [ "$(command git rev-parse refs/heads/other-tip)" = "$CLEAN_VALIDATED_TIP" ]
}

# Fail only the candidate's tip lookup; all other Git operations remain real.
setup_unresolved_tip_candidate() {
  create_test_worktree "unresolved-tip"
  CLEAN_TIP_STATUS=1
  CLEAN_TIP_OUTPUT=""
  git() {
    if [ "$1" = "-C" ] && [ "$2" = "$TEST_WORKTREES_DIR/unresolved-tip" ] && \
       [ "$3" = "rev-parse" ]; then
      printf "%s" "$CLEAN_TIP_OUTPUT"
      return "$CLEAN_TIP_STATUS"
    fi
    case "$1 $2" in
      "worktree remove"|"branch -d"|"branch -D")
        printf "%s\n" "$*" >> "$TEST_REPO/removal-calls"
        ;;
    esac
    command git "$@"
  }
  _clean_detect_provider() { printf "github"; }
  ensure_provider_cli() { return 0; }
  # An old PR/MR would authorize removal if cleanup reached the provider.
  check_branch_merged() { printf "%s\n" "$2" >> "$TEST_REPO/provider-calls"; }
  check_branch_closed() { printf "%s\n" "$2" >> "$TEST_REPO/provider-calls"; }
}

run_clean_with_errexit() {
  set -e
  cmd_clean "$@"
}

assert_unresolved_tip_is_preserved() {
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_REPO/provider-calls" ]
  [ ! -e "$TEST_REPO/removal-calls" ]
  [ -d "$TEST_WORKTREES_DIR/unresolved-tip" ]
  command git show-ref --verify --quiet refs/heads/unresolved-tip
  [[ "$output" == *"Skipping unresolved-tip (could not resolve HEAD to a commit"* ]]
  [[ "$output" == *"Skipped: 1"* ]]
}

@test "cmd_clean skips failed tip lookups before merged or closed provider authorization" {
  setup_unresolved_tip_candidate

  local mode
  for mode in --merged --closed; do
    run run_clean_with_errexit "$mode" --yes
    assert_unresolved_tip_is_preserved

    run run_clean_with_errexit "$mode" --force --yes
    assert_unresolved_tip_is_preserved
  done

  run run_clean_with_errexit --merged --closed --force --yes --dry-run
  assert_unresolved_tip_is_preserved
  [[ "$output" != *"Would remove: unresolved-tip"* ]]
}

@test "cmd_clean rejects failed tip lookups even when Git prints a commit" {
  setup_unresolved_tip_candidate
  CLEAN_TIP_OUTPUT=$(command git rev-parse HEAD)

  run run_clean_with_errexit --merged --closed --force --yes
  assert_unresolved_tip_is_preserved
}

@test "cmd_clean rejects an empty tip even when lookup succeeds" {
  setup_unresolved_tip_candidate
  CLEAN_TIP_STATUS=0

  run run_clean_with_errexit --merged --closed --force --yes
  assert_unresolved_tip_is_preserved
}

@test "cmd_clean requires HEAD to resolve to a commit object" {
  setup_unresolved_tip_candidate
  unset -f git
  local blob_tip
  blob_tip=$(printf "not a commit\n" | git hash-object -w --stdin)
  # Simulate a damaged branch ref: plain rev-parse HEAD still succeeds.
  printf "%s\n" "$blob_tip" > "$TEST_REPO/.git/refs/heads/unresolved-tip"
  [ "$(git -C "$TEST_WORKTREES_DIR/unresolved-tip" rev-parse HEAD)" = "$blob_tip" ]

  run run_clean_with_errexit --merged --closed --force --yes
  assert_unresolved_tip_is_preserved
}

@test "cmd_clean continues removing valid candidates after a failed tip lookup" {
  setup_unresolved_tip_candidate
  create_test_worktree "valid-tip"
  local branch_tip
  branch_tip=$(git -C "$TEST_WORKTREES_DIR/valid-tip" rev-parse HEAD)
  check_branch_merged() {
    printf "%s\n" "$2" >> "$TEST_REPO/provider-calls"
    [ "$2" = "valid-tip" ] && [ "$4" = "$branch_tip" ]
  }

  run run_clean_with_errexit --merged --force --yes
  [ "$status" -eq 0 ]
  [ "$(cat "$TEST_REPO/provider-calls")" = "valid-tip" ]
  [ -d "$TEST_WORKTREES_DIR/unresolved-tip" ]
  command git show-ref --verify --quiet refs/heads/unresolved-tip
  [ ! -d "$TEST_WORKTREES_DIR/valid-tip" ]
  ! command git show-ref --verify --quiet refs/heads/valid-tip
  [[ "$output" == *"Removed: 1, Skipped: 1"* ]]
}

@test "cmd_clean skips dirty worktree before provider lookup" {
  create_test_worktree "dirty-before-provider"
  echo "dirty" > "$TEST_WORKTREES_DIR/dirty-before-provider/dirty.txt"
  git -C "$TEST_WORKTREES_DIR/dirty-before-provider" add dirty.txt

  _clean_detect_provider() { printf "github"; }
  ensure_provider_cli() { return 0; }
  check_branch_merged() { printf "provider lookup should not run"; return 1; }

  run cmd_clean --merged --to main --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"dirty-before-provider"* ]]
  [[ "$output" != *"provider lookup should not run"* ]]
}

# Exercise the real provider predicate and branch deletion in disposable repos.
# Usage: assert_gitlab_cleanup <merged|closed> <jq|no-jq>
# Creates eligible and ineligible MR fixtures, runs cleanup with errexit, and
# asserts that only the requested unambiguous state loses its worktree and branch.
assert_gitlab_cleanup() {
  local requested_state="$1" parser="$2" branch tip
  for branch in merged-tip closed-tip opened-tip mixed-tip unknown-tip duplicate-tip; do
    create_test_worktree "$branch"
  done
  tip=$(git rev-parse HEAD)

  _clean_detect_provider() { printf "gitlab"; }
  ensure_provider_cli() { return 0; }
  # Emit a response for the requested source branch, including adversarial states.
  glab() {
    case "$4" in
      merged-tip) printf '[{"state":"merged","sha":"%s"}]' "$tip" ;;
      closed-tip) printf '[{"state":"closed","sha":"%s"}]' "$tip" ;;
      opened-tip) printf '[{"state":"opened","sha":"%s"}]' "$tip" ;;
      mixed-tip)
        printf '[{"state":"%s","sha":"old123"},{"state":"opened","sha":"%s"}]' \
          "$requested_state" "$tip"
        ;;
      unknown-tip) printf '[{"sha":"%s"}]' "$tip" ;;
      duplicate-tip)
        printf '[{"state":"opened","state":"%s","sha":"%s"}]' "$requested_state" "$tip"
        ;;
      *) return 1 ;;
    esac
  }
  clean_with_errexit() { set -e; cmd_clean "$@"; }

  if [ "$parser" = jq ]; then
    run clean_with_errexit "--$requested_state" --yes
  else
    run without_jq clean_with_errexit "--$requested_state" --yes
  fi
  [ "$status" -eq 0 ]
  for branch in merged-tip closed-tip opened-tip mixed-tip unknown-tip duplicate-tip; do
    if [ "$branch" = "$requested_state-tip" ]; then
      [ ! -d "$TEST_WORKTREES_DIR/$branch" ]
      ! git show-ref --verify --quiet "refs/heads/$branch"
    else
      [ -d "$TEST_WORKTREES_DIR/$branch" ]
      git show-ref --verify --quiet "refs/heads/$branch"
    fi
  done
}

@test "GitLab merged cleanup removes only a merged MR at the current tip with jq" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  assert_gitlab_cleanup merged jq
}

@test "GitLab closed cleanup removes only a closed MR at the current tip with jq" {
  command -v jq >/dev/null 2>&1 || skip "jq not installed"
  assert_gitlab_cleanup closed jq
}

@test "GitLab merged cleanup preserves open and mismatched MRs without jq" {
  assert_gitlab_cleanup merged no-jq
}

@test "GitLab closed cleanup preserves open and mismatched MRs without jq" {
  assert_gitlab_cleanup closed no-jq
}

# ── Locked entries with missing directories (#180) ──────────────────────────

# Create a locked worktree whose directory has been deleted out from under git
# Usage: create_locked_phantom <branch>
create_locked_phantom() {
  local branch="$1"
  create_test_worktree "$branch"
  git -C "$TEST_REPO" worktree lock "$TEST_WORKTREES_DIR/$branch"
  rm -rf "$TEST_WORKTREES_DIR/$branch"
}

@test "cmd_clean surfaces recovery hint for locked missing worktree when declined" {
  create_locked_phantom "phantom-hint"

  run cmd_clean < /dev/null
  [ "$status" -eq 0 ]
  [[ "$output" == *"Locked worktree entry with missing directory"* ]]
  [[ "$output" == *"git worktree unlock"* ]]
  # Entry stays registered without confirmation
  git -C "$TEST_REPO" worktree list --porcelain | grep -q "phantom-hint"
}

@test "cmd_clean --force unlocks and prunes locked missing worktree" {
  create_locked_phantom "phantom-force"

  run cmd_clean --force
  [ "$status" -eq 0 ]
  ! git -C "$TEST_REPO" worktree list --porcelain | grep -q "phantom-force"
  # Branch is no longer held by the phantom worktree
  git -C "$TEST_REPO" branch -D phantom-force
}

@test "cmd_clean --yes unlocks and prunes locked missing worktree" {
  create_locked_phantom "phantom-yes"

  run cmd_clean --yes
  [ "$status" -eq 0 ]
  ! git -C "$TEST_REPO" worktree list --porcelain | grep -q "phantom-yes"
}

@test "cmd_clean --dry-run reports locked missing worktree without changes" {
  create_locked_phantom "phantom-dry"

  run cmd_clean --dry-run --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"[dry-run] Would unlock and prune"* ]]
  git -C "$TEST_REPO" worktree list --porcelain | grep -q "phantom-dry"
}

@test "cmd_clean --force keeps locked worktree whose directory exists" {
  create_test_worktree "locked-alive"
  git -C "$TEST_REPO" worktree lock "$TEST_WORKTREES_DIR/locked-alive"

  run cmd_clean --force --yes
  [ "$status" -eq 0 ]
  [ -d "$TEST_WORKTREES_DIR/locked-alive" ]
  git -C "$TEST_REPO" worktree list --porcelain | grep -q "locked-alive"
}

@test "cmd_clean --merged recovers locked missing worktree before merged pass" {
  create_locked_phantom "phantom-merged"

  _clean_detect_provider() { printf "github"; }
  ensure_provider_cli() { return 0; }
  check_branch_merged() { return 1; }

  run cmd_clean --merged --force --yes
  [ "$status" -eq 0 ]
  ! git -C "$TEST_REPO" worktree list --porcelain | grep -q "phantom-merged"
}

@test "cmd_clean --merged --force skips the current active worktree" {
  create_test_worktree "active-merged"
  cd "$TEST_WORKTREES_DIR/active-merged" || false
  echo "dirty" > dirty.txt
  git add dirty.txt

  _clean_detect_provider() { printf "github"; }
  ensure_provider_cli() { return 0; }
  check_branch_merged() { [ "$2" = "active-merged" ] && [ -z "$3" ]; }
  run_hooks_in() { return 0; }
  run_hooks() { return 0; }

  run cmd_clean --merged --force --yes
  [ "$status" -eq 0 ]
  [ -d "$TEST_WORKTREES_DIR/active-merged" ]
}
