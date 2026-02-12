#!/usr/bin/env bash
# shellcheck disable=SC2154

# Remove command
cmd_remove() {
  local _spec
  _spec="--delete-branch
--yes
--force"
  parse_args "$_spec" "$@"

  local delete_branch="${_arg_delete_branch:-0}"
  local yes_mode="${_arg_yes:-0}"
  local force="${_arg_force:-0}"

  if [ ${#_pa_positional[@]} -eq 0 ]; then
    log_error "Usage: git gtr rm <id|branch> [<id|branch>...] [--delete-branch] [--force] [--yes]"
    exit 1
  fi

  resolve_repo_context || exit 1

  local repo_root="$_ctx_repo_root" base_dir="$_ctx_base_dir" prefix="$_ctx_prefix"

  for identifier in "${_pa_positional[@]}"; do
    # Resolve target branch
    local is_main worktree_path branch_name
    resolve_worktree "$identifier" "$repo_root" "$base_dir" "$prefix" || continue
  
    is_main="$_ctx_is_main" worktree_path="$_ctx_worktree_path" branch_name="$_ctx_branch"

    # Cannot remove main repository
    if [ "$is_main" = "1" ]; then
      log_error "Cannot remove main repository"
      continue
    fi

    log_step "Removing worktree: $(basename "$worktree_path")"

    # Run pre-remove hooks (abort on failure unless --force)
    if ! run_hooks_in preRemove "$worktree_path" \
      REPO_ROOT="$repo_root" \
      WORKTREE_PATH="$worktree_path" \
      BRANCH="$branch_name"; then
      if [ "$force" -eq 0 ]; then
        log_error "Pre-remove hook failed for $branch_name. Use --force to skip hooks."
        continue
      else
        log_warn "Pre-remove hook failed, continuing due to --force"
      fi
    fi

    # Remove the worktree
    if ! remove_worktree "$worktree_path" "$force"; then
      continue
    fi

    # Handle branch deletion
    if [ -n "$branch_name" ]; then
      if [ "$delete_branch" -eq 1 ]; then
        if [ "$yes_mode" -eq 1 ] || prompt_yes_no "Also delete branch '$branch_name'?"; then
          if git branch -D "$branch_name" 2>/dev/null; then
            log_info "Branch deleted: $branch_name"
          else
            log_warn "Could not delete branch: $branch_name"
          fi
        fi
      fi
    fi

    # Run post-remove hooks (don't abort on failure — worktree already removed)
    if ! run_hooks postRemove \
      REPO_ROOT="$repo_root" \
      WORKTREE_PATH="$worktree_path" \
      BRANCH="$branch_name"; then
      log_warn "Post-remove hook failed for $branch_name"
    fi
  done
}