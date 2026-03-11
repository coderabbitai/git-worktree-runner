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
