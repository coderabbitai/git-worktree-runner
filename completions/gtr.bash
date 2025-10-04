#!/bin/bash
# Bash completion for gtr

_gtr_completion() {
  local cur prev words cword
  _init_completion || return

  local cmd="${words[1]}"

  # Complete commands on first argument
  if [ "$cword" -eq 1 ]; then
    COMPREPLY=($(compgen -W "new go open ai rm ls list clean doctor adapter config help version" -- "$cur"))
    return 0
  fi

  # Commands that take worktree IDs or branch names
  case "$cmd" in
    go|open|ai|rm)
      if [ "$cword" -eq 2 ]; then
        # Complete with both IDs and branch names
        local ids branches all_options
        ids=$(command gtr list --ids 2>/dev/null || true)
        branches=$(git branch --format='%(refname:short)' 2>/dev/null || true)
        all_options="$ids $branches"
        COMPREPLY=($(compgen -W "$all_options" -- "$cur"))
      elif [[ "$cur" == -* ]]; then
        case "$cmd" in
          rm)
            COMPREPLY=($(compgen -W "--delete-branch --force --yes" -- "$cur"))
            ;;
          open)
            COMPREPLY=($(compgen -W "--editor" -- "$cur"))
            ;;
          ai)
            COMPREPLY=($(compgen -W "--tool" -- "$cur"))
            ;;
        esac
      elif [ "$prev" = "--editor" ]; then
        COMPREPLY=($(compgen -W "cursor vscode zed" -- "$cur"))
      elif [ "$prev" = "--tool" ]; then
        COMPREPLY=($(compgen -W "aider claudecode codex cursor continue" -- "$cur"))
      fi
      ;;
    new)
      # Complete flags
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--id --from --track --editor --ai --no-copy --no-fetch --yes" -- "$cur"))
      elif [ "$prev" = "--editor" ]; then
        COMPREPLY=($(compgen -W "cursor vscode zed" -- "$cur"))
      elif [ "$prev" = "--ai" ]; then
        COMPREPLY=($(compgen -W "aider claudecode codex cursor continue" -- "$cur"))
      elif [ "$prev" = "--track" ]; then
        COMPREPLY=($(compgen -W "auto remote local none" -- "$cur"))
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
