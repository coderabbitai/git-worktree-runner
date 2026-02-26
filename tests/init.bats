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
