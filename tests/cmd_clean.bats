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

@test "cmd_clean rejects --to without --merged" {
  run cmd_clean --to main
  [ "$status" -eq 1 ]
  [[ "$output" == *"--to can only be used with --merged"* ]]
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

@test "cmd_clean does not log dirty skip for non-merged worktree" {
  create_test_worktree "dirty-not-merged"
  echo "dirty" > "$TEST_WORKTREES_DIR/dirty-not-merged/dirty.txt"
  git -C "$TEST_WORKTREES_DIR/dirty-not-merged" add dirty.txt

  _clean_detect_provider() { printf "github"; }
  ensure_provider_cli() { return 0; }
  check_branch_merged() { return 1; }

  run cmd_clean --merged --to main --yes
  [ "$status" -eq 0 ]
  [[ "$output" != *"dirty-not-merged"* ]]
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
