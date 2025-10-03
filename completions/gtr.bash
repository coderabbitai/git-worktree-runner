#!/bin/bash
# Bash completion for gtr

_gtr_completion() {
  local cur prev words cword
  _init_completion || return

  local cmd="${words[1]}"

  # Complete commands on first argument
  if [ "$cword" -eq 1 ]; then
    COMPREPLY=($(compgen -W "create rm remove cd open ai list config help version" -- "$cur"))
    return 0
  fi

  # Commands that take worktree IDs
  case "$cmd" in
    cd|open|ai|rm|remove)
      if [ "$cword" -eq 2 ]; then
        # Use gtr ids command for config-aware completion
        local ids
        ids=$(command gtr ids 2>/dev/null || true)
        COMPREPLY=($(compgen -W "$ids" -- "$cur"))
      fi
      ;;
    create)
      # Complete flags
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--branch --id --auto --from --track --open --ai --no-copy --yes" -- "$cur"))
      fi
      ;;
    open)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--editor" -- "$cur"))
      elif [ "$prev" = "--editor" ]; then
        COMPREPLY=($(compgen -W "cursor vscode zed" -- "$cur"))
      fi
      ;;
    ai)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--tool" -- "$cur"))
      elif [ "$prev" = "--tool" ]; then
        COMPREPLY=($(compgen -W "aider claudecode codex cursor continue" -- "$cur"))
      fi
      ;;
    config)
      if [ "$cword" -eq 2 ]; then
        COMPREPLY=($(compgen -W "get set unset" -- "$cur"))
      elif [ "$cword" -eq 3 ]; then
        COMPREPLY=($(compgen -W "gtr.worktrees.dir gtr.worktrees.prefix gtr.worktrees.startId gtr.defaultBranch gtr.editor.default gtr.ai.default gtr.copy.include gtr.copy.exclude gtr.hook.postCreate gtr.hook.postRemove" -- "$cur"))
      fi
      ;;
  esac
}

complete -F _gtr_completion gtr
