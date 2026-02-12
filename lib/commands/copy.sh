#!/usr/bin/env bash

# Copy command (copy files between worktrees)
cmd_copy() {
  local source="1"  # Default: main repo
  local targets=""
  local patterns=""
  local all_mode=0
  local dry_run=0

  # Parse arguments (patterns come after -- separator, like git pathspec)
  while [ $# -gt 0 ]; do
    case "$1" in
      --from)
        source="$2"
        shift 2
        ;;
      -n|--dry-run)
        dry_run=1
        shift
        ;;
      -a|--all)
        all_mode=1
        shift
        ;;
      --)
        shift
        # Remaining args are patterns (like git pathspec)
        while [ $# -gt 0 ]; do
          if [ -n "$patterns" ]; then
            patterns="$patterns"$'\n'"$1"
          else
            patterns="$1"
          fi
          shift
        done
        break
        ;;
      -*)
        log_error "Unknown flag: $1"
        exit 1
        ;;
      *)
        targets="$targets $1"
        shift
        ;;
    esac
  done

  # Validation
  if [ "$all_mode" -eq 0 ] && [ -z "$targets" ]; then
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

  # Get patterns (flag > config)
  if [ -z "$patterns" ]; then
    patterns=$(cfg_get_all gtr.copy.include copy.include)
    # Also check .worktreeinclude
    if [ -f "$repo_root/.worktreeinclude" ]; then
      local file_patterns
      file_patterns=$(parse_pattern_file "$repo_root/.worktreeinclude")
      if [ -n "$file_patterns" ]; then
        if [ -n "$patterns" ]; then
          patterns="$patterns"$'\n'"$file_patterns"
        else
          patterns="$file_patterns"
        fi
      fi
    fi
  fi

  if [ -z "$patterns" ]; then
    log_error "No patterns specified. Use '-- <pattern>...' or configure gtr.copy.include"
    exit 1
  fi

  local excludes
  excludes=$(cfg_get_all gtr.copy.exclude copy.exclude)

  # Build target list for --all mode
  if [ "$all_mode" -eq 1 ]; then
    targets=$(list_worktree_branches "$base_dir" "$prefix")
    if [ -z "$targets" ]; then
      log_error "No worktrees found"
      exit 1
    fi
  fi

  # Process each target
  local copied_any=0
  for target_id in $targets; do
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