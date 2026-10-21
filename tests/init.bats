#!/usr/bin/env bats
# Tests for the init command (lib/commands/init.sh)

load test_helper

setup() {
  source "$PROJECT_ROOT/lib/commands/init.sh"
  # Isolate cache to temp dir so tests don't pollute ~/.cache or each other
  INIT_CACHE_TEST_ROOT=$(mktemp -d "$BATS_TMPDIR/gtr-init-cache.XXXXXX")
  export XDG_CACHE_HOME="$INIT_CACHE_TEST_ROOT/cache"
  export GTR_VERSION="test"
}

teardown() {
  rm -rf "$INIT_CACHE_TEST_ROOT"
}

run_generated_bash_wrapper_completion() {
  local wrapper_name="$1"
  local comp_line="$2"
  local comp_cword="$3"
  local comp_point="$4"
  shift 4

  bash -s -- "$PROJECT_ROOT" "$XDG_CACHE_HOME" "$wrapper_name" "$comp_line" "$comp_cword" "$comp_point" "$@" <<'BASH'
set -euo pipefail

PROJECT_ROOT="$1"
XDG_CACHE_HOME="$2"
wrapper_name="$3"
comp_line="$4"
comp_cword="$5"
comp_point="$6"
shift 6
words=("$@")

export XDG_CACHE_HOME
export GTR_VERSION="test"

log_info() { :; }
log_warn() { :; }
log_error() { :; }
show_command_help() { :; }

# shellcheck disable=SC1090
. "$PROJECT_ROOT/lib/commands/init.sh"

if [ "$wrapper_name" = "gtr" ]; then
  eval "$(cmd_init bash)"
else
  eval "$(cmd_init bash --as "$wrapper_name")"
fi

_git_gtr() {
  printf 'WORDS=%s\n' "${COMP_WORDS[*]}"
  printf 'CWORD=%s\n' "$COMP_CWORD"
  printf 'LINE=%s\n' "$COMP_LINE"
  printf 'POINT=%s\n' "$COMP_POINT"
  COMPREPLY=(--from)
}

completion_fn="_${wrapper_name}_completion"
COMP_WORDS=("${words[@]}")
COMP_CWORD="$comp_cword"
COMP_LINE="$comp_line"
COMP_POINT="$comp_point"
COMPREPLY=(stale-reply)
"$completion_fn"

printf 'REPLY=%s\n' "${COMPREPLY[*]-}"
BASH
}

# Complete a prefix against real registered worktrees in a disposable repository,
# checking that candidate generation never executes the marker payloads.
run_generated_bash_cd_completion() (
  set -e
  local wrapper_name="$1" prefix="$2" fixture branch index=0 comp_line
  shift 2
  fixture=$(mktemp -d)
  trap 'rm -rf "$fixture"' EXIT
  export PATH="$PROJECT_ROOT/bin:$PATH"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  git init --quiet "$fixture/repo with spaces"
  cd "$fixture/repo with spaces"
  git symbolic-ref HEAD refs/heads/main
  git -c user.name=Fixture -c user.email=fixture@example.test \
    commit --allow-empty --quiet -m init
  git branch unregistered-target
  for branch in "$@"; do
    git check-ref-format --branch "$branch" >/dev/null
    index=$((index + 1))
    git worktree add --quiet -b "$branch" "$fixture/wt-$index"
  done
  comp_line="$wrapper_name cd $prefix"
  run_generated_bash_wrapper_completion "$wrapper_name" "$comp_line" 2 \
    "${#comp_line}" "$wrapper_name" cd "$prefix"
  # Both payloads only create a marker in this disposable repository if evaluated.
  [ ! -e completion-dollar-marker ]
  [ ! -e completion-backtick-marker ]
)

# Run generated Bash/Zsh postCd hooks and report their execution order.
run_generated_post_cd_hooks() {
  local shell_name="$1"

  "$shell_name" -s -- "$PROJECT_ROOT" "$shell_name" <<'SCRIPT'
PROJECT_ROOT="$1"
shell_name="$2"

log_info() { :; }
log_warn() { :; }
log_error() { :; }
show_command_help() { :; }
compdef() { :; }

# shellcheck disable=SC1090
. "$PROJECT_ROOT/lib/commands/init.sh"

repo=$(mktemp -d)
cleanup() {
  rm -rf "$repo"
}
trap cleanup EXIT

git -C "$repo" init --quiet
git -C "$repo" config user.name "Test User"
git -C "$repo" config user.email "test@example.com"
git -C "$repo" -c commit.gpgsign=false commit --allow-empty -m "init" --quiet

git -C "$repo" config --add gtr.hook.postCd 'echo first >> "$REPO_ROOT/order"'
git -C "$repo" config --add gtr.hook.postCd 'cat'
git -C "$repo" config --add gtr.hook.postCd 'echo third >> "$REPO_ROOT/order"'

eval "$(cmd_init "$shell_name")"
gtr_run_post_cd_hooks "$repo"

printf 'ORDER='
paste -sd, "$repo/order"
printf '\n'
SCRIPT
}

# Exercise generated Fish hooks against a trusted or untrusted shared config.
run_generated_fish_gtrconfig_post_cd_hooks() {
  local trust_state="$1"
  local without_shasum="${2:-0}"
  local root repo wt xdg init_file fish_path

  root=$(cd -P "$(mktemp -d)" && pwd)
  repo="$root/repo"
  wt="$root/wt"
  xdg="$root/xdg"
  init_file="$root/gtr.fish"
  fish_path="$PATH"

  git init --quiet "$repo"
  git -C "$repo" config user.name "Test User"
  git -C "$repo" config user.email "test@example.com"
  git -C "$repo" -c commit.gpgsign=false commit --allow-empty -m "init" --quiet
  git -C "$repo" worktree add --quiet "$wt" -b feature

  cat > "$repo/.gtrconfig" <<'CFG'
[hooks]
  postCd = pwd > "$WORKTREE_PATH/hook-pwd"
  postCd = echo second >> "$WORKTREE_PATH/hook-order"
[defaults]
  ai = codex
CFG

  cmd_init fish > "$init_file"

  if [ "$trust_state" = "trusted" ]; then
    (
      export XDG_CONFIG_HOME="$xdg"
      # shellcheck disable=SC1091
      . "$PROJECT_ROOT/lib/hooks.sh"
      _hooks_mark_trusted "$repo/.gtrconfig"
    )
  fi

  if [ "$without_shasum" -eq 1 ]; then
    fish_path=$(path_without_command "$root/bin" shasum)
  fi

  PATH="$fish_path" XDG_CONFIG_HOME="$xdg" fish -c '
    source "$argv[1]"
    set -l wt "$argv[2]"
    set -l root "$argv[3]"

    cd /
    gtr_run_post_cd_hooks "$wt" > "$root/stdout" 2> "$root/stderr"
    set -l rc $status

    printf "RC=%s\n" "$rc"
    printf "PWD=%s\n" "$PWD"
    printf "WT=%s\n" "$wt"
    if test -f "$wt/hook-pwd"
      printf "HOOK_PWD=%s\n" (cat "$wt/hook-pwd")
    else
      printf "HOOK_PWD=<missing>\n"
    end
    if test -f "$wt/hook-order"
      printf "HOOK_ORDER=%s\n" (paste -sd, "$wt/hook-order")
    else
      printf "HOOK_ORDER=<missing>\n"
    end
    printf "STDERR=%s\n" (cat "$root/stderr")
  ' -- "$init_file" "$wt" "$root"
  local rc=$?

  rm -rf "$root"
  return "$rc"
}

require_runtime_shell() {
  local shell_name="$1"

  command -v "$shell_name" >/dev/null 2>&1 || skip "$shell_name is not installed"
}

# Use real generated hooks and a harmless delegated script. Keep the definitions
# and canonical path identical when replacing the Git directory.
run_generated_replacement_repo_hooks() (
  set -e
  local shell_name="$1" fixture
  fixture=$(mktemp -d)
  trap 'rm -rf "$fixture"' EXIT
  export REPO_FIXTURE="$fixture/repo with spaces"
  export INIT_FIXTURE="$fixture/init.$shell_name"
  export XDG_CONFIG_HOME="$fixture/config"
  mkdir -p "$REPO_FIXTURE"
  git -C "$REPO_FIXTURE" init --quiet
  git -C "$REPO_FIXTURE" -c user.name=Fixture -c user.email=fixture@example.test \
    -c commit.gpgsign=false commit --allow-empty --quiet -m initial
  git config -f "$REPO_FIXTURE/.gtrconfig" hooks.postCd 'sh "$REPO_ROOT/bootstrap.sh"'
  printf 'echo original > "$REPO_ROOT/hook-result"\n' > "$REPO_FIXTURE/bootstrap.sh"
  source "$PROJECT_ROOT/lib/hooks.sh"
  _hooks_mark_trusted "$REPO_FIXTURE/.gtrconfig"
  cmd_init "$shell_name" > "$INIT_FIXTURE"
  "$shell_name" -c 'source "$INIT_FIXTURE"; gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ "$(cat "$REPO_FIXTURE/hook-result")" = original ]
  # Verify every generated identity helper fails closed without birth times.
  mkdir "$fixture/bin"
  printf '#!/bin/sh\necho 1:2:0.000000000\n' > "$fixture/bin/stat"
  chmod +x "$fixture/bin/stat"
  if PATH="$fixture/bin:$PATH" "$shell_name" -c 'source "$INIT_FIXTURE"; gtr_hooks_repo_identity "$REPO_FIXTURE"'; then
    return 1
  fi
  mv "$REPO_FIXTURE/.git" "$fixture/original-git"
  git -C "$REPO_FIXTURE" init --quiet
  printf 'echo replacement > "$REPO_ROOT/hook-result"\n' > "$REPO_FIXTURE/bootstrap.sh"
  rm "$REPO_FIXTURE/hook-result"
  "$shell_name" -c 'source "$INIT_FIXTURE"; gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ ! -f "$REPO_FIXTURE/hook-result" ]
)

@test "bash generated hooks reject replacement repo with identical definitions" {
  run run_generated_replacement_repo_hooks bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"Untrusted .gtrconfig hooks skipped"* ]]
}

@test "zsh generated hooks reject replacement repo with identical definitions" {
  require_runtime_shell zsh
  run run_generated_replacement_repo_hooks zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Untrusted .gtrconfig hooks skipped"* ]]
}

@test "fish generated hooks reject replacement repo with identical definitions" {
  require_runtime_shell fish
  run run_generated_replacement_repo_hooks fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"Untrusted .gtrconfig hooks skipped"* ]]
}

# Freeze PR207's v2 approval format (2e414ca), including its original stat
# format and line-based definition hash. Do not derive it from current helpers:
# both the serialization and GNU birth-time representation changed in PR211.
mark_pr207_commands_trusted() {
  local config_file="$1" repo_root common_dir identity definitions hash key
  repo_root=$(cd "$(dirname "$config_file")" && pwd -P)
  common_dir=$(git -C "$repo_root" rev-parse --git-common-dir)
  common_dir=$(cd "$repo_root" && cd "$common_dir" && pwd -P)
  identity=$(LC_ALL=C stat -c '%d:%i:%.9W' "$common_dir" 2>/dev/null) ||
    identity=$(LC_ALL=C stat -f '%d:%i:%.9FB' "$common_dir") || return 1
  definitions=$(git config -f "$config_file" --get-regexp '^hooks\.|^defaults\.editor$|^defaults\.ai$')
  hash=$(printf '%s\n' "$definitions" | shasum -a 256 | cut -d' ' -f1)
  key=$(printf 'v2\n%s\n%s\n%s\n%s\n' "$repo_root" "$common_dir" "$identity" "$hash" |
    shasum -a 256 | cut -d' ' -f1)
  mkdir -p "$XDG_CONFIG_HOME/gtr/trusted"
  printf '%s/.gtrconfig\n' "$repo_root" > "$XDG_CONFIG_HOME/gtr/trusted/$key"
}

# Verify that generated shell helpers reject v2 trust and honor fresh approval.
run_generated_v2_trust_upgrade() (
  set -e
  local shell_name="$1" fixture
  fixture=$(mktemp -d)
  trap 'rm -rf "$fixture"' EXIT
  export REPO_FIXTURE="$fixture/repo with spaces" INIT_FIXTURE="$fixture/init.$shell_name"
  export XDG_CONFIG_HOME="$fixture/config" XDG_DATA_HOME="$fixture/data"
  git init --quiet "$REPO_FIXTURE"
  git -C "$REPO_FIXTURE" -c user.name=Fixture -c user.email=fixture@example.test \
    -c commit.gpgsign=false commit --allow-empty --quiet -m init
  git config -f "$REPO_FIXTURE/.gtrconfig" hooks.postCd 'sh "$REPO_ROOT/bootstrap.sh"'
  printf 'echo original > "$REPO_ROOT/hook-result"\n' > "$REPO_FIXTURE/bootstrap.sh"
  mark_pr207_commands_trusted "$REPO_FIXTURE/.gtrconfig"
  # Preserve the repository path, .git identity and command definition.
  printf 'echo replacement > "$REPO_ROOT/hook-result"\n' > "$REPO_FIXTURE/bootstrap.sh"
  cmd_init "$shell_name" > "$INIT_FIXTURE"
  "$shell_name" -c 'source "$INIT_FIXTURE"; gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ ! -f "$REPO_FIXTURE/hook-result" ]
  source "$PROJECT_ROOT/lib/hooks.sh"
  _hooks_mark_trusted "$REPO_FIXTURE/.gtrconfig"
  "$shell_name" -c 'source "$INIT_FIXTURE"; gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ "$(cat "$REPO_FIXTURE/hook-result")" = replacement ]
  # Current trust still approves delegated code, rather than pinning its bytes.
  printf 'echo updated > "$REPO_ROOT/hook-result"\n' > "$REPO_FIXTURE/bootstrap.sh"
  "$shell_name" -c 'source "$INIT_FIXTURE"; gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ "$(cat "$REPO_FIXTURE/hook-result")" = updated ]
  rm "$REPO_FIXTURE/hook-result"
  git config -f "$REPO_FIXTURE/.gtrconfig" hooks.postCd 'echo changed > "$REPO_ROOT/hook-result"'
  "$shell_name" -c 'source "$INIT_FIXTURE"; gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ ! -f "$REPO_FIXTURE/hook-result" ]
)

@test "fresh bash helpers reject v2 approval and accept current approval" {
  run run_generated_v2_trust_upgrade bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"Untrusted .gtrconfig hooks skipped"* ]]
}

@test "fresh zsh helpers reject v2 approval and accept current approval" {
  require_runtime_shell zsh
  run run_generated_v2_trust_upgrade zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"Untrusted .gtrconfig hooks skipped"* ]]
}

@test "fresh fish helpers reject v2 approval and accept current approval" {
  require_runtime_shell fish
  run run_generated_v2_trust_upgrade fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"Untrusted .gtrconfig hooks skipped"* ]]
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
  [[ "$output" == *'"cd new pr go run'* ]]
}

@test "bash output includes trust in subcommand completions" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *'init trust help version'* ]]
}

@test "bash output uses git gtr list --porcelain for cd completion" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr list --porcelain"* ]]
}

@test "bash cd completion filters ordinary branch prefixes" {
  run run_generated_bash_cd_completion gtr feature/a feature/auth feature/api bugfix
  [ "$status" -eq 0 ]
  [ "$output" = "REPLY=feature/api feature/auth" ]
}

@test "bash cd completion includes the main worktree alias" {
  run run_generated_bash_cd_completion gtr 1 feature/auth
  [ "$status" -eq 0 ]
  [ "$output" = "REPLY=1" ]
}

@test "bash cd completion excludes branches without registered worktrees" {
  run run_generated_bash_cd_completion gtr unregistered feature/auth
  [ "$status" -eq 0 ]
  [ "$output" = "REPLY=" ]
}

@test "bash cd completion keeps dollar command substitutions literal" {
  run run_generated_bash_cd_completion gtr 'feature/$(' \
    'feature/$(>completion-dollar-marker)' 'feature/`>completion-backtick-marker`'
  [ "$status" -eq 0 ]
  [ "$output" = 'REPLY=feature/\$\(\>completion-dollar-marker\)' ]
}

@test "bash cd completion keeps backtick substitutions literal with a custom wrapper" {
  run run_generated_bash_cd_completion gwtr 'feature/`' \
    'feature/$(>completion-dollar-marker)' 'feature/`>completion-backtick-marker`'
  [ "$status" -eq 0 ]
  [ "$output" = 'REPLY=feature/\`\>completion-backtick-marker\`' ]
}

@test "bash cd completion with an empty prefix preserves every literal candidate" {
  run run_generated_bash_cd_completion gtr '' \
    'feature/$(>completion-dollar-marker)' 'feature/`>completion-backtick-marker`'
  [ "$status" -eq 0 ]
  [ "$output" = 'REPLY=1 main feature/\$\(\>completion-dollar-marker\) feature/\`\>completion-backtick-marker\`' ]
}

@test "bash cd completion filters prefixes already escaped by Readline" {
  run run_generated_bash_cd_completion gwtr 'feature/\$\(\>completion-dollar-marker\)-m' \
    'feature/$(>completion-dollar-marker)-more' 'feature/$(>completion-dollar-marker)-other'
  [ "$status" -eq 0 ]
  [ "$output" = 'REPLY=feature/\$\(\>completion-dollar-marker\)-more' ]
}

@test "bash cd completion clears unmatched replies under set -e and treats prefixes literally" {
  local prefix
  for prefix in missing 'feature/*'; do
    run run_generated_bash_cd_completion gtr "$prefix" feature/auth
    [ "$status" -eq 0 ]
    [ "$output" = "REPLY=" ]
  done
}

@test "generated wrappers resolve .gtrconfig from the git common dir" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"git rev-parse --git-common-dir"* ]]
  [[ "$output" == *'printf '\''%s/.gtrconfig\n'\'''* ]]
}

@test "generated wrappers scope trust markers by repo root" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"hooks_current_trust_key"* ]]
  [[ "$output" == *"hooks_repo_root"* ]]
}

@test "generated wrappers validate trust marker contents" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"hooks_marker_matches_config"* ]]
  [[ "$output" == *"hooks_are_trusted"* ]]
  [[ "$output" == *'cat "$_gtr_trust_path"'* ]]
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

@test "generated bash wrapper recognizes trust markers when shasum is not installed" {
  local root repo xdg no_shasum_path
  root=$(mktemp -d)
  repo="$root/repo"
  xdg="$root/xdg"

  git init --quiet "$repo"
  cat > "$repo/.gtrconfig" <<'CFG'
[hooks]
  postCd = echo hi
CFG

  (
    export XDG_CONFIG_HOME="$xdg"
    # shellcheck disable=SC1091
    . "$PROJECT_ROOT/lib/hooks.sh"
    _hooks_mark_trusted "$repo/.gtrconfig"
  )

  no_shasum_path=$(path_without_command "$root/bin" shasum)
  run env PATH="$no_shasum_path" bash -c 'eval "$1" && gtr_hooks_are_trusted "$2" "$3"' \
    _ "$(cmd_init bash)" "$repo/.gtrconfig" "$xdg/gtr/trusted"
  rm -rf "$root"

  [ "$status" -eq 0 ]
}

@test "zsh output validates trust marker contents" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"hooks_canonical_config_path"* ]]
  [[ "$output" == *"hooks_marker_matches_config"* ]]
  [[ "$output" == *'cat "$_gtr_trust_path"'* ]]
}

@test "fish output includes cd subcommand completion" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"-a cd -d"* ]]
}

@test "fish output includes trust subcommand completion" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"-a trust -d"* ]]
}

@test "fish output uses git gtr list --porcelain for cd completion" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr list --porcelain"* ]]
}

@test "fish output validates trust marker contents" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"hooks_canonical_config_path"* ]]
  [[ "$output" == *"hooks_marker_matches_config"* ]]
  [[ "$output" == *'cat "$_gtr_trust_path"'* ]]
}

@test "fish output strips linked-worktree git common dir suffix" {
  require_runtime_shell fish

  run cmd_init fish
  [ "$status" -eq 0 ]

  local pattern
  pattern=$(printf '%s\n' "$output" | sed -n "s/.*string replace -r '\([^']*\)'.*/\1/p" | head -n 1)
  [ "$pattern" = '/\.git$' ]

  run fish -c 'string replace -r -- $argv[1] "" /tmp/repo/.git' -- "$pattern"
  [ "$status" -eq 0 ]
  [ "$output" = "/tmp/repo" ]
}

@test "fish generated postCd skips untrusted gtrconfig hooks without changing cwd" {
  require_runtime_shell fish

  run run_generated_fish_gtrconfig_post_cd_hooks untrusted

  [ "$status" -eq 0 ]
  [[ "$output" == *"RC=0"* ]]
  [[ "$output" == *"HOOK_PWD=<missing>"* ]]
  [[ "$output" == *"HOOK_ORDER=<missing>"* ]]
  [[ "$output" == *"STDERR=gtr: Untrusted .gtrconfig hooks skipped"* ]]

  local pwd_line wt_line
  pwd_line=$(printf '%s\n' "$output" | sed -n 's/^PWD=//p')
  wt_line=$(printf '%s\n' "$output" | sed -n 's/^WT=//p')
  [ "$pwd_line" = "$wt_line" ]
}

@test "fish generated postCd trusts multi-entry gtrconfig hooks without changing cwd" {
  require_runtime_shell fish

  run run_generated_fish_gtrconfig_post_cd_hooks trusted

  [ "$status" -eq 0 ]
  [[ "$output" == *"RC=0"* ]]
  [[ "$output" == *"HOOK_ORDER=second"* ]]
  [[ "$output" == *"STDERR="* ]]

  local pwd_line wt_line hook_pwd_line
  pwd_line=$(printf '%s\n' "$output" | sed -n 's/^PWD=//p')
  wt_line=$(printf '%s\n' "$output" | sed -n 's/^WT=//p')
  hook_pwd_line=$(printf '%s\n' "$output" | sed -n 's/^HOOK_PWD=//p')
  [ "$pwd_line" = "$wt_line" ]
  [ "$hook_pwd_line" = "$wt_line" ]
}

@test "fish generated postCd trusts gtrconfig hooks when shasum is unavailable" {
  require_runtime_shell fish
  command -v sha256sum >/dev/null 2>&1 || skip "sha256sum is not installed"

  run run_generated_fish_gtrconfig_post_cd_hooks trusted 1

  [ "$status" -eq 0 ]
  [[ "$output" == *"RC=0"* ]]
  [[ "$output" == *"HOOK_ORDER=second"* ]]
  [[ "$output" == *"STDERR="* ]]
}

# ── new/pr --cd wrapper support ─────────────────────────────────────────────

@test "bash output intercepts new/pr --cd and strips flag before delegating" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *'[ "$1" = "new" ] || [ "$1" = "pr" ]'* ]]
  [[ "$output" == *'if [ "$_gtr_arg" = "--cd" ]'* ]]
  [[ "$output" == *'command git gtr "$_gtr_command" "${_gtr_command_args[@]}"'* ]]
  [[ "$output" == *'command git gtr "${_gtr_original_args[@]}"'* ]]
}

@test "zsh output intercepts new/pr --cd and strips flag before delegating" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *'[ "$1" = "new" ] || [ "$1" = "pr" ]'* ]]
  [[ "$output" == *'if [ "$_gtr_arg" = "--cd" ]'* ]]
  [[ "$output" == *'command git gtr "$_gtr_command" "${_gtr_command_args[@]}"'* ]]
  [[ "$output" == *'command git gtr "${_gtr_original_args[@]}"'* ]]
}

@test "fish output intercepts new/pr --cd and strips flag before delegating" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *'contains -- "$argv[1]" new pr'* ]]
  [[ "$output" == *'test "$_gtr_arg" = "--cd"'* ]]
  [[ "$output" == *'command git gtr $_gtr_command $_gtr_command_args'* ]]
}

@test "bash output uses worktree diff to locate the new directory for --cd" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"git worktree list --porcelain"* ]]
  [[ "$output" == *'run_post_cd_hooks "$_gtr_new_dir"'* ]]
  [[ "$output" == *'could not determine new directory for --cd'* ]]
}

@test "zsh output uses worktree diff to locate the new directory for --cd" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"git worktree list --porcelain"* ]]
  [[ "$output" == *'run_post_cd_hooks "$_gtr_new_dir"'* ]]
  [[ "$output" == *'could not determine new directory for --cd'* ]]
}

@test "bash generated postCd hooks continue after stdin read" {
  require_runtime_shell bash
  run run_generated_post_cd_hooks bash

  [ "$status" -eq 0 ]
  [ "$output" = "ORDER=first,third" ]
}

@test "zsh generated postCd hooks continue after stdin read" {
  require_runtime_shell zsh
  run run_generated_post_cd_hooks zsh

  [ "$status" -eq 0 ]
  [ "$output" = "ORDER=first,third" ]
}

@test "fish output uses worktree diff to locate the new directory for --cd" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"git worktree list --porcelain"* ]]
  [[ "$output" == *'run_post_cd_hooks "$_gtr_new_paths[1]"'* ]]
  [[ "$output" == *'could not determine new directory for --cd'* ]]
}

@test "bash wrapper completions include --cd for new" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *'compgen -W "--cd"'* ]]
}

@test "bash wrapper completion rewrites delegated context for ai targets" {
  run run_generated_bash_wrapper_completion gtr "gtr ai fe" 2 9 gtr ai fe

  [ "$status" -eq 0 ]
  [[ "$output" == *"WORDS=git gtr ai fe"* ]]
  [[ "$output" == *"CWORD=3"* ]]
  [[ "$output" == *"LINE=git gtr ai fe"* ]]
  [[ "$output" == *"POINT=13"* ]]
  [[ "$output" == *"REPLY=--from"* ]]
}

@test "bash wrapper completion rewrites delegated context for custom wrapper names" {
  run run_generated_bash_wrapper_completion gwtr "gwtr ai fe" 2 10 gwtr ai fe

  [ "$status" -eq 0 ]
  [[ "$output" == *"WORDS=git gtr ai fe"* ]]
  [[ "$output" == *"CWORD=3"* ]]
  [[ "$output" == *"LINE=git gtr ai fe"* ]]
  [[ "$output" == *"POINT=13"* ]]
  [[ "$output" == *"REPLY=--from"* ]]
}

@test "bash wrapper completion preserves delegated replies and appends --cd for new flags" {
  run run_generated_bash_wrapper_completion gtr "gtr new --c" 2 11 gtr new --c

  [ "$status" -eq 0 ]
  [[ "$output" == *"WORDS=git gtr new --c"* ]]
  [[ "$output" == *"CWORD=3"* ]]
  [[ "$output" == *"LINE=git gtr new --c"* ]]
  [[ "$output" == *"POINT=15"* ]]
  [[ "$output" == *"REPLY=--from --cd"* ]]
}

@test "zsh wrapper completions include --cd for new" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *'compadd -- --cd'* ]]
}

@test "fish wrapper completions include --cd for new" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"using_subcommand new"* ]]
  [[ "$output" == *"-l cd -d 'Create and cd into the new worktree'"* ]]
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

# ── fzf: general setup ──────────────────────────────────────────────────────

@test "bash output includes fzf detection for cd with no args" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"command -v fzf"* ]]
  [[ "$output" == *"--prompt='Worktree> '"* ]]
  [[ "$output" == *"--with-nth=2"* ]]
}

@test "zsh output includes fzf detection for cd with no args" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"command -v fzf"* ]]
  [[ "$output" == *"--prompt='Worktree> '"* ]]
  [[ "$output" == *"--with-nth=2"* ]]
}

@test "fish output includes fzf detection for cd with no args" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"type -q fzf"* ]]
  [[ "$output" == *"--prompt='Worktree> '"* ]]
  [[ "$output" == *"--with-nth=2"* ]]
}

# ── fzf: header shows all keybindings ───────────────────────────────────────

@test "bash fzf header lists all keybindings" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"enter:cd"* ]]
  [[ "$output" == *"ctrl-e:editor"* ]]
  [[ "$output" == *"ctrl-a:ai"* ]]
  [[ "$output" == *"ctrl-d:delete"* ]]
  [[ "$output" == *"ctrl-y:copy"* ]]
  [[ "$output" == *"ctrl-r:refresh"* ]]
}

@test "zsh fzf header lists all keybindings" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"enter:cd"* ]]
  [[ "$output" == *"ctrl-e:editor"* ]]
  [[ "$output" == *"ctrl-a:ai"* ]]
  [[ "$output" == *"ctrl-d:delete"* ]]
  [[ "$output" == *"ctrl-y:copy"* ]]
  [[ "$output" == *"ctrl-r:refresh"* ]]
}

@test "fish fzf header lists all keybindings" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"enter:cd"* ]]
  [[ "$output" == *"ctrl-e:editor"* ]]
  [[ "$output" == *"ctrl-a:ai"* ]]
  [[ "$output" == *"ctrl-d:delete"* ]]
  [[ "$output" == *"ctrl-y:copy"* ]]
  [[ "$output" == *"ctrl-r:refresh"* ]]
}

# ── fzf: enter (cd) ─────────────────────────────────────────────────────────

@test "bash fzf enter extracts path from selection field 1 and cd" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  # Selection is parsed with cut -f1 to get path, then cd
  [[ "$output" == *'cut -f1'* ]]
  [[ "$output" == *'cd "$dir"'* ]]
}

@test "zsh fzf enter extracts path from selection field 1 and cd" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *'cut -f1'* ]]
  [[ "$output" == *'cd "$dir"'* ]]
}

@test "fish fzf enter extracts path from selection and cd" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  # Fish uses string split to extract path, then cd
  [[ "$output" == *'string split'* ]]
  [[ "$output" == *'set dir'* ]]
  [[ "$output" == *'cd $dir'* ]]
}

@test "fish fzf enter keeps selection variables in function scope" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *'set -l _gtr_key'* ]]
  [[ "$output" == *'set -l _gtr_line'* ]]
  [[ "$output" == *'set _gtr_key ""'* ]]
  [[ "$output" == *'set _gtr_line "$_gtr_selection[1]"'* ]]
  [[ "$output" != *'set -l _gtr_key ""'* ]]
  [[ "$output" != *'set -l _gtr_line "$_gtr_selection[1]"'* ]]
}

# ── fzf: ctrl-e (editor) — via --expect ──────────────────────────────────────

@test "bash fzf ctrl-e handled via --expect for full terminal access" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"--expect=ctrl-n,ctrl-a,ctrl-e"* ]]
  [[ "$output" == *'git gtr editor'* ]]
}

@test "zsh fzf ctrl-e handled via --expect for full terminal access" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"--expect=ctrl-n,ctrl-a,ctrl-e"* ]]
  [[ "$output" == *'git gtr editor'* ]]
}

@test "fish fzf ctrl-e handled via --expect for full terminal access" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"--expect=ctrl-n,ctrl-a,ctrl-e"* ]]
  [[ "$output" == *'git gtr editor'* ]]
}

# ── fzf: ctrl-a (ai) — via --expect ─────────────────────────────────────────

@test "bash fzf ctrl-a runs git gtr ai after fzf exits" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"--expect=ctrl-n,ctrl-a,ctrl-e"* ]]
  [[ "$output" == *'git gtr ai'* ]]
}

@test "zsh fzf ctrl-a runs git gtr ai after fzf exits" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"--expect=ctrl-n,ctrl-a,ctrl-e"* ]]
  [[ "$output" == *'git gtr ai'* ]]
}

@test "fish fzf ctrl-a runs git gtr ai after fzf exits" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"--expect=ctrl-n,ctrl-a,ctrl-e"* ]]
  [[ "$output" == *'git gtr ai'* ]]
}

# ── fzf: ctrl-d (delete + reload) ───────────────────────────────────────────

@test "bash fzf ctrl-d runs git gtr rm and reloads list" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-d:execute(git gtr rm {s1} > /dev/tty 2>&1 < /dev/tty)+reload(git gtr list --ids)"* ]]
}

@test "zsh fzf ctrl-d runs git gtr rm and reloads list" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-d:execute(git gtr rm {s1} > /dev/tty 2>&1 < /dev/tty)+reload(git gtr list --ids)"* ]]
}

@test "fish fzf ctrl-d runs git gtr rm and reloads list" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-d:execute(git gtr rm {s1} > /dev/tty 2>&1 < /dev/tty)+reload(git gtr list --ids)"* ]]
}

# ── fzf: ctrl-y (copy) ──────────────────────────────────────────────────────

@test "bash fzf ctrl-y runs git gtr copy on selected identity" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-y:execute(git gtr copy {s1} > /dev/tty 2>&1 < /dev/tty)"* ]]
}

@test "zsh fzf ctrl-y runs git gtr copy on selected identity" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-y:execute(git gtr copy {s1} > /dev/tty 2>&1 < /dev/tty)"* ]]
}

@test "fish fzf ctrl-y runs git gtr copy on selected identity" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-y:execute(git gtr copy {s1} > /dev/tty 2>&1 < /dev/tty)"* ]]
}

# ── fzf: ctrl-r (refresh) ───────────────────────────────────────────────────

@test "bash fzf ctrl-r reloads worktree list" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-r:reload(git gtr list --ids)"* ]]
}

@test "zsh fzf ctrl-r reloads worktree list" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-r:reload(git gtr list --ids)"* ]]
}

@test "fish fzf ctrl-r reloads worktree list" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-r:reload(git gtr list --ids)"* ]]
}

# ── fzf: preview window ─────────────────────────────────────────────────────

@test "bash fzf preview shows git log and status" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"--preview="* ]]
  [[ "$output" == *"git gtr run {s1} git log --oneline --graph --color=always"* ]]
  [[ "$output" == *"git gtr run {s1} git status --short"* ]]
  [[ "$output" == *"--preview-window=right:50%"* ]]
}

@test "zsh fzf preview shows git log and status" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"--preview="* ]]
  [[ "$output" == *"git gtr run {s1} git log --oneline --graph --color=always"* ]]
  [[ "$output" == *"git gtr run {s1} git status --short"* ]]
  [[ "$output" == *"--preview-window=right:50%"* ]]
}

@test "fish fzf preview shows git log and status" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"--preview="* ]]
  [[ "$output" == *"git gtr run {s1} git log --oneline --graph --color=always"* ]]
  [[ "$output" == *"git gtr run {s1} git status --short"* ]]
  [[ "$output" == *"--preview-window=right:50%"* ]]
}

# ── fzf: fallback messages ──────────────────────────────────────────────────

@test "bash output shows fzf install hint when no args and no fzf" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *'Install fzf for an interactive picker'* ]]
}

@test "zsh output shows fzf install hint when no args and no fzf" {
  run cmd_init zsh
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

# ── ctrl-n (new worktree) in fzf picker ────────────────────────────────────

@test "bash output includes --expect=ctrl-n in fzf args" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"--expect=ctrl-n"* ]]
}

@test "zsh output includes --expect=ctrl-n in fzf args" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"--expect=ctrl-n"* ]]
}

@test "fish output includes --expect=ctrl-n in fzf args" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"--expect=ctrl-n"* ]]
}

@test "bash output includes ctrl-n:new in fzf header" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-n:new"* ]]
}

@test "zsh output includes ctrl-n:new in fzf header" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-n:new"* ]]
}

@test "fish output includes ctrl-n:new in fzf header" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-n:new"* ]]
}

@test "bash output includes git gtr new in ctrl-n handler" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *'git gtr new "$_gtr_branch"'* ]]
}

@test "zsh output includes git gtr new in ctrl-n handler" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *'git gtr new "$_gtr_branch"'* ]]
}

@test "fish output includes git gtr new in ctrl-n handler" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *'git gtr new "$_gtr_branch"'* ]]
}

@test "bash output prompts for branch name on ctrl-n" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *'Branch name: '* ]]
}

@test "zsh output prompts for branch name on ctrl-n" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *'Branch name: '* ]]
}

@test "fish output prompts for branch name on ctrl-n" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *'Branch name: '* ]]
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
  GTR_VERSION="9.9.9" run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"gtr()"* ]]
  [ -f "$XDG_CACHE_HOME/gtr/init-gtr.zsh" ]
}

@test "init returns cached output on second call" {
  # First call: generates and caches
  GTR_VERSION="9.9.9" run cmd_init bash
  [ "$status" -eq 0 ]
  local first_output="$output"
  # Second call: reads from cache
  GTR_VERSION="9.9.9" run cmd_init bash
  [ "$status" -eq 0 ]
  [ "$output" = "$first_output" ]
}

@test "cache invalidates when version changes" {
  # Generate with version 1.0.0
  GTR_VERSION="1.0.0" run cmd_init zsh
  [ "$status" -eq 0 ]
  # Check cache stamp
  local stamp
  stamp="$(head -1 "$XDG_CACHE_HOME/gtr/init-gtr.zsh")"
  [[ "$stamp" == *"version=1.0.0"* ]]
  # Regenerate with version 2.0.0
  GTR_VERSION="2.0.0" run cmd_init zsh
  [ "$status" -eq 0 ]
  stamp="$(head -1 "$XDG_CACHE_HOME/gtr/init-gtr.zsh")"
  [[ "$stamp" == *"version=2.0.0"* ]]
}

@test "cache invalidates when shell integration schema changes" {
  GTR_INIT_CACHE_VERSION="1" run cmd_init bash
  [ "$status" -eq 0 ]
  local stamp
  stamp="$(head -1 "$XDG_CACHE_HOME/gtr/init-gtr.bash")"
  [[ "$stamp" == *"init=1"* ]]

  GTR_INIT_CACHE_VERSION="2" run cmd_init bash
  [ "$status" -eq 0 ]
  stamp="$(head -1 "$XDG_CACHE_HOME/gtr/init-gtr.bash")"
  [[ "$stamp" == *"init=2"* ]]
}

@test "init invalidates older schemas at the same CLI version" {
  local shell_name func_name schema cache_file
  mkdir -p "$XDG_CACHE_HOME/gtr"
  for shell_name in bash zsh fish; do
    for func_name in gtr gwtr; do
      for schema in 17 16 15 14 13 12 11 10 9 8 7 6; do
        cache_file="$XDG_CACHE_HOME/gtr/init-$func_name.$shell_name"
        printf '# gtr-cache: version=test init=%s func=%s shell=%s\nold-cache\n' \
          "$schema" "$func_name" "$shell_name" > "$cache_file"
        run cmd_init "$shell_name" --as "$func_name"
        [ "$status" -eq 0 ]
        [[ "$output" != *old-cache* ]]
        [[ "$(head -1 "$cache_file")" == *"init=18"* ]]
      done
    done
  done
}

# Execute the published setup itself, so docs cannot silently bypass cmd_init's
# version/schema check. Include a future upgrade with the same schema as well.
run_documented_init_upgrade() (
  set -e
  local shell_name="$1" heading="$2" source_file snippet schema version cache_file cli_version
  export PATH="$PROJECT_ROOT/bin:$PATH"
  export XDG_CONFIG_HOME="$XDG_CACHE_HOME/config" XDG_DATA_HOME="$XDG_CACHE_HOME/data"
  export STALE_CACHE_MARKER="$XDG_CACHE_HOME/stale-executed"
  cache_file="$XDG_CACHE_HOME/gtr/init-gtr.$shell_name"
  mkdir -p "$XDG_CACHE_HOME/gtr"
  cli_version=$(git gtr --version)
  cli_version="${cli_version##* }"
  for source_file in README.md lib/commands/help.sh; do
    snippet=$(awk -v heading="$heading" '
      index($0, "# " heading " (add to ") { capture=1; next }
      capture && /^[[:space:]]*$/ { exit }
      capture { print }
    ' "$PROJECT_ROOT/$source_file")
    [ -n "$snippet" ]
    # Non-interactive zsh has no completion system; the setup only registers it.
    if [ "$shell_name" = zsh ]; then
      snippet='compdef() { :; }'$'\n'"$snippet"
    fi
    for schema in 6 7 8 9 10 11 12 13 14 15 16 17 18; do
      version="$cli_version"
      [ "$schema" != 18 ] || version=old-version
      printf '# gtr-cache: version=%s init=%s func=gtr shell=%s\n' \
        "$version" "$schema" "$shell_name" > "$cache_file"
      printf '%s\n' 'echo stale > "$STALE_CACHE_MARKER"' >> "$cache_file"
      "$shell_name" -c "$snippet"
      [ ! -f "$STALE_CACHE_MARKER" ]
      [[ "$(head -1 "$cache_file")" == *"version=$cli_version init=18 "* ]]
    done
  done
)

@test "documented bash setup checks installed version and schema before loading cache" {
  run run_documented_init_upgrade bash Bash
  [ "$status" -eq 0 ]
}

@test "documented zsh setup checks installed version and schema before loading cache" {
  require_runtime_shell zsh
  run run_documented_init_upgrade zsh Zsh
  [ "$status" -eq 0 ]
}

@test "documented fish setup checks installed version and schema before loading cache" {
  require_runtime_shell fish
  run run_documented_init_upgrade fish Fish
  [ "$status" -eq 0 ]
}

@test "cache uses --as func name in cache key" {
  GTR_VERSION="9.9.9" run cmd_init bash --as myfn
  [ "$status" -eq 0 ]
  [[ "$output" == *"myfn()"* ]]
  [ -f "$XDG_CACHE_HOME/gtr/init-myfn.bash" ]
}

@test "cache works for all shells" {
  for sh in bash zsh fish; do
    GTR_VERSION="9.9.9" run cmd_init "$sh"
    [ "$status" -eq 0 ]
    [ -f "$XDG_CACHE_HOME/gtr/init-gtr.${sh}" ]
  done
}

run_generated_snapshot_replacement_hooks() (
  set -e
  local shell_name="$1" fixture
  fixture=$(mktemp -d)
  trap 'rm -rf "$fixture"' EXIT
  export REPO_FIXTURE="$fixture/repo"
  export INIT_FIXTURE="$fixture/init.$shell_name"
  export XDG_CONFIG_HOME="$fixture/config"
  export REAL_GIT
  REAL_GIT=$(command -v git)
  mkdir -p "$REPO_FIXTURE" "$fixture/bin"
  git -C "$REPO_FIXTURE" init --quiet
  git -C "$REPO_FIXTURE" -c user.name=Fixture -c user.email=fixture@example.test \
    -c commit.gpgsign=false commit --allow-empty --quiet -m initial
  git config -f "$REPO_FIXTURE/.gtrconfig" hooks.postCd 'echo approved > "$REPO_ROOT/result"'
  source "$PROJECT_ROOT/lib/hooks.sh"
  _hooks_mark_trusted "$REPO_FIXTURE/.gtrconfig"
  cmd_init "$shell_name" > "$INIT_FIXTURE"
  cat > "$fixture/bin/git" <<'WRAPPER'
#!/usr/bin/env bash
if [ "$1" = config ] && [ "${2:-}" = -z ] && [ "${4:-}" = "$REPO_FIXTURE/.gtrconfig" ]; then
  "$REAL_GIT" "$@" > "$REPO_FIXTURE/captured"
  "$REAL_GIT" config -f "$REPO_FIXTURE/.gtrconfig" hooks.postCd 'echo attacker > "$REPO_ROOT/result"'
  cat "$REPO_FIXTURE/captured"
else
  exec "$REAL_GIT" "$@"
fi
WRAPPER
  chmod +x "$fixture/bin/git"
  PATH="$fixture/bin:$PATH" "$shell_name" -c 'source "$INIT_FIXTURE"; gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ "$(cat "$REPO_FIXTURE/result")" = approved ]
)

@test "generated shells execute the captured approved snapshot after pathname replacement" {
  local shell_name
  for shell_name in bash zsh fish; do
    command -v "$shell_name" >/dev/null || continue
    run run_generated_snapshot_replacement_hooks "$shell_name"
    [ "$status" -eq 0 ]
  done
}
