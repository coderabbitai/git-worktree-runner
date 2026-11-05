#!/usr/bin/env bats
# Tests for completion asset resolution and generated Bash completion behavior

load test_helper

log_error() { printf '%s\n' "$*" >&2; }
log_info() { printf '%s\n' "$*" >&2; }

setup() {
  TEST_ROOT="$(mktemp -d)"
  TEST_GTR_DIR="$TEST_ROOT/prefix with spaces"
  mkdir -p "$TEST_GTR_DIR"
  export GTR_DIR="$TEST_GTR_DIR"
  # shellcheck disable=SC1091
  . "$PROJECT_ROOT/lib/commands/completion.sh"
}

teardown() {
  rm -rf "$TEST_ROOT"
}

write_test_file() {
  local path="$1" content="$2"
  mkdir -p "$(dirname "$path")"
  printf '%s\n' "$content" > "$path"
}

setup_source_layout() {
  write_test_file "$TEST_GTR_DIR/completions/gtr.bash" "# source bash completion"
  write_test_file "$TEST_GTR_DIR/completions/_git-gtr" "#compdef git-gtr"
  write_test_file "$TEST_GTR_DIR/completions/git-gtr.fish" "# fish source completion"
}

setup_homebrew_layout() {
  write_test_file "$TEST_GTR_DIR/etc/bash_completion.d/git-gtr" "# brew bash completion"
  write_test_file "$TEST_GTR_DIR/share/zsh/site-functions/_git-gtr" "#compdef git-gtr"
  write_test_file "$TEST_GTR_DIR/share/fish/vendor_completions.d/git-gtr.fish" "# fish brew completion"
}

@test "cmd_completion bash uses source checkout asset when present" {
  setup_source_layout

  run cmd_completion bash

  [ "$status" -eq 0 ]
  [ "$output" = "# source bash completion" ]
}

@test "cmd_completion zsh uses source checkout completions directory when present" {
  setup_source_layout

  run cmd_completion zsh

  [ "$status" -eq 0 ]
  [[ "$output" == *"fpath=('$TEST_GTR_DIR/completions' \$fpath)"* ]]
}

@test "cmd_completion fish uses source checkout asset when present" {
  setup_source_layout

  run cmd_completion fish

  [ "$status" -eq 0 ]
  [ "$output" = "# fish source completion" ]
}

@test "cmd_completion bash falls back to Homebrew asset layout" {
  setup_homebrew_layout

  run cmd_completion bash

  [ "$status" -eq 0 ]
  [ "$output" = "# brew bash completion" ]
}

@test "cmd_completion zsh falls back to Homebrew site-functions directory" {
  setup_homebrew_layout

  run cmd_completion zsh

  [ "$status" -eq 0 ]
  [[ "$output" == *"fpath=('$TEST_GTR_DIR/share/zsh/site-functions' \$fpath)"* ]]
}

@test "cmd_completion fish falls back to Homebrew vendor completions" {
  setup_homebrew_layout

  run cmd_completion fish

  [ "$status" -eq 0 ]
  [ "$output" = "# fish brew completion" ]
}

@test "cmd_completion prefers source checkout assets over Homebrew assets" {
  setup_source_layout
  setup_homebrew_layout

  run cmd_completion bash

  [ "$status" -eq 0 ]
  [ "$output" = "# source bash completion" ]
}

@test "cmd_completion returns a clear error when completion assets are missing" {
  run cmd_completion bash

  [ "$status" -eq 1 ]
  [[ "$output" == *"Could not find bash completion asset under:"* ]]
  [[ "$output" == *"Expected either a source checkout (completions/) or a Homebrew install layout."* ]]
}

# Create a disposable repository with harmless command-substitution and quote fixtures.
setup_bash_completion_repo() {
  mkdir -p "$TEST_ROOT/repo"
  cd "$TEST_ROOT/repo" || return 1
  git init --quiet
  git symbolic-ref HEAD refs/heads/main
  git -c user.name=Test -c user.email=test@example.com -c commit.gpgsign=false \
    commit --allow-empty --quiet -m init

  # Both are valid refs. Evaluating either creates a harmless marker in this repo.
  DOLLAR_BRANCH='literal$(>completion-dollar-marker)'
  BACKTICK_BRANCH='literal`>completion-backtick-marker`'
  QUOTED_BRANCH="quote\"and'apostrophe"
  local branch
  for branch in feature/api feature/auth fix/bug \
    "$DOLLAR_BRANCH" "$BACKTICK_BRANCH" "$QUOTED_BRANCH"; do
    git branch "$branch"
  done
}

# Complete git gtr arguments, then parse each suggestion as an accepted Bash word.
# Check both candidate generation and acceptance leave the fixture markers absent.
run_bash_completion() {
  # Supply bash-completion's context without requiring it to be installed.
  # Use errexit to catch failures when a prefix has no matches.
  run bash -e -c '
    source "$1"
    shift
    _init_completion() {
      words=("${COMP_WORDS[@]}")
      cword=$COMP_CWORD
      cur=${words[cword]}
      prev=${words[cword-1]}
      COMPREPLY=()
    }
    COMP_WORDS=(git gtr "$@")
    COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
    _git_gtr
    for candidate in "${COMPREPLY[@]}"; do
      # Deliberately parse the suggestion, as Bash does after completion and Enter.
      # The fixture substitutions only create harmless marker files in this repo.
      eval "set -- $candidate"
      [ "$#" -eq 1 ]
      printf "%s\n" "$1"
    done
  ' bash "$PROJECT_ROOT/completions/gtr.bash" "$@"

  [ ! -e completion-dollar-marker ]
  [ ! -e completion-backtick-marker ]
  [ "$status" -eq 0 ]
}

# Verify literal argv round trips, ordinary prefixes, target 1, and no-match behavior.
assert_literal_branch_completions() {
  local expected
  expected=$(printf '%s\n' 1 feature/api feature/auth fix/bug \
    "$DOLLAR_BRANCH" "$BACKTICK_BRANCH" main "$QUOTED_BRANCH")
  run_bash_completion "$@" ""
  [ "$output" = "$expected" ]

  run_bash_completion "$@" 'literal$('
  [ "$output" = "$DOLLAR_BRANCH" ]
  run_bash_completion "$@" 'literal`'
  [ "$output" = "$BACKTICK_BRANCH" ]
  run_bash_completion "$@" quote
  [ "$output" = "$QUOTED_BRANCH" ]

  run_bash_completion "$@" feature/a
  [ "$output" = $'feature/api\nfeature/auth' ]
  run_bash_completion "$@" 1
  [ "$output" = "1" ]
  run_bash_completion "$@" missing
  [ -z "$output" ]
}

@test "bash go/run/rm/mv/rename completion filters branch names literally" {
  setup_bash_completion_repo
  local cmd
  for cmd in go run rm mv rename; do
    assert_literal_branch_completions "$cmd"
  done
}

@test "bash editor completion filters branch names literally" {
  setup_bash_completion_repo
  assert_literal_branch_completions editor
  assert_literal_branch_completions editor --editor vim
}

@test "bash ai completion filters branch names literally" {
  setup_bash_completion_repo
  assert_literal_branch_completions ai
  assert_literal_branch_completions ai --ai codex
}

@test "bash copy completion filters branch names literally" {
  setup_bash_completion_repo
  assert_literal_branch_completions copy
  assert_literal_branch_completions copy --from
}
