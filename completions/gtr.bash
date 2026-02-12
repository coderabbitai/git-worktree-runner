#!/bin/bash
# Bash completion for git gtr
#
# Prerequisites:
#   - bash-completion v2+ must be installed
#   - Git's bash completion must be enabled
#
# This completion integrates with git's completion system by defining a _git_<subcommand>
# function, which git's completion framework automatically discovers and calls when
# completing "git gtr ..." commands.
#
# Installation:
#   Add to your ~/.bashrc:
#     source /path/to/git-worktree-runner/completions/gtr.bash

_git_gtr() {
  local cur prev words cword
  _init_completion || return

  # words array for git subcommand: [git, gtr, <actual_command>, ...]
  # cword is the index of current word being completed

  # If we're completing the first argument after 'git gtr'
  if [ "$cword" -eq 2 ]; then
    COMPREPLY=($(compgen -W "new go run copy editor ai rm mv rename ls list clean doctor adapter config completion init help version" -- "$cur"))
    return 0
  fi

  local cmd="${words[2]}"

  # Commands that take branch names or '1' for main repo
  case "$cmd" in
    go|run|rm|mv|rename)
      if [ "$cword" -eq 3 ]; then
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
          mv|rename)
            COMPREPLY=($(compgen -W "--force --yes" -- "$cur"))
            ;;
        esac
      fi
      ;;
    editor)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--editor" -- "$cur"))
      elif [ "$prev" = "--editor" ]; then
        COMPREPLY=($(compgen -W "cursor vscode zed idea pycharm webstorm vim nvim emacs sublime nano atom none" -- "$cur"))
      else
        local branches all_options
        branches=$(git branch --format='%(refname:short)' 2>/dev/null || true)
        all_options="1 $branches"
        COMPREPLY=($(compgen -W "$all_options" -- "$cur"))
      fi
      ;;
    ai)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--ai" -- "$cur"))
      elif [ "$prev" = "--ai" ]; then
        COMPREPLY=($(compgen -W "aider auggie claude codex continue copilot cursor gemini opencode none" -- "$cur"))
      else
        local branches all_options
        branches=$(git branch --format='%(refname:short)' 2>/dev/null || true)
        all_options="1 $branches"
        COMPREPLY=($(compgen -W "$all_options" -- "$cur"))
      fi
      ;;
    ls|list)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--porcelain" -- "$cur"))
      fi
      ;;
    clean)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--merged --yes -y --dry-run -n" -- "$cur"))
      fi
      ;;
    copy)
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-n --dry-run -a --all --from" -- "$cur"))
      else
        # Complete with branch names and special ID '1' for main repo
        local branches all_options
        branches=$(git branch --format='%(refname:short)' 2>/dev/null || true)
        all_options="1 $branches"
        COMPREPLY=($(compgen -W "$all_options" -- "$cur"))
      fi
      ;;
    new)
      # Complete flags
      if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "--from --from-current --track --no-copy --no-fetch --no-hooks --force --name --folder --yes --editor -e --ai -a" -- "$cur"))
      elif [ "$prev" = "--track" ]; then
        COMPREPLY=($(compgen -W "auto remote local none" -- "$cur"))
      fi
      ;;
    completion|init)
      # Complete with shell names
      if [ "$cword" -eq 3 ]; then
        COMPREPLY=($(compgen -W "bash zsh fish" -- "$cur"))
      fi
      ;;
    config)
      # Find action by scanning all config args (handles flexible flag positioning)
      local config_action=""
      local i
      for (( i=3; i < cword; i++ )); do
        case "${words[i]}" in
          list|get|set|add|unset) config_action="${words[i]}" ;;
        esac
      done

      if [ -z "$config_action" ]; then
        # Still need to complete action or scope
        COMPREPLY=($(compgen -W "list get set add unset --local --global --system" -- "$cur"))
      else
        # Have action, complete based on it
        case "$config_action" in
          list|get)
            # Read operations support all scopes including --system
            if [[ "$cur" == -* ]]; then
              COMPREPLY=($(compgen -W "--local --global --system" -- "$cur"))
            else
              COMPREPLY=($(compgen -W "gtr.worktrees.dir gtr.worktrees.prefix gtr.defaultBranch gtr.editor.default gtr.editor.workspace gtr.ai.default gtr.provider gtr.copy.include gtr.copy.exclude gtr.copy.includeDirs gtr.copy.excludeDirs gtr.hook.postCreate gtr.hook.preRemove gtr.hook.postRemove gtr.hook.postCd" -- "$cur"))
            fi
            ;;
          set|add|unset)
            # Write operations only support --local and --global (--system requires root)
            if [[ "$cur" == -* ]]; then
              COMPREPLY=($(compgen -W "--local --global" -- "$cur"))
            else
              COMPREPLY=($(compgen -W "gtr.worktrees.dir gtr.worktrees.prefix gtr.defaultBranch gtr.editor.default gtr.editor.workspace gtr.ai.default gtr.provider gtr.copy.include gtr.copy.exclude gtr.copy.includeDirs gtr.copy.excludeDirs gtr.hook.postCreate gtr.hook.preRemove gtr.hook.postRemove gtr.hook.postCd" -- "$cur"))
            fi
            ;;
        esac
      fi
      ;;
  esac
}
