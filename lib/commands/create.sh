#!/usr/bin/env bash

# Create command
# Copy files and directories to newly created worktree
# Usage: _post_create_copy repo_root worktree_path
# shellcheck disable=SC2154  # _ctx_copy_* set by merge_copy_patterns
_post_create_copy() {
  local repo_root="$1"
  local worktree_path="$2"

  merge_copy_patterns "$repo_root"

  local includes="$_ctx_copy_includes" excludes="$_ctx_copy_excludes"

  if [ -n "$includes" ]; then
    log_step "Copying files..."
    copy_patterns "$repo_root" "$worktree_path" "$includes" "$excludes"
  fi

  # Copy directories (typically git-ignored dirs like node_modules, .venv)
  local dir_includes dir_excludes
  dir_includes=$(cfg_get_all gtr.copy.includeDirs copy.includeDirs)
  dir_excludes=$(cfg_get_all gtr.copy.excludeDirs copy.excludeDirs)

  if [ -n "$dir_includes" ]; then
    log_step "Copying directories..."
    copy_directories "$repo_root" "$worktree_path" "$dir_includes" "$dir_excludes"
  fi
}

# Show next steps after worktree creation (resolves collision for --folder overrides)
# Usage: _post_create_next_steps branch_name folder_name folder_override repo_root base_dir prefix
# shellcheck disable=SC2154  # _ctx_is_main set by resolve_target/unpack_target
_post_create_next_steps() {
  local branch_name="$1" folder_name="$2" folder_override="$3"
  local repo_root="$4" base_dir="$5" prefix="$6"

  local next_steps_id
  if [ -n "$folder_override" ]; then
    # Check if folder_name would resolve to main repo (collision with current branch)
    local resolve_result
    if resolve_result=$(resolve_target "$folder_name" "$repo_root" "$base_dir" "$prefix" 2>/dev/null); then
      unpack_target "$resolve_result"
    
      if [ "$_ctx_is_main" = "1" ]; then
        # Collision: folder name matches current branch, use branch name instead
        next_steps_id="$branch_name"
      else
        next_steps_id="$folder_name"
      fi
    else
      next_steps_id="$folder_name"
    fi
  else
    next_steps_id="$branch_name"
  fi

  echo ""
  echo "Next steps:"
  echo "  git gtr editor $next_steps_id  # Open in editor"
  echo "  git gtr ai $next_steps_id      # Start AI tool"
  echo "  cd \"\$(git gtr go $next_steps_id)\"  # Navigate to worktree"
}

# Determine the base ref for worktree creation
# Usage: _create_resolve_from_ref <from_ref> <from_current> <repo_root>
# Prints: resolved ref
_create_resolve_from_ref() {
  local from_ref="$1" from_current="$2" repo_root="$3"

  if [ -z "$from_ref" ]; then
    if [ "$from_current" -eq 1 ]; then
      from_ref=$(get_current_branch)
      if [ -z "$from_ref" ] || [ "$from_ref" = "HEAD" ]; then
        log_warn "Currently in detached HEAD state - falling back to default branch"
        from_ref=$(resolve_default_branch "$repo_root")
      else
        log_info "Creating from current branch: $from_ref"
      fi
    else
      from_ref=$(resolve_default_branch "$repo_root")
    fi
  fi

  printf "%s" "$from_ref"
}
# shellcheck disable=SC2154  # _arg_* _pa_* set by parse_args, _ctx_* set by resolve_*
cmd_create() {
  local _spec
  _spec="--from: value
--from-current
--track: value
--no-copy
--no-fetch
--no-hooks
--yes
--force
--name: value
--folder: value
--editor|-e
--ai|-a"
  parse_args "$_spec" "$@"

  local branch_name="${_pa_positional[0]:-}"
  local from_ref="${_arg_from:-}"
  local from_current="${_arg_from_current:-0}"
  local track_mode="${_arg_track:-auto}"
  local skip_copy="${_arg_no_copy:-0}"
  local skip_fetch="${_arg_no_fetch:-0}"
  local skip_hooks="${_arg_no_hooks:-0}"
  local yes_mode="${_arg_yes:-0}"
  local force="${_arg_force:-0}"
  local custom_name="${_arg_name:-}"
  local folder_override="${_arg_folder:-}"
  local open_editor="${_arg_editor:-0}"
  local start_ai="${_arg_ai:-0}"

  # Validate flag combinations
  if [ -n "$folder_override" ] && [ -n "$custom_name" ]; then
    log_error "--folder and --name cannot be used together"
    exit 1
  fi

  if [ "$force" -eq 1 ] && [ -z "$custom_name" ] && [ -z "$folder_override" ]; then
    log_error "--force requires --name or --folder to distinguish worktrees"
    if [ -n "$branch_name" ]; then
      echo "Example: git gtr new $branch_name --force --name backend" >&2
      echo "     or: git gtr new $branch_name --force --folder my-folder" >&2
    else
      echo "Example: git gtr new feature-auth --force --name backend" >&2
      echo "     or: git gtr new feature-auth --force --folder my-folder" >&2
    fi
    exit 1
  fi

  # Get repo info
  resolve_repo_context || exit 1

  local repo_root="$_ctx_repo_root" base_dir="$_ctx_base_dir" prefix="$_ctx_prefix"

  # Get branch name if not provided
  if [ -z "$branch_name" ]; then
    if [ "$yes_mode" -eq 1 ]; then
      log_error "Branch name required in non-interactive mode"
      exit 1
    fi
    branch_name=$(prompt_input "Enter branch name:")
    if [ -z "$branch_name" ]; then
      log_error "Branch name required"
      exit 1
    fi
  fi

  # Determine from_ref with precedence: --from > --from-current > default
  from_ref=$(_create_resolve_from_ref "$from_ref" "$from_current" "$repo_root")

  # Construct folder name for display
  local folder_name
  if [ -n "$folder_override" ]; then
    folder_name=$(sanitize_branch_name "$folder_override")
  elif [ -n "$custom_name" ]; then
    folder_name="$(sanitize_branch_name "$branch_name")-${custom_name}"
  else
    folder_name=$(sanitize_branch_name "$branch_name")
  fi

  log_step "Creating worktree: $folder_name"
  echo "Location: $base_dir/${prefix}${folder_name}"
  echo "Branch: $branch_name"

  # Create the worktree
  local worktree_path
  if ! worktree_path=$(create_worktree "$base_dir" "$prefix" "$branch_name" "$from_ref" "$track_mode" "$skip_fetch" "$force" "$custom_name" "$folder_override"); then
    exit 1
  fi

  # Copy files based on patterns
  if [ "$skip_copy" -eq 0 ]; then
    _post_create_copy "$repo_root" "$worktree_path"
  fi

  # Run post-create hooks (unless --no-hooks)
  if [ "$skip_hooks" -eq 0 ]; then
    run_hooks_in postCreate "$worktree_path" \
      REPO_ROOT="$repo_root" \
      WORKTREE_PATH="$worktree_path" \
      BRANCH="$branch_name"
  fi

  echo ""
  log_info "Worktree created: $worktree_path"

  # Auto-launch editor/AI or show next steps
  [ "$open_editor" -eq 1 ] && { _auto_launch_editor "$worktree_path" || true; }
  [ "$start_ai" -eq 1 ] && { _auto_launch_ai "$worktree_path" || true; }
  if [ "$open_editor" -eq 0 ] && [ "$start_ai" -eq 0 ]; then
    _post_create_next_steps "$branch_name" "$folder_name" "$folder_override" "$repo_root" "$base_dir" "$prefix"
  fi
}