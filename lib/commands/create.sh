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
# Usage: _create_resolve_from_ref <from_ref> <from_current> <repo_root> [remote]
# Prints: resolved ref
_create_resolve_from_ref() {
  local from_ref="$1" from_current="$2" repo_root="$3" remote="${4:-$(resolve_default_remote)}"

  if [ -z "$from_ref" ]; then
    if [ "$from_current" -eq 1 ]; then
      from_ref=$(get_current_branch)
      if [ -z "$from_ref" ] || [ "$from_ref" = "HEAD" ]; then
        log_warn "Currently in detached HEAD state - falling back to default branch"
        from_ref="$remote/$(resolve_default_branch "$repo_root" "$remote")"
      else
        log_info "Creating from current branch: $from_ref"
      fi
    else
      from_ref="$remote/$(resolve_default_branch "$repo_root" "$remote")"
    fi
  fi

  printf "%s" "$from_ref"
}

# Print a stable, escaped record stream for scripting and agent integrations.
# Format: key<tab>value, one record per line.
_create_print_porcelain() {
  local worktree_path="$1" branch_name="$2" hook_status="$3"
  printf "path\t%s\n" "$(_tsv_escape_field "$worktree_path")"
  printf "branch\t%s\n" "$(_tsv_escape_field "$branch_name")"
  printf "hook_status\t%s\n" "$hook_status"
}

# Detect machine mode before parsing so all incidental stdout, including hook
# output, can be redirected away from the stable record stream.
_create_wants_porcelain() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --porcelain) return 0 ;;
      --) return 1 ;;
    esac
  done
  return 1
}

# shellcheck disable=SC2154  # _arg_* _pa_* set by parse_args, _ctx_* set by resolve_*
_cmd_create_impl() {
  local _spec
  _spec="--from: value
--from-current
--remote: value
--track: value
--no-copy
--no-fetch
--no-hooks
--sparse
--no-sparse
--yes
--force
--name: value
--folder: value
--porcelain
--editor|-e
--ai|-a"
  parse_args "$_spec" "$@"

  local branch_name="${_pa_positional[0]:-}"
  local from_ref="${_arg_from:-}"
  local from_current="${_arg_from_current:-0}"
  local remote="${_arg_remote:-$(resolve_default_remote)}"
  local track_mode="${_arg_track:-auto}"
  local skip_copy="${_arg_no_copy:-0}"
  local skip_fetch="${_arg_no_fetch:-0}"
  local skip_hooks="${_arg_no_hooks:-0}"
  local sparse_flag="${_arg_sparse:-0}"
  local no_sparse_flag="${_arg_no_sparse:-0}"
  local yes_mode="${_arg_yes:-0}"
  local force="${_arg_force:-0}"
  local custom_name="${_arg_name:-}"
  local folder_override="${_arg_folder:-}"
  local porcelain="${_arg_porcelain:-0}"
  local open_editor="${_arg_editor:-0}"
  local start_ai="${_arg_ai:-0}"

  if [ "$porcelain" -eq 1 ]; then
    yes_mode=1
    if [ "$open_editor" -eq 1 ] || [ "$start_ai" -eq 1 ]; then
      log_error "--porcelain cannot be combined with --editor or --ai"
      exit 1
    fi
  fi

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
  from_ref=$(_create_resolve_from_ref "$from_ref" "$from_current" "$repo_root" "$remote")

  # Decide whether to inherit sparse-checkout from the base worktree.
  # Precedence: --no-sparse > --sparse > gtr.sparse.inherit (default on).
  local sparse_inherit=0 native_sparse_supported=0
  _git_supports_sparse_inheritance && native_sparse_supported=1
  if [ "$no_sparse_flag" -eq 1 ]; then
    sparse_inherit=0
  elif [ "$sparse_flag" -eq 1 ]; then
    sparse_inherit=1
  elif [ "$native_sparse_supported" -eq 1 ] && cfg_bool gtr.sparse.inherit true; then
    sparse_inherit=1
  fi

  local sparse_source="" no_checkout=0
  if [ "$sparse_inherit" -eq 1 ]; then
    if [ "$native_sparse_supported" -eq 1 ]; then
      sparse_source=$(_resolve_sparse_source "$from_ref")
    elif [ "$sparse_flag" -eq 1 ]; then
      log_warn "Sparse-checkout inheritance requires Git 2.36+ — creating a full checkout"
    fi
    if [ -z "$sparse_source" ] && [ "$sparse_flag" -eq 1 ] && [ "$native_sparse_supported" -eq 1 ]; then
      log_warn "No sparse-checkout source found for '$from_ref' — creating a full checkout"
    fi
  fi

  # Git 2.36+ copies the caller's sparse settings during worktree add. Defer
  # checkout only when a sparse caller must produce a full checkout; ordinary
  # dense creation keeps the existing one-step path.
  local current_worktree=""
  if [ -z "$sparse_source" ] && [ "$native_sparse_supported" -eq 1 ]; then
    current_worktree=$(git rev-parse --show-toplevel 2>/dev/null || true)
    if _worktree_sparse_enabled "$current_worktree"; then
      no_checkout=1
    fi
  fi

  # Construct folder name for display
  local folder_name
  folder_name=$(_resolve_folder_name "$branch_name" "$custom_name" "$folder_override") || exit 1

  log_step "Creating worktree: $folder_name"
  echo "Location: $base_dir/${prefix}${folder_name}"
  echo "Branch: $branch_name"

  # Create the worktree
  local worktree_path
  # Only `git worktree add` uses sparse_source as its context; fetch and branch
  # resolution retain the caller's repository configuration.
  if ! worktree_path=$(create_worktree "$base_dir" "$prefix" "$branch_name" "$from_ref" "$track_mode" "$skip_fetch" "$force" "$custom_name" "$folder_override" "$remote" "$no_checkout" "$sparse_source"); then
    exit 1
  fi

  if [ -n "$sparse_source" ]; then
    if _worktree_is_sparse "$worktree_path"; then
      log_info "Inherited sparse-checkout from $sparse_source"
    else
      log_warn "Sparse-checkout inheritance was not applied — falling back to a full checkout"
      if ! _ensure_full_checkout "$worktree_path" 1; then
        log_error "Could not populate worktree at $worktree_path"
        exit 1
      fi
    fi
  elif [ "$no_checkout" -eq 1 ] && ! _ensure_full_checkout "$worktree_path" 1; then
    log_error "Could not populate full worktree at $worktree_path"
    exit 1
  fi

  # Copy files based on patterns
  if [ "$skip_copy" -eq 0 ]; then
    _post_create_copy "$repo_root" "$worktree_path"
  fi

  # Run post-create hooks (unless --no-hooks)
  local hook_status="disabled"
  if [ "$skip_hooks" -eq 0 ]; then
    hook_status=$(_hooks_phase_status postCreate)
    if ! run_hooks_in postCreate "$worktree_path" \
      REPO_ROOT="$repo_root" \
      WORKTREE_PATH="$worktree_path" \
      BRANCH="$branch_name"; then
      exit 1
    fi
  fi

  echo ""
  log_info "Worktree created: $worktree_path"

  if [ "$porcelain" -eq 1 ]; then
    _create_print_porcelain "$worktree_path" "$branch_name" "$hook_status" >&3
    return 0
  fi

  # Auto-launch editor/AI or show next steps
  [ "$open_editor" -eq 1 ] && { _auto_launch_editor "$worktree_path" || true; }
  [ "$start_ai" -eq 1 ] && { _auto_launch_ai "$worktree_path" "$repo_root" "$branch_name" || true; }
  if [ "$open_editor" -eq 0 ] && [ "$start_ai" -eq 0 ]; then
    _post_create_next_steps "$branch_name" "$folder_name" "$folder_override" "$repo_root" "$base_dir" "$prefix"
  fi
}

cmd_create() {
  if _create_wants_porcelain "$@"; then
    _cmd_create_impl "$@" 3>&1 1>&2
  else
    _cmd_create_impl "$@"
  fi
}
