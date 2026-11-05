#!/usr/bin/env bats
# Tests for completion path resolution in lib/commands/completion.sh

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
    [ "${COMPREPLY[*]}" = topic ] || exit 1
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
