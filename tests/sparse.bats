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
  git -C "$TEST_REPO" tag base

  result=$(_worktree_path_for_ref base)
  [ -z "$result" ]

  for ref in heads/base refs/heads/base; do
    result=$(_worktree_path_for_ref "$ref")
    [ "$result" = "$TEST_WORKTREES_DIR/base" ]
  done
}

@test "_worktree_path_for_ref matches remote-prefixed refs by short name" {
  make_sparse_worktree "$TEST_WORKTREES_DIR/base" base apps/web
  result=$(_worktree_path_for_ref origin/base)
  [ "$result" = "$TEST_WORKTREES_DIR/base" ]

  git -C "$TEST_REPO" update-ref refs/remotes/origin/base HEAD
  for ref in remotes/origin/base refs/remotes/origin/base; do
    result=$(_worktree_path_for_ref "$ref")
    [ "$result" = "$TEST_WORKTREES_DIR/base" ]
  done

  make_sparse_worktree "$TEST_WORKTREES_DIR/literal-remote" remotes/origin/base docs
  result=$(_worktree_path_for_ref remotes/origin/base)
  [ -z "$result" ]
  result=$(_worktree_path_for_ref refs/remotes/origin/base)
  [ "$result" = "$TEST_WORKTREES_DIR/base" ]
}

@test "_worktree_path_for_ref follows Git namespace shorthand resolution" {
  make_sparse_worktree "$TEST_WORKTREES_DIR/heads-literal" heads/only apps/web
  make_sparse_worktree "$TEST_WORKTREES_DIR/tags-literal" tags/only docs

  result=$(_worktree_path_for_ref heads/only)
  [ "$result" = "$TEST_WORKTREES_DIR/heads-literal" ]
  result=$(_worktree_path_for_ref tags/only)
  [ "$result" = "$TEST_WORKTREES_DIR/tags-literal" ]
}

@test "_worktree_path_for_ref preserves slash branch path after remote name" {
  make_sparse_worktree "$TEST_WORKTREES_DIR/auth" feature/user-auth apps/web
  result=$(_worktree_path_for_ref origin/feature/user-auth)
  [ "$result" = "$TEST_WORKTREES_DIR/auth" ]
}

@test "_worktree_path_for_ref uses the longest configured remote prefix" {
  git -C "$TEST_REPO" config gtr.defaultRemote team
  git -C "$TEST_REPO" remote add team/upstream https://example.com/upstream.git
  make_sparse_worktree "$TEST_WORKTREES_DIR/auth" feature/user-auth apps/web

  result=$(_worktree_path_for_ref team/upstream/feature/user-auth)
  [ "$result" = "$TEST_WORKTREES_DIR/auth" ]
}

@test "_worktree_path_for_ref does not shorten an exact local slash ref" {
  git -C "$TEST_REPO" branch feature/user-auth
  make_sparse_worktree "$TEST_WORKTREES_DIR/short" user-auth apps/web

  result=$(_worktree_path_for_ref feature/user-auth)
  [ -z "$result" ]
}

@test "_worktree_path_for_ref does not reinterpret an exact branch or tag as remote" {
  make_sparse_worktree "$TEST_WORKTREES_DIR/short" foo apps/web
  git -C "$TEST_REPO" branch origin/foo

  result=$(_worktree_path_for_ref origin/foo)
  [ -z "$result" ]

  git -C "$TEST_REPO" branch -D origin/foo >/dev/null
  git -C "$TEST_REPO" tag origin/foo
  result=$(_worktree_path_for_ref origin/foo)
  [ -z "$result" ]
}

@test "_resolve_sparse_source refuses an ambiguous duplicate branch" {
  make_sparse_worktree "$TEST_WORKTREES_DIR/shared-one" shared apps/web
  git -C "$TEST_REPO" worktree add --force --quiet "$TEST_WORKTREES_DIR/shared-two" shared
  git -C "$TEST_WORKTREES_DIR/shared-two" sparse-checkout set docs >/dev/null

  run _worktree_path_for_ref shared
  [ "$status" -eq 2 ]
  [[ "$output" == *"source is ambiguous"* ]]

  result=$(_resolve_sparse_source shared)
  [ -z "$result" ]
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

@test "cmd_create inherits a cone from the base worktree" {
  source_gtr_commands
  make_sparse_worktree "$TEST_WORKTREES_DIR/base" base apps/web packages

  run cmd_create feat --from base --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]

  wt="$TEST_WORKTREES_DIR/feat"
  # Config replicated
  [ "$(git -C "$wt" config --bool core.sparseCheckout)" = "true" ]
  [ "$(git -C "$wt" config --bool core.sparseCheckoutCone)" = "true" ]

  # Pattern list matches the source
  src_list=$(git -C "$TEST_WORKTREES_DIR/base" sparse-checkout list)
  new_list=$(git -C "$wt" sparse-checkout list)
  [ "$src_list" = "$new_list" ]

  # Working tree narrowed: cone dirs present, excluded dirs absent
  [ -d "$wt/apps/web" ]
  [ -d "$wt/packages" ]
  [ ! -d "$wt/apps/api" ]
  [ ! -d "$wt/docs" ]
}

@test "cmd_create uses a shorthand base ref's sparse worktree" {
  source_gtr_commands
  git -C "$TEST_REPO" sparse-checkout init --cone >/dev/null
  git -C "$TEST_REPO" sparse-checkout set apps/api >/dev/null
  make_sparse_worktree "$TEST_WORKTREES_DIR/base source" base docs
  git -C "$TEST_WORKTREES_DIR/base source" commit --allow-empty -m "advance base" --quiet

  run cmd_create feat-heads --from heads/base --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]

  wt="$TEST_WORKTREES_DIR/feat-heads"
  [ "$(git -C "$wt" rev-parse HEAD)" = "$(git -C "$TEST_WORKTREES_DIR/base source" rev-parse HEAD)" ]
  [ "$(git -C "$wt" sparse-checkout list)" = "docs" ]
  [ -d "$wt/docs" ]
  [ ! -d "$wt/apps/api" ]
  [[ "$output" == *"Inherited sparse-checkout from $TEST_WORKTREES_DIR/base source"* ]]
}

@test "cmd_create keeps tag start points separate from same-named branch settings" {
  source_gtr_commands
  git -C "$TEST_REPO" sparse-checkout init --cone >/dev/null
  git -C "$TEST_REPO" sparse-checkout set apps/api >/dev/null
  make_sparse_worktree "$TEST_WORKTREES_DIR/base" base docs
  git -C "$TEST_WORKTREES_DIR/base" commit --allow-empty -m "advance base" --quiet
  git -C "$TEST_REPO" tag base HEAD

  run cmd_create feat-tag --from base --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]

  wt="$TEST_WORKTREES_DIR/feat-tag"
  [ "$(git -C "$wt" rev-parse HEAD)" = "$(git -C "$TEST_REPO" rev-parse 'refs/tags/base^{commit}')" ]
  [ "$(git -C "$wt" sparse-checkout list)" = "apps/api" ]
  [ -d "$wt/apps/api" ]
  [ ! -d "$wt/docs" ]
  [[ "$output" == *"Inherited sparse-checkout from $TEST_REPO"* ]]
}

@test "cmd_create inherits a dash-prefixed cone directory" {
  source_gtr_commands
  mkdir -p "$TEST_REPO/-app"
  echo dash > "$TEST_REPO/-app/file.txt"
  git -C "$TEST_REPO" add -A
  git -C "$TEST_REPO" commit -m "add dash-prefixed directory" --quiet

  make_sparse_worktree "$TEST_WORKTREES_DIR/base" base -- -app

  run cmd_create feat --from base --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]
  [ -f "$TEST_WORKTREES_DIR/feat/-app/file.txt" ]
  [ ! -d "$TEST_WORKTREES_DIR/feat/apps" ]
}

@test "cmd_create preserves sparse-index mode" {
  source_gtr_commands
  git -C "$TEST_REPO" worktree add --quiet -b base "$TEST_WORKTREES_DIR/base" HEAD
  if ! git -C "$TEST_WORKTREES_DIR/base" sparse-checkout init --cone --sparse-index >/dev/null 2>&1; then
    skip "git does not support sparse-index mode"
  fi
  git -C "$TEST_WORKTREES_DIR/base" sparse-checkout set apps/web packages >/dev/null
  if [ "$(git -C "$TEST_WORKTREES_DIR/base" config --bool index.sparse 2>/dev/null || true)" != "true" ]; then
    skip "git did not enable sparse-index mode"
  fi

  run cmd_create feat --from base --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]
  [ "$(git -C "$TEST_WORKTREES_DIR/feat" config --bool index.sparse)" = "true" ]
  [ -d "$TEST_WORKTREES_DIR/feat/apps/web" ]
  [ ! -d "$TEST_WORKTREES_DIR/feat/apps/api" ]
}

@test "cmd_create inherits non-cone patterns" {
  source_gtr_commands
  # Source uses non-cone (raw pattern) sparse-checkout.
  git -C "$TEST_REPO" worktree add --quiet -b base "$TEST_WORKTREES_DIR/base" HEAD
  git -C "$TEST_WORKTREES_DIR/base" sparse-checkout init --no-cone >/dev/null
  git -C "$TEST_WORKTREES_DIR/base" sparse-checkout set "/apps/web/" "/docs/" >/dev/null

  run cmd_create feat --from base --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]

  # Sparse enabled, but cone mode stays off (raw patterns, not cone dirs)
  [ "$(git -C "$TEST_WORKTREES_DIR/feat" config --bool core.sparseCheckout)" = "true" ]
  [ "$(git -C "$TEST_WORKTREES_DIR/feat" config --bool core.sparseCheckoutCone 2>/dev/null || echo false)" != "true" ]

  # Raw pattern list matches the source (applied via set --stdin)
  src_list=$(git -C "$TEST_WORKTREES_DIR/base" sparse-checkout list)
  new_list=$(git -C "$TEST_WORKTREES_DIR/feat" sparse-checkout list)
  [ "$src_list" = "$new_list" ]

  # Working tree narrowed to the pattern dirs
  [ -d "$TEST_WORKTREES_DIR/feat/apps/web" ]
  [ -d "$TEST_WORKTREES_DIR/feat/docs" ]
  [ ! -d "$TEST_WORKTREES_DIR/feat/apps/api" ]
  [ ! -d "$TEST_WORKTREES_DIR/feat/packages" ]
}

@test "cmd_create falls back to a full checkout when source patterns are missing" {
  source_gtr_commands
  git -C "$TEST_REPO" worktree add --quiet -b base "$TEST_WORKTREES_DIR/base" HEAD
  git -C "$TEST_WORKTREES_DIR/base" sparse-checkout init --no-cone >/dev/null
  git -C "$TEST_WORKTREES_DIR/base" sparse-checkout set "/apps/web/" >/dev/null

  pattern_file=$(git -C "$TEST_WORKTREES_DIR/base" rev-parse --git-path info/sparse-checkout)
  rm -f "$pattern_file"

  run cmd_create feat-missing-patterns --from base --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]
  [[ "$output" != *"Inherited sparse-checkout"* ]]
  [[ "$output" == *"falling back to a full checkout"* ]]

  wt="$TEST_WORKTREES_DIR/feat-missing-patterns"
  [ -d "$wt/apps/web" ]
  [ -d "$wt/apps/api" ]
  [ -d "$wt/docs" ]
  [ "$(git -C "$wt" config --bool core.sparseCheckout 2>/dev/null || echo false)" != "true" ]
}

@test "cmd_create does not replace a broken base with the current sparse worktree" {
  source_gtr_commands
  git -C "$TEST_REPO" sparse-checkout init --cone >/dev/null
  git -C "$TEST_REPO" sparse-checkout set apps/web >/dev/null
  git -C "$TEST_REPO" worktree add --quiet -b broken "$TEST_WORKTREES_DIR/broken" HEAD
  git -C "$TEST_WORKTREES_DIR/broken" sparse-checkout set docs >/dev/null

  pattern_file=$(git -C "$TEST_WORKTREES_DIR/broken" rev-parse --git-path info/sparse-checkout)
  rm -f "$pattern_file"

  run cmd_create feat-broken --from broken --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]
  [[ "$output" != *"Inherited sparse-checkout"* ]]
  [[ "$output" == *"falling back to a full checkout"* ]]

  wt="$TEST_WORKTREES_DIR/feat-broken"
  [ -d "$wt/apps/web" ]
  [ -d "$wt/apps/api" ]
  [ -d "$wt/docs" ]
  [ "$(git -C "$wt" config --bool core.sparseCheckout 2>/dev/null || echo false)" != "true" ]
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

@test "cmd_create --no-sparse from the current sparse worktree creates a dense checkout" {
  source_gtr_commands
  git -C "$TEST_REPO" sparse-checkout init --cone >/dev/null
  git -C "$TEST_REPO" sparse-checkout set apps/web >/dev/null

  run cmd_create feat-current-full --from-current --no-sparse --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]

  wt="$TEST_WORKTREES_DIR/feat-current-full"
  [ -d "$wt/apps/web" ]
  [ -d "$wt/apps/api" ]
  [ -d "$wt/docs" ]
  [ "$(git -C "$wt" config --bool core.sparseCheckout 2>/dev/null || echo false)" != "true" ]
}

@test "cmd_create respects gtr.sparse.inherit=false (no inheritance)" {
  source_gtr_commands
  git -C "$TEST_REPO" config gtr.sparse.inherit false
  make_sparse_worktree "$TEST_WORKTREES_DIR/base" base apps/web

  run cmd_create feat-cfg --from base --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]

  wt="$TEST_WORKTREES_DIR/feat-cfg"
  # Inheritance disabled by config: full checkout, sparse not enabled
  [ -d "$wt/apps/api" ]
  [ -d "$wt/docs" ]
  [ "$(git -C "$wt" config --bool core.sparseCheckout 2>/dev/null || echo false)" != "true" ]
}

@test "cmd_create respects sparse.inherit=false from .gtrconfig" {
  source_gtr_commands
  git -C "$TEST_REPO" config -f "$TEST_REPO/.gtrconfig" sparse.inherit false
  git -C "$TEST_REPO" sparse-checkout init --cone >/dev/null
  git -C "$TEST_REPO" sparse-checkout set apps/web >/dev/null

  run cmd_create feat-file-cfg --from-current --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]

  wt="$TEST_WORKTREES_DIR/feat-file-cfg"
  [ -d "$wt/apps/web" ]
  [ -d "$wt/apps/api" ]
  [ -d "$wt/docs" ]
  [ "$(git -C "$wt" config --bool core.sparseCheckout 2>/dev/null || echo false)" != "true" ]
}

@test "worktree-local sparse config overrides .gtrconfig" {
  source_gtr_commands
  git -C "$TEST_REPO" sparse-checkout init --cone >/dev/null
  git -C "$TEST_REPO" sparse-checkout set apps/web >/dev/null
  git -C "$TEST_REPO" config -f "$TEST_REPO/.gtrconfig" sparse.inherit true
  git -C "$TEST_REPO" config --worktree gtr.sparse.inherit false

  run cmd_create feat-worktree-cfg --from-current --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]

  wt="$TEST_WORKTREES_DIR/feat-worktree-cfg"
  [ -d "$wt/apps/web" ]
  [ -d "$wt/apps/api" ]
  [ -d "$wt/docs" ]
  [ "$(git -C "$wt" config --bool core.sparseCheckout 2>/dev/null || echo false)" != "true" ]
}

@test "cmd_create --sparse overrides gtr.sparse.inherit=false" {
  source_gtr_commands
  git -C "$TEST_REPO" config gtr.sparse.inherit false
  make_sparse_worktree "$TEST_WORKTREES_DIR/base" base apps/web

  run cmd_create feat-override --from base --sparse --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]

  wt="$TEST_WORKTREES_DIR/feat-override"
  # --sparse beats the config: sparse inherited from the base worktree
  [ "$(git -C "$wt" config --bool core.sparseCheckout)" = "true" ]
  [ -d "$wt/apps/web" ]
  [ ! -d "$wt/apps/api" ]
  [ ! -d "$wt/docs" ]
}

@test "cmd_create --sparse falls back to dense when Git lacks native inheritance" {
  source_gtr_commands
  make_sparse_worktree "$TEST_WORKTREES_DIR/base" base apps/web
  _git_supports_sparse_inheritance() { return 1; }

  run cmd_create feat-old-git --from base --sparse --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]
  [[ "$output" == *"requires Git 2.36+"* ]]

  wt="$TEST_WORKTREES_DIR/feat-old-git"
  [ -d "$wt/apps/web" ]
  [ -d "$wt/apps/api" ]
  [ -d "$wt/docs" ]
  [ "$(git -C "$wt" config --bool core.sparseCheckout 2>/dev/null || echo false)" != "true" ]
}

@test "cmd_create skips sparse config lookup when Git cannot inherit" {
  source_gtr_commands
  make_sparse_worktree "$TEST_WORKTREES_DIR/base" base apps/web
  _git_supports_sparse_inheritance() { return 1; }
  cfg_bool() {
    printf "unexpected cfg_bool call\n" >&2
    return 1
  }

  run cmd_create feat-old-default --from base --yes --no-fetch --no-hooks --no-copy
  [ "$status" -eq 0 ]
  [[ "$output" != *"unexpected cfg_bool call"* ]]
  [ -d "$TEST_WORKTREES_DIR/feat-old-default/apps/api" ]
}

@test "_git_version_at_least parses vendor-suffixed versions" {
  git() {
    [ "$1" = "--version" ] || return 1
    printf "git version 2.36.6 (Vendor Git-1)\n"
  }

  _git_version_at_least 2 36
  run _git_version_at_least 2 37
  [ "$status" -eq 1 ]
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
