#!/usr/bin/env bats
# Tests for cmd_rename in lib/commands/rename.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
}

teardown() {
  teardown_integration_repo
}

# Exercise the printed command as shell input without ever invoking a real push.
assert_rename_push_suggestion() {
  local old_branch="$1" new_branch="$2" rename_command="${3:-mv}"
  git check-ref-format --branch "$old_branch" >/dev/null
  git check-ref-format --branch "$new_branch" >/dev/null
  create_test_worktree "$old_branch"
  git update-ref "refs/remotes/origin/$old_branch" HEAD

  run "$PROJECT_ROOT/bin/gtr" "$rename_command" "$old_branch" "$new_branch" --yes
  [ "$status" -eq 0 ]
  PUSH_SUGGESTION=$(printf '%s\n' "$output" | sed -n 's/^  \(git push origin .*\)$/\1/p')
  [ -n "$PUSH_SUGGESTION" ]
  git show-ref --verify --quiet "refs/heads/$new_branch"
  ! git show-ref --verify --quiet "refs/heads/$old_branch"
  git show-ref --verify --quiet "refs/remotes/origin/$old_branch"
  [ ! -e rename-old-marker ]
  [ ! -e rename-new-marker ]

  run bash --noprofile --norc -c '
    git() { printf "%s\n" "$#" "$@"; }
    eval "$1"
  ' _ "$PUSH_SUGGESTION"
  [ "$status" -eq 0 ]
  [ ! -e rename-old-marker ]
  [ ! -e rename-new-marker ]
  [ "${#lines[@]}" -eq 5 ]
  [ "${lines[0]}" = 4 ]
  [ "${lines[1]}" = push ]
  [ "${lines[2]}" = origin ]
  [ "${lines[3]}" = ":$old_branch" ]
  [ "${lines[4]}" = "$new_branch" ]
}

# ── Basic rename ─────────────────────────────────────────────────────────────

@test "cmd_rename renames worktree and branch" {
  create_test_worktree "old-name"
  cmd_rename old-name new-name --yes 2>/dev/null
  [ -d "$TEST_WORKTREES_DIR/new-name" ]
  [ ! -d "$TEST_WORKTREES_DIR/old-name" ]
}

@test "cmd_rename updates branch name" {
  create_test_worktree "rename-branch"
  cmd_rename rename-branch renamed-branch --yes 2>/dev/null
  # New branch should exist
  run git -C "$TEST_REPO" show-ref --verify "refs/heads/renamed-branch"
  [ "$status" -eq 0 ]
  # Old branch should not exist
  run git -C "$TEST_REPO" show-ref --verify "refs/heads/rename-branch"
  [ "$status" -ne 0 ]
}

@test "cmd_rename preserves an ordinary folder prefix" {
  git config gtr.worktrees.prefix dev-
  create_worktree "$TEST_WORKTREES_DIR" "dev-" "old-name" "HEAD" "none" "1" >/dev/null

  cmd_rename old-name feature/renamed --yes

  [ -f "$TEST_WORKTREES_DIR/dev-feature-renamed/.git" ]
  [ ! -e "$TEST_WORKTREES_DIR/dev-old-name" ]
  [ "$(get_current_branch "$TEST_WORKTREES_DIR/dev-feature-renamed")" = "feature/renamed" ]
}

@test "cmd_rename rejects traversal prefixes without moving the worktree or renaming its branch" {
  create_test_worktree "old-name"
  local old_path="$TEST_WT_PATH"
  git config gtr.worktrees.dir "$TEST_REPO/prefix-fixture/trees"
  git config -f .gtrconfig worktrees.prefix ../planted-

  run "$PROJECT_ROOT/bin/gtr" mv old-name renamed --yes

  [ "$status" -eq 1 ]
  [[ "$output" == *"Invalid gtr.worktrees.prefix"* ]]
  [ -f "$old_path/.git" ]
  [ "$(get_current_branch "$old_path")" = "old-name" ]
  [ ! -e "$TEST_REPO/prefix-fixture" ]
  ! git show-ref --verify --quiet refs/heads/renamed
}

# ── Remote push suggestion ───────────────────────────────────────────────────

@test "cmd_rename keeps the push suggestion readable for ordinary branch names" {
  assert_rename_push_suggestion old-name feature/new-name
  [ "$PUSH_SUGGESTION" = 'git push origin :old-name feature/new-name' ]
}

@test "cmd_rename push suggestion preserves substitutions in the old branch" {
  assert_rename_push_suggestion 'old$(>rename-old-marker)' new-name
}

@test "cmd_rename push suggestion preserves substitutions in the new branch via rename alias" {
  assert_rename_push_suggestion old-name 'new`>rename-new-marker`' rename
}

@test "cmd_rename push suggestion preserves separators in the old branch" {
  assert_rename_push_suggestion 'old;>rename-old-marker;#' new-name
}

@test "cmd_rename push suggestion preserves separators in the new branch" {
  assert_rename_push_suggestion old-name 'new;>rename-new-marker;#'
}

@test "cmd_rename push suggestion preserves quotes in both branch names" {
  assert_rename_push_suggestion "old'branch" 'new"branch'
}

@test "cmd_rename omits the push suggestion without a remote tracking ref" {
  create_test_worktree old-name

  run "$PROJECT_ROOT/bin/gtr" mv old-name new-name --yes

  [ "$status" -eq 0 ]
  [[ "$output" != *'git push origin'* ]]
}

# ── Error cases ──────────────────────────────────────────────────────────────

@test "cmd_rename fails with insufficient args" {
  run cmd_rename
  [ "$status" -eq 1 ]
}

@test "cmd_rename fails with only one arg" {
  run cmd_rename old-name
  [ "$status" -eq 1 ]
}

@test "cmd_rename cannot rename main repo" {
  run cmd_rename 1 something --yes
  [ "$status" -eq 1 ]
}

@test "cmd_rename fails if target branch already exists" {
  create_test_worktree "src-branch"
  create_test_worktree "dst-branch"
  run cmd_rename src-branch dst-branch --yes
  [ "$status" -eq 1 ]
}

@test "cmd_rename fails if target folder already exists" {
  create_test_worktree "src-wt"
  mkdir -p "$TEST_WORKTREES_DIR/target-wt"
  touch "$TEST_WORKTREES_DIR/target-wt/placeholder"
  run cmd_rename src-wt target-wt --yes
  [ "$status" -eq 1 ]
}

@test "cmd_rename fails for unknown worktree" {
  run cmd_rename nonexistent new-name --yes
  [ "$status" -eq 1 ]
}
