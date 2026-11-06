#!/usr/bin/env bash

# Copy command (copy files between worktrees)
# shellcheck disable=SC2154  # _arg_* _pa_* set by parse_args, _ctx_* set by resolve_*/merge_copy_patterns
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
  local excludes dir_includes="" dir_excludes=""
  if [ -z "$patterns" ]; then
    merge_copy_patterns "$repo_root"
  
    patterns="$_ctx_copy_includes" excludes="$_ctx_copy_excludes"
    dir_includes=$(cfg_get_all gtr.copy.includeDirs copy.includeDirs)
    dir_excludes=$(cfg_get_all gtr.copy.excludeDirs copy.excludeDirs)
  else
    excludes=$(cfg_get_all gtr.copy.exclude copy.exclude)
  fi

  if [ -z "$patterns" ] && [ -z "$dir_includes" ]; then
    log_error "No patterns specified. Use '-- <pattern>...' or configure gtr.copy.include or gtr.copy.includeDirs"
    exit 1
  fi

  # Directory discovery depends only on the source. Resolve it once so --all
  # does not repeat the same filesystem scan for every target worktree.
  local resolved_dirs=""
  if [ -n "$dir_includes" ]; then
    resolved_dirs=$(_resolve_directory_patterns "$src_path" "$dir_includes") || exit 1
  fi

  # Build target list for --all mode
  if [ "$all_mode" -eq 1 ]; then
    local records line is_main="" found_worktree=0
    records=$(list_worktree_records "$repo_root") || exit 1
    # Branch names cannot distinguish duplicate checkouts or detached HEADs.
    # Keep paths escaped until resolve_worktree validates each exact identity.
    while IFS= read -r line; do
      case "$line" in
        "is_main "*) is_main="${line#is_main }" ;;
        "path "*)
          if [ "$is_main" = "0" ]; then
            targets+=("path:${line#path }")
            found_worktree=1
          fi
          ;;
      esac
    done <<< "$records"
    if [ "$found_worktree" -eq 0 ]; then
      log_error "No worktrees found"
      exit 1
    fi
  fi

  # Process each target
  local copied_any=0 resolved_worktree=0
  local target_id processed_path
  local -a processed_paths=()
  for target_id in "${targets[@]}"; do
    local dst_path dst_branch
    resolve_worktree "$target_id" "$repo_root" "$base_dir" "$prefix" || continue
  
    dst_path="$_ctx_worktree_path" dst_branch="$_ctx_branch"

    # Count resolved non-main targets before excluding the source so a
    # source-only --all remains a valid no-op.
    [ "$_ctx_is_main" = "0" ] && resolved_worktree=1

    # Skip if source == destination
    [ "$src_path" = "$dst_path" ] && continue

    # Explicit targets can overlap --all, including via branch/folder aliases.
    if [ "$all_mode" -eq 1 ]; then
      for processed_path in "${processed_paths[@]}"; do
        [ "$dst_path" = "$processed_path" ] && continue 2
      done
      processed_paths+=("$dst_path")
    fi

    if [ "$dry_run" -eq 1 ]; then
      log_step "[dry-run] Would copy to: $dst_branch"
      if [ -n "$patterns" ]; then
        copy_patterns "$src_path" "$dst_path" "$patterns" "$excludes" "true" "true" || return 1
      fi
      if [ -n "$resolved_dirs" ]; then
        _copy_resolved_directories "$src_path" "$dst_path" "$resolved_dirs" "$dir_excludes" "true" "$excludes" || return 1
      fi
    else
      log_step "Copying to: $dst_branch"
      if [ -n "$patterns" ]; then
        copy_patterns "$src_path" "$dst_path" "$patterns" "$excludes" "true" || return 1
      fi
      if [ -n "$resolved_dirs" ]; then
        _copy_resolved_directories "$src_path" "$dst_path" "$resolved_dirs" "$dir_excludes" "false" "$excludes" || return 1
      fi
    fi
    copied_any=1
  done

  if [ "$all_mode" -eq 1 ] && [ "$resolved_worktree" -eq 0 ]; then
    log_error "No worktrees found"
    return 1
  fi

  if [ "$copied_any" -eq 0 ]; then
    log_warn "No files copied (source and target may be the same)"
  fi
}
