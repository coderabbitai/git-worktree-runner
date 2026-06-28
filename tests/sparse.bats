#!/usr/bin/env bats

# Tests for sparse-checkout inheritance helpers and decision logic.

setup() {
  load test_helper
  source_gtr_libs

  # Disposable repo with a couple of top-level dirs so cone sparse is observable.
  # Canonicalize the path so it matches what `git worktree list` reports
  # (macOS /var is a symlink to /private/var).
  TEST_REPO=$(cd "$(mktemp -d)" && pwd -P)
  git -C "$TEST_REPO" init --quiet
  git -C "$TEST_REPO" config user.name "Test User"
  git -C "$TEST_REPO" config user.email "test@example.com"
  mkdir -p "$TEST_REPO/apps/web" "$TEST_REPO/apps/api" "$TEST_REPO/packages" "$TEST_REPO/docs"
  echo web > "$TEST_REPO/apps/web/file.txt"
  echo api > "$TEST_REPO/apps/api/file.txt"
  echo pkg > "$TEST_REPO/packages/file.txt"
  echo doc > "$TEST_REPO/docs/file.txt"
  git -C "$TEST_REPO" add -A
  git -C "$TEST_REPO" commit -m init --quiet

  TEST_WORKTREES_DIR="${TEST_REPO}-worktrees"
  cd "$TEST_REPO" || return 1
}

teardown() {
  cd / 2>/dev/null || true
  if [ -d "$TEST_REPO" ]; then
    git -C "$TEST_REPO" worktree list --porcelain 2>/dev/null | while IFS= read -r line; do
      case "$line" in
        "worktree "*)
          wt="${line#worktree }"
          [ "$wt" = "$TEST_REPO" ] && continue
          git -C "$TEST_REPO" worktree remove --force "$wt" 2>/dev/null || true
          ;;
      esac
    done
  fi
  rm -rf "$TEST_REPO" "$TEST_WORKTREES_DIR"
}

# Create a cone-sparse worktree on a branch checking out only the given dirs.
# Usage: make_sparse_worktree <path> <branch> <dir>...
make_sparse_worktree() {
  local path="$1" branch="$2"
  shift 2
  git -C "$TEST_REPO" worktree add --quiet -b "$branch" "$path" HEAD
  git -C "$path" sparse-checkout init --cone >/dev/null
  git -C "$path" sparse-checkout set "$@" >/dev/null
}

@test "_worktree_path_for_ref finds the worktree holding a branch" {
  make_sparse_worktree "$TEST_WORKTREES_DIR/base" base apps/web packages
  result=$(_worktree_path_for_ref base)
  [ "$result" = "$TEST_WORKTREES_DIR/base" ]
}

@test "_worktree_path_for_ref matches remote-prefixed refs by short name" {
  make_sparse_worktree "$TEST_WORKTREES_DIR/base" base apps/web
  result=$(_worktree_path_for_ref origin/base)
  [ "$result" = "$TEST_WORKTREES_DIR/base" ]
}

@test "_worktree_path_for_ref returns empty for unknown refs" {
  result=$(_worktree_path_for_ref does-not-exist)
  [ -z "$result" ]
}

@test "_resolve_sparse_source returns the base worktree when it is sparse" {
  make_sparse_worktree "$TEST_WORKTREES_DIR/base" base apps/web packages
  result=$(_resolve_sparse_source base)
  [ "$result" = "$TEST_WORKTREES_DIR/base" ]
}

@test "_resolve_sparse_source returns empty when base is not sparse" {
  git -C "$TEST_REPO" worktree add --quiet -b plain "$TEST_WORKTREES_DIR/plain" HEAD
  result=$(_resolve_sparse_source plain)
  [ -z "$result" ]
}

@test "_resolve_sparse_source falls back to current worktree" {
  # No worktree holds 'origin/main'; cwd (main repo) is sparse
  git -C "$TEST_REPO" sparse-checkout init --cone >/dev/null
  git -C "$TEST_REPO" sparse-checkout set apps/web >/dev/null
  result=$(_resolve_sparse_source origin/main)
  [ "$result" = "$TEST_REPO" ]
  # restore full checkout for teardown safety
  git -C "$TEST_REPO" sparse-checkout disable >/dev/null
}

@test "apply_inherited_sparse replicates a cone into a new worktree" {
  make_sparse_worktree "$TEST_WORKTREES_DIR/base" base apps/web packages
  git -C "$TEST_REPO" worktree add --no-checkout --quiet -b feat "$TEST_WORKTREES_DIR/feat" base

  run apply_inherited_sparse "$TEST_WORKTREES_DIR/feat" "$TEST_WORKTREES_DIR/base"
  [ "$status" -eq 0 ]

  # Config replicated
  [ "$(git -C "$TEST_WORKTREES_DIR/feat" config --bool core.sparseCheckout)" = "true" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/feat" config --bool core.sparseCheckoutCone)" = "true" ]

  # Pattern list matches the source
  src_list=$(git -C "$TEST_WORKTREES_DIR/base" sparse-checkout list)
  new_list=$(git -C "$TEST_WORKTREES_DIR/feat" sparse-checkout list)
  [ "$src_list" = "$new_list" ]

  # Working tree narrowed: cone dirs present, excluded dirs absent
  [ -d "$TEST_WORKTREES_DIR/feat/apps/web" ]
  [ -d "$TEST_WORKTREES_DIR/feat/packages" ]
  [ ! -d "$TEST_WORKTREES_DIR/feat/apps/api" ]
  [ ! -d "$TEST_WORKTREES_DIR/feat/docs" ]
}

@test "cmd_create inherits sparse-checkout from --from base worktree" {
  source_gtr_commands
  make_sparse_worktree "$TEST_WORKTREES_DIR/base" base apps/web packages

  run cmd_create feat-xyz --from base --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]

  wt="$TEST_WORKTREES_DIR/feat-xyz"
  [ "$(git -C "$wt" config --bool core.sparseCheckout)" = "true" ]
  [ -d "$wt/apps/web" ]
  [ ! -d "$wt/apps/api" ]
  [ ! -d "$wt/docs" ]
}

@test "cmd_create --no-sparse forces a full checkout" {
  source_gtr_commands
  make_sparse_worktree "$TEST_WORKTREES_DIR/base" base apps/web

  run cmd_create feat-full --from base --no-sparse --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]

  wt="$TEST_WORKTREES_DIR/feat-full"
  # Full checkout: everything present, sparse not enabled
  [ -d "$wt/apps/api" ]
  [ -d "$wt/docs" ]
  [ "$(git -C "$wt" config --bool core.sparseCheckout 2>/dev/null || echo false)" != "true" ]
}

@test "cmd_create with non-sparse base produces a full checkout" {
  source_gtr_commands
  git -C "$TEST_REPO" worktree add --quiet -b plain "$TEST_WORKTREES_DIR/plain" HEAD

  run cmd_create feat-plain --from plain --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]

  wt="$TEST_WORKTREES_DIR/feat-plain"
  [ -d "$wt/apps/api" ]
  [ -d "$wt/docs" ]
}
