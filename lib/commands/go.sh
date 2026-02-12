#!/usr/bin/env bash

# Go command (navigate to worktree - prints path for shell integration)
# shellcheck disable=SC2154  # _pa_* set by parse_args, _ctx_* set by resolve_*
cmd_go() {
  parse_args "" "$@"

  if [ ${#_pa_positional[@]} -ne 1 ]; then
    log_error "Usage: git gtr go <id|branch>"
    exit 1
  fi

  local identifier="${_pa_positional[0]}"
  resolve_repo_context || exit 1

  local repo_root="$_ctx_repo_root" base_dir="$_ctx_base_dir" prefix="$_ctx_prefix"

  # Resolve target branch
  local is_main worktree_path branch
  resolve_worktree "$identifier" "$repo_root" "$base_dir" "$prefix" || exit 1

  is_main="$_ctx_is_main" worktree_path="$_ctx_worktree_path" branch="$_ctx_branch"

  # Human messages to stderr so stdout can be used in command substitution
  if [ "$is_main" = "1" ]; then
    echo "Main repo" >&2
  else
    echo "Worktree: $branch" >&2
  fi
  echo "Branch: $branch" >&2

  # Print path to stdout for shell integration: cd "$(gtr go my-feature)"
  printf "%s\n" "$worktree_path"
}