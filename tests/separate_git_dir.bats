#!/usr/bin/env bats
# Main-checkout discovery when the Git directory lives outside the checkout.

load test_helper

setup() {
  TEST_FIXTURE=$(cd -P "$(mktemp -d)" && pwd)
  TEST_MAIN="$TEST_FIXTURE/main checkout"
  TEST_METADATA="$TEST_FIXTURE/metadata/store"
  TEST_LINKED="$TEST_FIXTURE/linked checkout"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  export XDG_CONFIG_HOME="$TEST_FIXTURE/user-config"
  export XDG_CACHE_HOME="$TEST_FIXTURE/cache"
  export GIT_TEMPLATE_DIR="$TEST_FIXTURE/template"
  mkdir -p "$TEST_FIXTURE/metadata" "$GIT_TEMPLATE_DIR"
  git init --quiet --separate-git-dir="$TEST_METADATA" "$TEST_MAIN"
  git -C "$TEST_MAIN" -c user.name=Test -c user.email=test@example.com \
    commit --allow-empty -m init --quiet
  git -C "$TEST_MAIN" worktree add --quiet -b linked "$TEST_LINKED" HEAD
  mkdir -p "$TEST_MAIN/subdir/nested" "$TEST_LINKED/subdir/nested"
  source_gtr_libs
  cd "$TEST_MAIN"
}

teardown() {
  cd /
  rm -rf "$TEST_FIXTURE"
}

@test "separate Git directory resolves the main checkout and its subdirectories" {
  local context
  for context in "$TEST_MAIN" "$TEST_MAIN/subdir/nested"; do
    cd "$context"
    [ "$(_resolve_main_repo_root)" = "$TEST_MAIN" ]
    [ "$(_gtrconfig_path)" = "$TEST_MAIN/.gtrconfig" ]
  done
}

@test "relative gitfile and GIT_DIR paths resolve the separate main checkout" {
  printf 'gitdir: ../metadata/store\n' > "$TEST_MAIN/.git"
  cd "$TEST_MAIN/subdir/nested"
  [ "$(_resolve_main_repo_root)" = "$TEST_MAIN" ]

  cd "$TEST_MAIN"
  local git_dir
  for git_dir in ../metadata/store "$TEST_METADATA"; do
    [ "$(GIT_DIR="$git_dir" GIT_WORK_TREE=. _resolve_main_repo_root)" = "$TEST_MAIN" ]
  done
}

@test "linked worktrees use absolute or relative core.worktree from the common directory" {
  local configured context
  for configured in "$TEST_MAIN" '../../main checkout'; do
    git -C "$TEST_MAIN" config core.worktree "$configured"
    for context in "$TEST_MAIN" "$TEST_MAIN/subdir/nested" "$TEST_LINKED" "$TEST_LINKED/subdir/nested"; do
      cd "$context"
      [ "$(_resolve_main_repo_root)" = "$TEST_MAIN" ]
      [ "$(_gtrconfig_path)" = "$TEST_MAIN/.gtrconfig" ]
    done
  done
}

@test "linked worktree without a main-checkout backlink fails instead of selecting metadata" {
  git config -f "$TEST_METADATA/.gtrconfig" copy.include metadata.txt
  cd "$TEST_LINKED/subdir/nested"

  run _resolve_main_repo_root
  [ "$status" -eq 1 ]
  [ -z "$output" ]
  [ -z "$(_gtrconfig_path)" ]
  [ -z "$(cfg_get_all_file copy.include)" ]

  run "$PROJECT_ROOT/bin/gtr" new unresolved --from HEAD --no-fetch --porcelain
  [ "$status" -ne 0 ]
  [ ! -e "${TEST_METADATA}-worktrees" ]
  [ ! -e "${TEST_MAIN}-worktrees" ]
}

@test "separate metadata named .git still resolves the configured main checkout" {
  local main="$TEST_FIXTURE/dot-main" linked="$TEST_FIXTURE/dot-linked"
  git clone --quiet --separate-git-dir="$TEST_FIXTURE/metadata/.git" "$TEST_MAIN" "$main"
  git -C "$main" worktree add --quiet -b dot-linked "$linked" HEAD
  git -C "$main" config core.worktree "$main"

  local context
  for context in "$main" "$linked"; do
    cd "$context"
    [ "$(_resolve_main_repo_root)" = "$main" ]
  done
}

@test "main config is used even when a linked worktree has its own core.worktree" {
  git config extensions.worktreeConfig true
  if ! git config --worktree core.worktree "$TEST_MAIN"; then
    skip "worktree config is not available"
  fi
  git -C "$TEST_LINKED" config --worktree core.worktree "$TEST_LINKED"
  cd "$TEST_LINKED/subdir/nested"

  [ "$(_resolve_main_repo_root)" = "$TEST_MAIN" ]
}

@test "separate checkout paths preserve spaces quotes backslashes tabs newlines and unicode" {
  local unusual="$TEST_FIXTURE/quote\"back\\slash"$'\tline\n'"café"
  mv "$TEST_MAIN" "$unusual"
  TEST_MAIN="$unusual"
  git -C "$TEST_MAIN" config core.worktree "$TEST_MAIN"

  local context
  for context in "$TEST_MAIN/subdir/nested" "$TEST_LINKED/subdir/nested"; do
    cd "$context"
    [ "$(_resolve_main_repo_root)" = "$TEST_MAIN" ]
    [ "$(_gtrconfig_path)" = "$TEST_MAIN/.gtrconfig" ]
  done
}

@test "separate root resolution preserves caller environment and works with Bash 3.2 strict mode" {
  git config core.worktree "$TEST_MAIN"
  cd "$TEST_LINKED"
  export GIT_DIR=.git GIT_COMMON_DIR="$TEST_METADATA" GIT_WORK_TREE=.
  export CDPATH="$TEST_FIXTURE"

  _resolve_main_repo_root > "$TEST_FIXTURE/root"
  [ "$(cat "$TEST_FIXTURE/root")" = "$TEST_MAIN" ]
  [ "$GIT_DIR" = .git ]
  [ "$GIT_COMMON_DIR" = "$TEST_METADATA" ]
  [ "$GIT_WORK_TREE" = . ]
  [ "$CDPATH" = "$TEST_FIXTURE" ]
  [ "$PWD" = "$TEST_LINKED" ]

  run /bin/bash -eu -c 'source "$1/lib/config.sh"; _resolve_main_repo_root' bash "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_MAIN" ]
}

@test "separate root determines default and team-configured relative worktree paths and target 1" {
  git config core.worktree "$TEST_MAIN"
  local context result
  for context in "$TEST_MAIN/subdir/nested" "$TEST_LINKED/subdir/nested"; do
    cd "$context"
    [ "$(resolve_base_dir "$(_resolve_main_repo_root)")" = "${TEST_MAIN}-worktrees" ]
    result=$("$PROJECT_ROOT/bin/gtr" go 1 2>/dev/null)
    [ "$result" = "$TEST_MAIN" ]
  done

  git config -f "$TEST_MAIN/.gtrconfig" worktrees.dir local-trees
  git config -f "$TEST_METADATA/.gtrconfig" worktrees.dir wrong-trees
  git config -f "$TEST_LINKED/.gtrconfig" worktrees.dir linked-trees
  for context in "$TEST_MAIN/subdir/nested" "$TEST_LINKED/subdir/nested"; do
    cd "$context"
    [ "$(cfg_default gtr.worktrees.dir)" = local-trees ]
    [ "$(resolve_base_dir "$(_resolve_main_repo_root)" 2>/dev/null)" = "$TEST_MAIN/local-trees" ]
  done
}

@test "new from separate main and linked checkouts uses main config and copy sources" {
  git config -f "$TEST_MAIN/.gtrconfig" copy.include own.txt
  git config -f "$TEST_MAIN/.gtrconfig" copy.includeDirs assets
  printf 'main fixture\n' > "$TEST_MAIN/own.txt"
  mkdir "$TEST_MAIN/assets"
  printf 'main asset\n' > "$TEST_MAIN/assets/asset.txt"
  printf 'extra.txt\n' > "$TEST_MAIN/.worktreeinclude"
  printf 'main extra\n' > "$TEST_MAIN/extra.txt"
  git config -f "$TEST_METADATA/.gtrconfig" copy.include wrong.txt
  printf 'metadata fixture\n' > "$TEST_METADATA/wrong.txt"
  git config -f "$TEST_LINKED/.gtrconfig" copy.include wrong.txt
  printf 'linked fixture\n' > "$TEST_LINKED/own.txt"
  printf 'linked fixture\n' > "$TEST_LINKED/wrong.txt"

  cd "$TEST_MAIN/subdir/nested"
  run "$PROJECT_ROOT/bin/gtr" new from-main --from HEAD --no-fetch --porcelain
  [ "$status" -eq 0 ]
  local main_new="${TEST_MAIN}-worktrees/from-main"
  [ "$(cat "$main_new/own.txt")" = 'main fixture' ]
  [ "$(cat "$main_new/assets/asset.txt")" = 'main asset' ]
  [ "$(cat "$main_new/extra.txt")" = 'main extra' ]
  [ ! -e "$main_new/wrong.txt" ]

  git config core.worktree "$TEST_MAIN"
  git config -f "$TEST_MAIN/.gtrconfig" worktrees.dir local-trees
  cd "$TEST_LINKED/subdir/nested"
  run "$PROJECT_ROOT/bin/gtr" new from-linked --from HEAD --no-fetch --porcelain
  [ "$status" -eq 0 ]
  local linked_new="$TEST_MAIN/local-trees/from-linked"
  [ "$(cat "$linked_new/own.txt")" = 'main fixture' ]
  [ "$(cat "$linked_new/assets/asset.txt")" = 'main asset' ]
  [ "$(cat "$linked_new/extra.txt")" = 'main extra' ]
  [ ! -e "$linked_new/wrong.txt" ]
}
