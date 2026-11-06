#!/usr/bin/env bash
# Parse creation suggestions without launching real editors or AI tools.
# shellcheck disable=SC2154  # output and status are set by BATS run.
assert_next_steps_suggestions() {
  local expected_id="$1" expected_path="$2" creation_output="$output"
  local suggestion subcommand argv_file="$BATS_TEST_TMPDIR/next-steps-argv"
  local expected_file="$BATS_TEST_TMPDIR/next-steps-expected"

  # The suggested identifier must still resolve to the newly created worktree.
  local actual_path
  actual_path=$("$PROJECT_ROOT/bin/gtr" go "$expected_id" 2>/dev/null)
  [ "$actual_path" = "$expected_path" ]
  [ ! -e "$TEST_REPO/next-steps-marker" ]

  for subcommand in editor ai go; do
    # shellcheck disable=SC2016  # Match the literal command substitution.
    case "$subcommand" in
      go) suggestion=$(printf '%s\n' "$creation_output" | sed -n '/^  cd "$(git gtr go /p') ;;
      *) suggestion=$(printf '%s\n' "$creation_output" | sed -n "/^  git gtr $subcommand /p") ;;
    esac
    [ -n "$suggestion" ]
    : > "$argv_file"
    run bash --noprofile --norc -c '
      argv_file=$2
      worktree_path=$3
      git() {
        printf "%s\0" git "$#" "$@" >> "$argv_file"
        if [ "${2:-}" = go ]; then
          printf "%s\n" "$worktree_path"
        fi
      }
      cd() { printf "%s\0" cd "$#" "$@" >> "$argv_file"; }
      eval "$1"
    ' _ "$suggestion" "$argv_file" "$expected_path"
    [ "$status" -eq 0 ]
    [ ! -e "$TEST_REPO/next-steps-marker" ]
    printf '%s\0' git 3 gtr "$subcommand" "$expected_id" > "$expected_file"
    if [ "$subcommand" = go ]; then
      printf '%s\0' cd 1 "$expected_path" >> "$expected_file"
    fi
    cmp "$expected_file" "$argv_file"
  done
}
