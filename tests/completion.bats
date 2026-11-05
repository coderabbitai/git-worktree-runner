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
  git config branch.sort refname
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

# Complete git gtr arguments and parse each unquoted suggestion as an accepted word.
# Interactive acceptance and quote handling are exercised by the PTY regression below.
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
      # Fixtures are harmless if evaluated; this models acceptance of an unquoted word.
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
  run_bash_completion "$@" 'literal\$\('
  [ "$output" = "$DOLLAR_BRANCH" ]
  run_bash_completion "$@" 'literal`'
  [ "$output" = "$BACKTICK_BRANCH" ]
  run_bash_completion "$@" 'literal\`'
  [ "$output" = "$BACKTICK_BRANCH" ]
  run_bash_completion "$@" quote
  [ "$output" = "$QUOTED_BRANCH" ]
  run_bash_completion "$@" 'quote\"'
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

@test "bash completion retains matches after inserting an escaped common prefix" {
  setup_bash_completion_repo
  git branch "$DOLLAR_BRANCH-more"
  # shellcheck disable=SC1091
  source "$PROJECT_ROOT/completions/gtr.bash"

  _git_gtr_complete_targets literal
  [ "${#COMPREPLY[@]}" -eq 3 ]
  _git_gtr_complete_targets 'literal$('
  [ "${#COMPREPLY[@]}" -eq 2 ]

  # Readline inserts the common prefix of escaped candidates on the first Tab.
  local common_prefix="${COMPREPLY[0]}"
  while [[ "${COMPREPLY[1]}" != "$common_prefix"* ]]; do
    common_prefix="${common_prefix%?}"
  done
  [ "$common_prefix" = 'literal\$\(\>completion-dollar-marker\)' ]

  # Subsequent completion must keep both matches and allow narrowing to one.
  local cmd
  for cmd in go run rm mv rename editor ai copy; do
    run_bash_completion "$cmd" "$common_prefix"
    [ "$output" = "$DOLLAR_BRANCH"$'\n'"$DOLLAR_BRANCH-more" ]
    run_bash_completion "$cmd" "$common_prefix-m"
    [ "$output" = "$DOLLAR_BRANCH-more" ]
  done
}

@test "bash branch completion ignores column.branch=always" {
  setup_bash_completion_repo
  git config column.branch always
  local cmd
  for cmd in go editor ai copy; do
    assert_literal_branch_completions "$cmd"
  done
}

@test "bash Readline accepts branch names literally in every quoting context" {
  command -v python3 >/dev/null || skip "python3 is required for the Readline PTY test"
  setup_bash_completion_repo

  run python3 "$PROJECT_ROOT/tests/bash_completion_pty.py" "$PROJECT_ROOT" "$BASH"

  [ "$status" -eq 0 ]
  [[ "$output" == *"interactive completion checks passed"* ]]
}

@test "Bash rm completes branch names literally after a preview flag" {
  setup_bash_completion_repo
  run_bash_completion rm -n 'literal'
  [ "$output" = "$DOLLAR_BRANCH"$'\n'"$BACKTICK_BRANCH" ]
}

@test "Bash rm completion handles preview flags before and after targets" {
  run bash -c '
    source "$1/completions/gtr.bash"
    _init_completion() {
      words=(git gtr rm "${test_args[@]}")
      cword=$((${#words[@]} - 1))
      cur=${words[$cword]}
      prev=${words[$((cword - 1))]}
    }
    git() { printf "%s\n" topic; }
    test_args=(--dry)
    _git_gtr
    [ "${COMPREPLY[*]}" = --dry-run ] || exit 1
    test_args=(-n "")
    _git_gtr
    [ "${COMPREPLY[*]}" = "1 topic" ] || exit 1
    test_args=(topic --dry)
    _git_gtr
    [ "${COMPREPLY[*]}" = --dry-run ] || exit 1
    test_args=(to)
    _git_gtr
    [ "${COMPREPLY[*]}" = topic ]
  ' _ "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
}

@test "Zsh rm completion offers targets after preview options" {
  command -v zsh >/dev/null || skip "zsh is not installed"
  run zsh -c '
    _arguments() {
      [[ " $* " == *" *:target:->worktrees "* ]] || exit 1
      [[ " $* " == *" --dry-run["* ]] || exit 1
      state=worktrees
    }
    _describe() { [[ "$1" == "branch names" ]] || exit 1; described=yes; }
    git() { print topic; }
    words=(git gtr rm -n "")
    CURRENT=5
    source "$1/completions/_git-gtr"
    [[ "$described" == yes ]] || exit 1
    described=no
    words=(git gtr rm --dry)
    CURRENT=4
    _git-gtr
    [[ "$described" == yes ]]
  ' _ "$PROJECT_ROOT"
  [ "$status" -eq 0 ]
}
