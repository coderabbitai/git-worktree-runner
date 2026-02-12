#!/usr/bin/env bash

# Rename command (rename worktree and branch)
# shellcheck disable=SC2154  # _arg_* _pa_* set by parse_args, _ctx_* set by resolve_*
cmd_rename() {
  local _spec
  _spec="--force
--yes"
  parse_args "$_spec" "$@"

  require_args 2 "Usage: git gtr mv <old> <new> [--force] [--yes]"

  local old_identifier="${_pa_positional[0]}"
  local new_name="${_pa_positional[1]}"
  local force="${_arg_force:-0}"
  local yes_mode="${_arg_yes:-0}"

  resolve_repo_context || exit 1

  local repo_root="$_ctx_repo_root" base_dir="$_ctx_base_dir" prefix="$_ctx_prefix"

  # Resolve old worktree
  local is_main old_path old_branch
  resolve_worktree "$old_identifier" "$repo_root" "$base_dir" "$prefix" || exit 1

  is_main="$_ctx_is_main" old_path="$_ctx_worktree_path" old_branch="$_ctx_branch"

  # Cannot rename main repository
  if [ "$is_main" = "1" ]; then
    log_error "Cannot rename main repository"
    exit 1
  fi

  # Sanitize new name and construct new path
  local new_sanitized new_path
  new_sanitized=$(sanitize_branch_name "$new_name")
  new_path="$base_dir/${prefix}${new_sanitized}"

  # Check if new path already exists
  if [ -d "$new_path" ]; then
    log_error "Worktree already exists at: $new_path"
    exit 1
  fi

  # Check if new branch name already exists
  if git -C "$repo_root" show-ref --verify --quiet "refs/heads/$new_name"; then
    log_error "Branch '$new_name' already exists"
    exit 1
  fi

  log_step "Renaming worktree"
  echo "Branch: $old_branch → $new_name"
  echo "Folder: $(basename "$old_path") → ${prefix}${new_sanitized}"

  # Confirm unless --yes
  if [ "$yes_mode" -eq 0 ]; then
    if ! prompt_yes_no "Proceed with rename?"; then
      log_info "Cancelled"
      exit 0
    fi
  fi

  # Rename the branch first
  if ! git -C "$repo_root" branch -m "$old_branch" "$new_name"; then
    log_error "Failed to rename branch"
    exit 1
  fi

  # Move the worktree
  local move_args=()
  if [ "$force" -eq 1 ]; then
    move_args+=(--force)
  fi

  if ! git -C "$repo_root" worktree move "${move_args[@]}" "$old_path" "$new_path"; then
    # Rollback: rename branch back
    log_warn "Worktree move failed, rolling back branch rename..."
    git -C "$repo_root" branch -m "$new_name" "$old_branch" 2>/dev/null || true
    log_error "Failed to move worktree"
    exit 1
  fi

  echo ""
  log_info "Renamed: $old_branch → $new_name"
  log_info "Location: $new_path"

  # Check if remote tracking branch exists and warn
  if git -C "$repo_root" show-ref --verify --quiet "refs/remotes/origin/$old_branch"; then
    echo ""
    log_warn "Remote branch 'origin/$old_branch' still exists"
    log_info "To update remote, run:"
    echo "  git push origin :$old_branch $new_name"
  fi
}