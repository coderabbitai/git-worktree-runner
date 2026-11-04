#!/usr/bin/env bats
# Repository-root and copy isolation for bare repositories and their worktrees.

load test_helper

setup() {
  TEST_FIXTURE=$(cd -P "$(mktemp -d)" && pwd)
  TEST_PARENT="$TEST_FIXTURE/parent space"
  TEST_BARE="$TEST_PARENT/repository.git"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  export XDG_CONFIG_HOME="$TEST_FIXTURE/user-config"
  export XDG_CACHE_HOME="$TEST_FIXTURE/cache"
  export GIT_TEMPLATE_DIR="$TEST_FIXTURE/template"
  export GTR_DIR="$PROJECT_ROOT"
  mkdir -p "$TEST_PARENT" "$GIT_TEMPLATE_DIR"
  git init --quiet "$TEST_FIXTURE/seed"
  git -C "$TEST_FIXTURE/seed" -c user.name=Test -c user.email=test@example.com \
    commit --allow-empty -m init --quiet
  git clone --bare --quiet "$TEST_FIXTURE/seed" "$TEST_BARE"
  source_gtr_libs
  cd "$TEST_BARE"
}

teardown() {
  cd /
  rm -rf "$TEST_FIXTURE"
}

@test "bare root and subdirectories resolve to the bare repository" {
  local context
  for context in "$TEST_BARE" "$TEST_BARE/objects"; do
    cd "$context"
    [ "$(_resolve_main_repo_root)" = "$TEST_BARE" ]
    [ "$(_gtrconfig_path)" = "$TEST_BARE/.gtrconfig" ]
  done
}

@test "relative and absolute GIT_DIR resolve to the same bare root" {
  cd "$TEST_PARENT"
  local git_dir
  for git_dir in repository.git "$TEST_BARE"; do
    [ "$(GIT_DIR="$git_dir" _resolve_main_repo_root)" = "$TEST_BARE" ]
  done
}

@test "bare repositories named .git keep their own root from linked worktrees" {
  local bare="$TEST_PARENT/.git" linked="$TEST_FIXTURE/linked"
  git clone --bare --quiet "$TEST_FIXTURE/seed" "$bare"
  git -C "$bare" worktree add --quiet -b linked "$linked" HEAD
  mkdir -p "$linked/subdir"

  local context
  for context in "$bare" "$bare/objects" "$linked" "$linked/subdir"; do
    cd "$context"
    [ "$(_resolve_main_repo_root)" = "$bare" ]
    [ "$(_gtrconfig_path)" = "$bare/.gtrconfig" ]
  done
}

@test "bare root determines default and relative worktree locations" {
  [ "$(resolve_base_dir "$(_resolve_main_repo_root)")" = "${TEST_BARE}-worktrees" ]
  git config gtr.worktrees.dir local-worktrees
  [ "$(resolve_base_dir "$(_resolve_main_repo_root)" 2>/dev/null)" = "$TEST_BARE/local-worktrees" ]
}

@test "new from bare repo ignores parent config and copy patterns" {
  local worktrees="$TEST_FIXTURE/worktrees"
  git config gtr.worktrees.dir "$worktrees"
  printf 'benign parent fixture\n' > "$TEST_PARENT/secret.txt"
  printf 'parent include fixture\n' > "$TEST_PARENT/parent-include.txt"
  mkdir "$TEST_PARENT/parent-assets"
  printf 'parent asset fixture\n' > "$TEST_PARENT/parent-assets/asset.txt"
  git config -f "$TEST_PARENT/.gtrconfig" copy.include secret.txt
  git config -f "$TEST_PARENT/.gtrconfig" copy.includeDirs parent-assets
  git config -f "$TEST_PARENT/.gtrconfig" hooks.postCreate 'touch parent-hook-ran'
  printf 'parent-include.txt\n' > "$TEST_PARENT/.worktreeinclude"

  run "$PROJECT_ROOT/bin/gtr" new isolated --from HEAD --no-fetch --porcelain

  [ "$status" -eq 0 ]
  [ -f "$worktrees/isolated/.git" ]
  [ ! -e "$worktrees/isolated/secret.txt" ]
  [ ! -e "$worktrees/isolated/parent-include.txt" ]
  [ ! -e "$worktrees/isolated/parent-assets" ]
  [ ! -e "$worktrees/isolated/parent-hook-ran" ]
  [[ "$output" == *$'hook_status\tnone'* ]]
}

@test "bare and linked worktree creation use the bare root config and copy source" {
  printf 'bare fixture\n' > "$TEST_BARE/own.txt"
  printf 'bare include fixture\n' > "$TEST_BARE/own-include.txt"
  mkdir "$TEST_BARE/own-assets"
  printf 'bare asset fixture\n' > "$TEST_BARE/own-assets/asset.txt"
  git config -f "$TEST_BARE/.gtrconfig" copy.include own.txt
  git config -f "$TEST_BARE/.gtrconfig" copy.includeDirs own-assets
  printf 'own-include.txt\n' > "$TEST_BARE/.worktreeinclude"

  run "$PROJECT_ROOT/bin/gtr" new first --from HEAD --no-fetch --porcelain
  [ "$status" -eq 0 ]
  [ "$(cat "${TEST_BARE}-worktrees/first/own.txt")" = "bare fixture" ]
  [ -f "${TEST_BARE}-worktrees/first/own-include.txt" ]
  [ -f "${TEST_BARE}-worktrees/first/own-assets/asset.txt" ]

  mkdir "${TEST_BARE}-worktrees/first/subdir"
  cd "${TEST_BARE}-worktrees/first/subdir"
  # A linked worktree reports --is-bare-repository=false, even for a bare common dir.
  [ "$(git rev-parse --is-bare-repository)" = false ]
  [ "$(_resolve_main_repo_root)" = "$TEST_BARE" ]
  printf 'linked fixture\n' > ../own.txt
  git config -f ../.gtrconfig copy.include should-not-copy.txt
  run "$PROJECT_ROOT/bin/gtr" new second --from HEAD --no-fetch --porcelain
  [ "$status" -eq 0 ]
  [ "$(cat "${TEST_BARE}-worktrees/second/own.txt")" = "bare fixture" ]
  [ -f "${TEST_BARE}-worktrees/second/own-include.txt" ]
  [ -f "${TEST_BARE}-worktrees/second/own-assets/asset.txt" ]
}

@test "normal repo and linked worktrees retain main config and copy source" {
  local normal="$TEST_PARENT/normal" linked="$TEST_FIXTURE/linked"
  git clone --quiet "$TEST_FIXTURE/seed" "$normal"
  git -C "$normal" worktree add --quiet -b linked "$linked" HEAD
  mkdir -p "$normal/subdir" "$linked/subdir"
  git config -f "$TEST_PARENT/.gtrconfig" copy.include parent.txt
  printf 'parent fixture\n' > "$TEST_PARENT/parent.txt"
  git config -f "$normal/.gtrconfig" copy.include main.txt
  printf 'main fixture\n' > "$normal/main.txt"
  git config -f "$linked/.gtrconfig" copy.include linked.txt
  printf 'linked fixture\n' > "$linked/linked.txt"

  local context branch=0
  for context in "$normal" "$normal/subdir" "$linked" "$linked/subdir"; do
    cd "$context"
    [ "$(_resolve_main_repo_root)" = "$normal" ]
    [ "$(_gtrconfig_path)" = "$normal/.gtrconfig" ]
    branch=$((branch + 1))
    run "$PROJECT_ROOT/bin/gtr" new "control-$branch" --from HEAD --no-fetch --porcelain
    [ "$status" -eq 0 ]
    [ "$(cat "${normal}-worktrees/control-$branch/main.txt")" = "main fixture" ]
    [ ! -e "${normal}-worktrees/control-$branch/parent.txt" ]
    [ ! -e "${normal}-worktrees/control-$branch/linked.txt" ]
  done
}
