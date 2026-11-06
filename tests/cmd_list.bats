#!/usr/bin/env bats
# Tests for cmd_list in lib/commands/list.sh

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
}

teardown() {
  teardown_integration_repo
}

@test "cmd_list shows main repo" {
  run cmd_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"[main repo]"* ]]
}

@test "cmd_list shows created worktree" {
  create_test_worktree "list-me"
  run cmd_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"list-me"* ]]
}

@test "cmd_list shows nested externally-created worktree" {
  mkdir -p "$TEST_WORKTREES_DIR/jsmith"
  git -C "$TEST_REPO" worktree add "$TEST_WORKTREES_DIR/jsmith/my-feature" -b jsmith/my-feature --quiet

  run cmd_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"jsmith/my-feature"* ]]
  [[ "$output" == *"$TEST_WORKTREES_DIR/jsmith/my-feature"* ]]
  [[ "$output" != *"(detached)"*"$TEST_WORKTREES_DIR/jsmith"* ]]
}

@test "cmd_list --porcelain outputs TSV format" {
  create_test_worktree "porcelain-test"
  local output
  output=$(cmd_list --porcelain)
  # First line: main repo
  local first_line
  first_line=$(echo "$output" | head -1)
  [[ "$first_line" == *"$TEST_REPO"* ]]
  # Should contain tab-separated fields
  [[ "$output" == *$'\t'* ]]
}

@test "cmd_list --porcelain includes worktree branch and status" {
  create_test_worktree "tsv-test"
  local output
  output=$(cmd_list --porcelain)
  # Worktree line should have: path<tab>branch<tab>status
  [[ "$output" == *"tsv-test"*$'\t'*"ok"* ]]
}

@test "cmd_list preserves trailing newlines through sorting and rendering" {
  git worktree list --porcelain -z >/dev/null 2>&1 || skip "NUL worktree listing is unavailable"
  local suffix path branch result formatted
  printf '%s\t%s\tok\n' "$TEST_REPO" "$(git symbolic-ref --short HEAD)" > "$TEST_REPO/expected"
  for suffix in $'\n' $'\n\n'; do
    branch="list-${#suffix}"
    path="$TEST_WORKTREES_DIR/$branch$suffix"
    git worktree add -b "$branch" "$path" HEAD >/dev/null
    printf '%s\t%s\tok\n' "$path" "$branch" >> "$TEST_REPO/expected"

    result=$(cmd_list)
    printf -v formatted '%-30s %s\n' "$branch" "$path"
    [[ "$result" == *"$formatted"* ]]
    result=$(cmd_list --ids)
    [[ "$result" == *"path:$(_tsv_escape_field "$path")"$'\t'"$branch"$'\tok'* ]]
  done
  cmd_list --porcelain > "$TEST_REPO/actual"
  cmp "$TEST_REPO/expected" "$TEST_REPO/actual"
}

@test "cmd_list --porcelain includes nested externally-created worktree" {
  mkdir -p "$TEST_WORKTREES_DIR/jsmith"
  git -C "$TEST_REPO" worktree add "$TEST_WORKTREES_DIR/jsmith/my-feature" -b jsmith/my-feature --quiet

  local output
  output=$(cmd_list --porcelain)

  local expected_row="$TEST_WORKTREES_DIR/jsmith/my-feature"$'\t'"jsmith/my-feature"$'\t'"ok"
  local bogus_parent="$TEST_WORKTREES_DIR/jsmith"$'\t'"(detached)"$'\t'"missing"
  [[ "$output" == *"$expected_row"* ]]
  [[ "$output" != *"$bogus_parent"* ]]
}

@test "cmd_list with no worktrees still works" {
  run cmd_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"Git Worktrees"* ]]
}

@test "cmd_list human format has header" {
  run cmd_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"BRANCH"* ]]
  [[ "$output" == *"PATH"* ]]
}

@test "cmd_list from inside a worktree shows all worktrees" {
  create_test_worktree "wt-inside"
  cd "$TEST_WORKTREES_DIR/wt-inside"
  run cmd_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"[main repo]"* ]]
  [[ "$output" == *"wt-inside"* ]]
  [[ "$output" == *"$TEST_REPO"* ]]
}

@test "cmd_list --porcelain from inside a worktree includes main repo" {
  create_test_worktree "wt-porcelain"
  cd "$TEST_WORKTREES_DIR/wt-porcelain"
  local output
  output=$(cmd_list --porcelain)
  [[ "$output" == *"$TEST_REPO"* ]]
  [[ "$output" == *"wt-porcelain"* ]]
}

@test "cmd_list from a repo subdirectory shows the main repo root" {
  mkdir -p "$TEST_REPO/subdir/nested"
  cd "$TEST_REPO/subdir/nested"
  run cmd_list
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_REPO"* ]]
  [[ "$output" != *"subdir/..-worktrees"* ]]
}

@test "cmd_list --ids emits one escaped registered identity per worktree" {
  local path="$TEST_WORKTREES_DIR/back\\slash"$'\t'"tab"$'\n'"line"$'\n'
  git worktree add --quiet --detach "$path" HEAD
  run cmd_list --ids
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[1]}" = "path:$(_tsv_escape_field "$path")"$'\t(detached)\tdetached' ]
  local identity="${lines[1]%%$'\t'*}"
  resolve_worktree "$identity" "$TEST_REPO" "$TEST_WORKTREES_DIR" ""
  [ "$_ctx_worktree_path" = "$path" ]
}

@test "old Git rejects newline paths before they can impersonate picker identities" {
  git worktree add --quiet "$TEST_WORKTREES_DIR/other" -b other
  git worktree add --quiet --detach "$TEST_WORKTREES_DIR/other"$'\n'"suffix" HEAD
  git() {
    case "$*" in *"worktree list --porcelain -z") return 1 ;; esac
    command git "$@"
  }
  run cmd_list --ids
  [ "$status" -eq 1 ]
  [[ "$output" == *'require Git with NUL'* ]]
  [[ "$output" != *"path:$TEST_WORKTREES_DIR/other"* ]]
  run resolve_worktree "path:$TEST_WORKTREES_DIR/other" "$TEST_REPO" "$TEST_WORKTREES_DIR" ""
  [ "$status" -eq 1 ]
}

@test "old Git rejects a newline in the main worktree path too" {
  local main="$TEST_REPO/main"$'\n'"root"
  git init --quiet "$main"
  cd "$main"
  git() {
    case "$*" in *"worktree list --porcelain -z") return 1 ;; esac
    command git "$@"
  }
  run cmd_list --ids
  [ "$status" -eq 1 ]
  [[ "$output" == *'require Git with NUL'* ]]
  [[ "$output" != *"path:"* ]]
}
