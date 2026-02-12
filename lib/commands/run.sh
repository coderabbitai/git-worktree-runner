#!/usr/bin/env bash

# Run command (execute command in worktree directory)
cmd_run() {
  local identifier=""
  local -a run_args=()

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      -*)
        log_error "Unknown flag: $1"
        exit 1
        ;;
      *)
        if [ -z "$identifier" ]; then
          identifier="$1"
          shift
        else
          run_args=("$@")  # Capture all remaining args as the command
          break
        fi
        ;;
    esac
  done

  # Validation
  if [ -z "$identifier" ]; then
    log_error "Usage: git gtr run <id|branch> <command...>"
    exit 1
  fi

  if [ ${#run_args[@]} -eq 0 ]; then
    log_error "Usage: git gtr run <id|branch> <command...>"
    log_error "No command specified"
    exit 1
  fi

  resolve_repo_context || exit 1
  # shellcheck disable=SC2154
  local repo_root="$_ctx_repo_root" base_dir="$_ctx_base_dir" prefix="$_ctx_prefix"

  # Resolve target branch
  local is_main worktree_path branch
  resolve_worktree "$identifier" "$repo_root" "$base_dir" "$prefix" || exit 1
  # shellcheck disable=SC2154
  is_main="$_ctx_is_main" worktree_path="$_ctx_worktree_path" branch="$_ctx_branch"

  # Human messages to stderr (like cmd_go)
  if [ "$is_main" = "1" ]; then
    log_step "Running in: main repo"
  else
    log_step "Running in: $branch"
  fi
  echo "Command: ${run_args[*]}" >&2
  echo "" >&2

  # Execute command in worktree directory (exit code propagates)
  (cd "$worktree_path" && "${run_args[@]}")
}