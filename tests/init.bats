#!/usr/bin/env bats
# Tests for the init command (lib/commands/init.sh)

load test_helper

setup() {
  source "$PROJECT_ROOT/lib/commands/init.sh"
}

# ── Default function name ────────────────────────────────────────────────────

@test "bash output defines gtr() function by default" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"gtr()"* ]]
}

@test "zsh output defines gtr() function by default" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"gtr()"* ]]
}

@test "fish output defines 'function gtr' by default" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"function gtr"* ]]
}

# ── --as flag ────────────────────────────────────────────────────────────────

@test "bash --as gwtr defines gwtr() function" {
  run cmd_init bash --as gwtr
  [ "$status" -eq 0 ]
  [[ "$output" == *"gwtr()"* ]]
  [[ "$output" != *"gtr()"* ]]
}

@test "zsh --as gwtr defines gwtr() function" {
  run cmd_init zsh --as gwtr
  [ "$status" -eq 0 ]
  [[ "$output" == *"gwtr()"* ]]
  [[ "$output" != *"gtr()"* ]]
}

@test "fish --as gwtr defines 'function gwtr'" {
  run cmd_init fish --as gwtr
  [ "$status" -eq 0 ]
  [[ "$output" == *"function gwtr"* ]]
  [[ "$output" != *"function gtr"* ]]
}

@test "--as replaces function name in completion registration (bash)" {
  run cmd_init bash --as myfn
  [ "$status" -eq 0 ]
  [[ "$output" == *"complete -F _myfn_completion myfn"* ]]
}

@test "--as replaces function name in compdef (zsh)" {
  run cmd_init zsh --as myfn
  [ "$status" -eq 0 ]
  [[ "$output" == *"compdef _myfn_completion myfn"* ]]
}

@test "--as replaces function name in fish completions" {
  run cmd_init fish --as myfn
  [ "$status" -eq 0 ]
  [[ "$output" == *"complete -f -c myfn"* ]]
}

@test "--as replaces error message prefix" {
  run cmd_init bash --as gwtr
  [ "$status" -eq 0 ]
  [[ "$output" == *"gwtr: postCd hook failed"* ]]
}

@test "--as can appear before shell argument" {
  run cmd_init --as gwtr bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"gwtr()"* ]]
}

# ── --as validation ──────────────────────────────────────────────────────────

@test "--as rejects name starting with digit" {
  run cmd_init bash --as 123bad
  [ "$status" -eq 1 ]
}

@test "--as rejects name with hyphens" {
  run cmd_init bash --as foo-bar
  [ "$status" -eq 1 ]
}

@test "--as rejects name with spaces" {
  run cmd_init bash --as "foo bar"
  [ "$status" -eq 1 ]
}

@test "--as accepts underscore-prefixed name" {
  run cmd_init bash --as _my_func
  [ "$status" -eq 0 ]
  [[ "$output" == *"_my_func()"* ]]
}

@test "--as without value fails" {
  run cmd_init bash --as
  [ "$status" -eq 1 ]
}

# ── cd completions ───────────────────────────────────────────────────────────

@test "bash output includes cd in subcommand completions" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *'"cd new go run'* ]]
}

@test "bash output uses git gtr list --porcelain for cd completion" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr list --porcelain"* ]]
}

@test "zsh output includes cd completion" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"cd:Change directory to worktree"* ]]
}

@test "zsh output uses git gtr list --porcelain for cd completion" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr list --porcelain"* ]]
}

@test "fish output includes cd subcommand completion" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"-a cd -d"* ]]
}

@test "fish output uses git gtr list --porcelain for cd completion" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr list --porcelain"* ]]
}

# ── Error cases ──────────────────────────────────────────────────────────────

@test "unknown shell fails" {
  run cmd_init powershell
  [ "$status" -eq 1 ]
}

@test "unknown flag fails" {
  run cmd_init bash --unknown
  [ "$status" -eq 1 ]
}

# ── git gtr passthrough preserved ────────────────────────────────────────────

@test "bash output passes non-cd commands to git gtr" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *'command git gtr "$@"'* ]]
}

@test "--as does not replace 'git gtr' invocations" {
  run cmd_init bash --as myfn
  [ "$status" -eq 0 ]
  [[ "$output" == *"command git gtr"* ]]
  [[ "$output" == *"git gtr list --porcelain"* ]]
}
