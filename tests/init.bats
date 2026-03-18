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
COMPREPLY=()
"$completion_fn"

printf 'REPLY=%s\n' "${COMPREPLY[*]}"
BASH
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

# ── new --cd wrapper support ────────────────────────────────────────────────

@test "bash output intercepts new --cd and strips flag before delegating" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *'[ "$1" = "new" ]'* ]]
  [[ "$output" == *'if [ "$_gtr_arg" = "--cd" ]'* ]]
  [[ "$output" == *'command git gtr new "${_gtr_new_args[@]}"'* ]]
  [[ "$output" == *'command git gtr "${_gtr_original_args[@]}"'* ]]
}

@test "zsh output intercepts new --cd and strips flag before delegating" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *'[ "$1" = "new" ]'* ]]
  [[ "$output" == *'if [ "$_gtr_arg" = "--cd" ]'* ]]
  [[ "$output" == *'command git gtr new "${_gtr_new_args[@]}"'* ]]
  [[ "$output" == *'command git gtr "${_gtr_original_args[@]}"'* ]]
}

@test "fish output intercepts new --cd and strips flag before delegating" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *'test "$argv[1]" = "new"'* ]]
  [[ "$output" == *'test "$_gtr_arg" = "--cd"'* ]]
  [[ "$output" == *'command git gtr new $_gtr_new_args'* ]]
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
  [[ "$output" == *"ctrl-d:execute(git gtr rm {2} > /dev/tty 2>&1 < /dev/tty)+reload(git gtr list --porcelain)"* ]]
}

@test "zsh fzf ctrl-d runs git gtr rm and reloads list" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-d:execute(git gtr rm {2} > /dev/tty 2>&1 < /dev/tty)+reload(git gtr list --porcelain)"* ]]
}

@test "fish fzf ctrl-d runs git gtr rm and reloads list" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-d:execute(git gtr rm {2} > /dev/tty 2>&1 < /dev/tty)+reload(git gtr list --porcelain)"* ]]
}

# ── fzf: ctrl-y (copy) ──────────────────────────────────────────────────────

@test "bash fzf ctrl-y runs git gtr copy on selected branch" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-y:execute(git gtr copy {2} > /dev/tty 2>&1 < /dev/tty)"* ]]
}

@test "zsh fzf ctrl-y runs git gtr copy on selected branch" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-y:execute(git gtr copy {2} > /dev/tty 2>&1 < /dev/tty)"* ]]
}

@test "fish fzf ctrl-y runs git gtr copy on selected branch" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-y:execute(git gtr copy {2} > /dev/tty 2>&1 < /dev/tty)"* ]]
}

# ── fzf: ctrl-r (refresh) ───────────────────────────────────────────────────

@test "bash fzf ctrl-r reloads worktree list" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-r:reload(git gtr list --porcelain)"* ]]
}

@test "zsh fzf ctrl-r reloads worktree list" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-r:reload(git gtr list --porcelain)"* ]]
}

@test "fish fzf ctrl-r reloads worktree list" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"ctrl-r:reload(git gtr list --porcelain)"* ]]
}

# ── fzf: preview window ─────────────────────────────────────────────────────

@test "bash fzf preview shows git log and status" {
  run cmd_init bash
  [ "$status" -eq 0 ]
  [[ "$output" == *"--preview="* ]]
  [[ "$output" == *"git -C {1} log --oneline --graph --color=always"* ]]
  [[ "$output" == *"git -C {1} status --short"* ]]
  [[ "$output" == *"--preview-window=right:50%"* ]]
}

@test "zsh fzf preview shows git log and status" {
  run cmd_init zsh
  [ "$status" -eq 0 ]
  [[ "$output" == *"--preview="* ]]
  [[ "$output" == *"git -C {1} log --oneline --graph --color=always"* ]]
  [[ "$output" == *"git -C {1} status --short"* ]]
  [[ "$output" == *"--preview-window=right:50%"* ]]
}

@test "fish fzf preview shows git log and status" {
  run cmd_init fish
  [ "$status" -eq 0 ]
  [[ "$output" == *"--preview="* ]]
  [[ "$output" == *"git -C {1} log --oneline --graph --color=always"* ]]
  [[ "$output" == *"git -C {1} status --short"* ]]
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
