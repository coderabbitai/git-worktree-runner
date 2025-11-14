#!/bin/bash
# Bash completion for gtr

_gtr_completion() {
  local cur prev words cword
  _init_completion || return

  local cmd="${words[1]}"

  # Complete commands on first argument
  if [ "$cword" -eq 1 ]; then
    COMPREPLY=($(compgen -W "new go editor ai rm ls list clean doctor adapter config help version" -- "$cur"))
    return 0
  fi

  # Commands that take branch names or '1' for main repo
  case "$cmd" in
    go|editor|ai|rm)
      if [ "$cword" -eq 2 ]; then
        # Complete with branch names and special ID '1' for main repo
        local branches all_options
        branches=$(git branch --format='%(refname:short)' 2>/dev/null || true)
        all_options="1 $branches"
        COMPREPLY=($(compgen -W "$all_options" -- "$cur"))
      elif [[ "$cur" == -* ]]; then
        case "$cmd" in
          rm)
            COMPREPLY=($(compgen -W "--delete-branch --force --yes" -- "$cur"))
            ;;
        esac
      fi
      ;;
    new)
      # Complete flags
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--id --from --track --no-copy --no-fetch --force --name --yes" -- "$cur"))
      elif [ "$prev" = "--track" ]; then
        COMPREPLY=($(compgen -W "auto remote local none" -- "$cur"))
      fi
      ;;
    config)
      if [ "$cword" -eq 2 ]; then
        COMPREPLY=($(compgen -W "get set unset" -- "$cur"))
      elif [ "$cword" -eq 3 ]; then
        COMPREPLY=($(compgen -W "gtr.worktrees.dir gtr.worktrees.prefix gtr.defaultBranch gtr.editor.default gtr.ai.default gtr.copy.include gtr.copy.exclude gtr.hook.postCreate gtr.hook.postRemove" -- "$cur"))
      fi
      ;;
  esac
}

complete -F _gtr_completion gtr
