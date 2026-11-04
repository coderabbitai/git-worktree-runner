#!/usr/bin/env bats
# Tests for text prompt stream separation in lib/ui.sh

load test_helper

setup() {
  # Use the real UI functions rather than test_helper's logging stubs.
  NO_COLOR=1 . "$PROJECT_ROOT/lib/ui.sh"
}

@test "prompt_input keeps the prompt out of command substitution" {
  local answer
  answer=$(prompt_input "Enter branch name:" \
    <<< 'feature/prompt-test' 2>"$BATS_TEST_TMPDIR/stderr")

  [ "$answer" = "feature/prompt-test" ]
  [ "$(cat "$BATS_TEST_TMPDIR/stderr")" = "[?] Enter branch name: " ]
}

@test "prompt_input returns an empty answer without capturing the prompt" {
  local answer
  answer=$(prompt_input "Enter pull request number, URL, or branch:" \
    <<< '' 2>"$BATS_TEST_TMPDIR/stderr")

  [ -z "$answer" ]
  [ "$(cat "$BATS_TEST_TMPDIR/stderr")" = "[?] Enter pull request number, URL, or branch: " ]
}

@test "prompt_input sets a named variable without writing to stdout" {
  local answer="unchanged"
  prompt_input "Enter branch name:" answer <<< 'feature/named-input' \
    >"$BATS_TEST_TMPDIR/stdout" 2>"$BATS_TEST_TMPDIR/stderr"

  [ "$answer" = "feature/named-input" ]
  [ ! -s "$BATS_TEST_TMPDIR/stdout" ]
  [ "$(cat "$BATS_TEST_TMPDIR/stderr")" = "[?] Enter branch name: " ]
}
