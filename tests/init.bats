#!/usr/bin/env bats
# Tests for the init command (lib/commands/init.sh)

load test_helper

setup() {
  source "$PROJECT_ROOT/lib/commands/init.sh"
  # Isolate cache to temp dir so tests don't pollute ~/.cache or each other
  export XDG_CACHE_HOME="$BATS_TMPDIR/gtr-init-cache-$$"
  export GTR_VERSION="test"
}

teardown() {
  rm -rf "$BATS_TMPDIR/gtr-init-cache-$$"
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

# ── fzf interactive picker ───────────────────────────────────────────────────

@test "bash output includes fzf picker for cd with no args" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"command -v fzf"* ]]
  [[ "$output" == *"--prompt='Worktree> '"* ]]
  [[ "$output" == *"--with-nth=2"* ]]
  [[ "$output" == *"ctrl-e:execute"* ]]
}

@test "zsh output includes fzf picker for cd with no args" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"command -v fzf"* ]]
  [[ "$output" == *"--prompt='Worktree> '"* ]]
  [[ "$output" == *"--with-nth=2"* ]]
  [[ "$output" == *"ctrl-e:execute"* ]]
}

@test "fish output includes fzf picker for cd with no args" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"type -q fzf"* ]]
  [[ "$output" == *"--prompt='Worktree> '"* ]]
  [[ "$output" == *"--with-nth=2"* ]]
  [[ "$output" == *"ctrl-e:execute"* ]]
}

@test "bash output shows fzf install hint when no args and no fzf" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *'Install fzf for an interactive picker'* ]]
}

@test "fish output shows fzf install hint when no args and no fzf" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *'Install fzf for an interactive picker'* ]]
}

@test "--as replaces function name in fzf fallback message" {
  run cmd_init bash --as gwtr
  [ "$status" -eq 0 ]
  [[ "$output" == *'Usage: gwtr cd <branch>'* ]]
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

# ── caching (default behavior) ──────────────────────────────────────────────

@test "init creates cache file and returns output" {
  local cache_dir="$BATS_TMPDIR/gtr-cache-test-$$"
  XDG_CACHE_HOME="$cache_dir" GTR_VERSION="9.9.9" run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"gtr()"* ]]
  [ -f "$cache_dir/gtr/init-gtr.zsh" ]
  rm -rf "$cache_dir"
}

@test "init returns cached output on second call" {
  local cache_dir="$BATS_TMPDIR/gtr-cache-test-$$"
  # First call: generates and caches
  XDG_CACHE_HOME="$cache_dir" GTR_VERSION="9.9.9" run cmd_init bash
  [ "$status" -eq 0 ]
  local first_output="$output"
  # Second call: reads from cache
  XDG_CACHE_HOME="$cache_dir" GTR_VERSION="9.9.9" run cmd_init bash
  [ "$status" -eq 0 ]
  [ "$output" = "$first_output" ]
  rm -rf "$cache_dir"
}

@test "cache invalidates when version changes" {
  local cache_dir="$BATS_TMPDIR/gtr-cache-test-$$"
  # Generate with version 1.0.0
  XDG_CACHE_HOME="$cache_dir" GTR_VERSION="1.0.0" run cmd_init zsh
  [ "$status" -eq 0 ]
  # Check cache stamp
  local stamp
  stamp="$(head -1 "$cache_dir/gtr/init-gtr.zsh")"
  [[ "$stamp" == *"version=1.0.0"* ]]
  # Regenerate with version 2.0.0
  XDG_CACHE_HOME="$cache_dir" GTR_VERSION="2.0.0" run cmd_init zsh
  [ "$status" -eq 0 ]
  stamp="$(head -1 "$cache_dir/gtr/init-gtr.zsh")"
  [[ "$stamp" == *"version=2.0.0"* ]]
  rm -rf "$cache_dir"
}

@test "cache uses --as func name in cache key" {
  local cache_dir="$BATS_TMPDIR/gtr-cache-test-$$"
  XDG_CACHE_HOME="$cache_dir" GTR_VERSION="9.9.9" run cmd_init bash --as myfn
  [ "$status" -eq 0 ]
  [[ "$output" == *"myfn()"* ]]
  [ -f "$cache_dir/gtr/init-myfn.bash" ]
  rm -rf "$cache_dir"
}

@test "cache works for all shells" {
  local cache_dir="$BATS_TMPDIR/gtr-cache-test-$$"
  for sh in bash zsh fish; do
    XDG_CACHE_HOME="$cache_dir" GTR_VERSION="9.9.9" run cmd_init "$sh"
    [ "$status" -eq 0 ]
    [ -f "$cache_dir/gtr/init-gtr.${sh}" ]
  done
  rm -rf "$cache_dir"
}
