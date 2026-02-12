#!/usr/bin/env bats
# Tests for the shared argument parser (lib/args.sh)

load test_helper

setup() {
  source "$PROJECT_ROOT/lib/args.sh"
}

@test "boolean flag sets _arg variable to 1" {
  parse_args "--force" --force
  [ "$_arg_force" = "1" ]
}

@test "value flag sets _arg variable to the value" {
  parse_args "--from: value" --from origin/main
  [ "$_arg_from" = "origin/main" ]
}

@test "short alias maps to same variable as long form" {
  parse_args "--dry-run|-n" -n
  [ "$_arg_dry_run" = "1" ]
}

@test "long form also works with alias spec" {
  parse_args "--dry-run|-n" --dry-run
  [ "$_arg_dry_run" = "1" ]
}

@test "positional args collected in _pa_positional" {
  parse_args "--force" my-branch --force
  [ "${_pa_positional[0]}" = "my-branch" ]
  [ "$_arg_force" = "1" ]
}

@test "multiple positional args collected in order" {
  parse_args "" foo bar baz
  [ ${#_pa_positional[@]} -eq 3 ]
  [ "${_pa_positional[0]}" = "foo" ]
  [ "${_pa_positional[1]}" = "bar" ]
  [ "${_pa_positional[2]}" = "baz" ]
}

@test "-- stops parsing and collects passthrough args" {
  parse_args "--ai: value" my-branch --ai claude -- --verbose --model opus
  [ "${_pa_positional[0]}" = "my-branch" ]
  [ "$_arg_ai" = "claude" ]
  [ ${#_pa_passthrough[@]} -eq 3 ]
  [ "${_pa_passthrough[0]}" = "--verbose" ]
  [ "${_pa_passthrough[1]}" = "--model" ]
  [ "${_pa_passthrough[2]}" = "opus" ]
}

@test "unknown flag exits with error" {
  run parse_args "--force" --badarg
  [ "$status" -eq 1 ]
}

@test "empty spec still rejects unknown flags" {
  run parse_args "" --something
  [ "$status" -eq 1 ]
}

@test "hyphens in flag names become underscores in variable" {
  parse_args "--from-current" --from-current
  [ "$_arg_from_current" = "1" ]
}

@test "multiline spec with mixed flag types" {
  local spec
  spec="--from: value
--from-current
--no-copy
--editor|-e"
  parse_args "$spec" --from main --no-copy -e my-branch

  [ "$_arg_from" = "main" ]
  [ "$_arg_from_current" = "" ]
  [ "$_arg_no_copy" = "1" ]
  [ "$_arg_editor" = "1" ]
  [ "${_pa_positional[0]}" = "my-branch" ]
}

@test "flags without values are reset to empty on each parse" {
  parse_args "--force" --force
  [ "$_arg_force" = "1" ]

  # Parse again without the flag
  parse_args "--force" my-branch
  [ "$_arg_force" = "" ]
}

@test "value flag without argument exits with error" {
  run parse_args "--from: value" --from
  [ "$status" -eq 1 ]
}
