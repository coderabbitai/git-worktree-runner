#!/usr/bin/env bash
# shellcheck disable=SC2154

# Copy command (copy files between worktrees)
cmd_copy() {
  local _spec
  _spec="--from: value
--dry-run|-n
--all|-a"
  parse_args "$_spec" "$@"

  local source="${_arg_from:-1}"  # Default: main repo
  local -a targets=("${_pa_positional[@]}")
  local all_mode="${_arg_all:-0}"
  local dry_run="${_arg_dry_run:-0}"

  # Convert passthrough args (after --) to newline-separated patterns
  local patterns=""
  local _p
  for _p in "${_pa_passthrough[@]}"; do
    if [ -n "$patterns" ]; then
      patterns="$patterns"$'\n'"$_p"
    else
      patterns="$_p"
    fi
  done

  # Validation
  if [ "$all_mode" -eq 0 ] && [ ${#targets[@]} -eq 0 ]; then
    log_error "Usage: git gtr copy <target>... [-n] [-a] [--from <source>] [-- <pattern>...]"
    exit 1
  fi

  # Get repo context
  resolve_repo_context || exit 1

  local repo_root="$_ctx_repo_root" base_dir="$_ctx_base_dir" prefix="$_ctx_prefix"

  # Resolve source path
  local src_path
  resolve_worktree "$source" "$repo_root" "$base_dir" "$prefix" || exit 1

  src_path="$_ctx_worktree_path"

  # Get patterns (flag > config + .worktreeinclude)
  local excludes
  if [ -z "$patterns" ]; then
    merge_copy_patterns "$repo_root"
  
    patterns="$_ctx_copy_includes" excludes="$_ctx_copy_excludes"
  else
    excludes=$(cfg_get_all gtr.copy.exclude copy.exclude)
  fi

  if [ -z "$patterns" ]; then
    log_error "No patterns specified. Use '-- <pattern>...' or configure gtr.copy.include"
    exit 1
  fi

  # Build target list for --all mode
  if [ "$all_mode" -eq 1 ]; then
    local all_branches
    all_branches=$(list_worktree_branches "$base_dir" "$prefix")
    if [ -z "$all_branches" ]; then
      log_error "No worktrees found"
      exit 1
    fi
    local _branch
    while IFS= read -r _branch; do
      [ -n "$_branch" ] && targets+=("$_branch")
    done <<< "$all_branches"
  fi

  # Process each target
  local copied_any=0
  local target_id
  for target_id in "${targets[@]}"; do
    local dst_path dst_branch
    resolve_worktree "$target_id" "$repo_root" "$base_dir" "$prefix" || continue
  
    dst_path="$_ctx_worktree_path" dst_branch="$_ctx_branch"

    # Skip if source == destination
    [ "$src_path" = "$dst_path" ] && continue

    if [ "$dry_run" -eq 1 ]; then
      log_step "[dry-run] Would copy to: $dst_branch"
      copy_patterns "$src_path" "$dst_path" "$patterns" "$excludes" "true" "true"
    else
      log_step "Copying to: $dst_branch"
      copy_patterns "$src_path" "$dst_path" "$patterns" "$excludes" "true"
    fi
    copied_any=1
  done

  if [ "$copied_any" -eq 0 ]; then
    log_warn "No files copied (source and target may be the same)"
  fi
}