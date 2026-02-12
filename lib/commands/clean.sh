#!/usr/bin/env bash
# shellcheck disable=SC2154

# Clean command (remove prunable worktrees)
# Remove worktrees whose PRs/MRs are merged (handles squash merges)
# Usage: _clean_merged repo_root base_dir prefix yes_mode dry_run
_clean_merged() {
  local repo_root="$1" base_dir="$2" prefix="$3" yes_mode="$4" dry_run="$5"

  log_step "Checking for worktrees with merged PRs/MRs..."

  # Detect hosting provider (GitHub, GitLab, etc.)
  local provider
  provider=$(detect_provider) || true
  if [ -z "$provider" ]; then
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null || true)
    if [ -z "$remote_url" ]; then
      log_error "No remote URL configured for 'origin'"
    else
      # Sanitize URL to avoid leaking embedded credentials (e.g., https://token@host/...)
      local safe_url="${remote_url%%@*}"
      if [ "$safe_url" != "$remote_url" ]; then
        safe_url="<redacted>@${remote_url#*@}"
      fi
      log_error "Could not detect hosting provider from remote URL: $safe_url"
      log_info "Set manually: git gtr config set gtr.provider github  (or gitlab)"
    fi
    exit 1
  fi

  # Ensure provider CLI is available and authenticated
  ensure_provider_cli "$provider" || exit 1

  # Fetch latest from origin
  log_step "Fetching from origin..."
  git fetch origin --prune 2>/dev/null || log_warn "Could not fetch from origin"

  local removed=0
  local skipped=0

  # Get main repo branch to exclude it
  local main_branch
  main_branch=$(current_branch "$repo_root")

  # Iterate through worktree directories
  for dir in "$base_dir/${prefix}"*; do
    [ -d "$dir" ] || continue

    local branch
    branch=$(current_branch "$dir")

    if [ -z "$branch" ] || [ "$branch" = "(detached)" ]; then
      log_warn "Skipping $dir (detached HEAD)"
      skipped=$((skipped + 1))
      continue
    fi

    # Skip if same as main repo branch
    if [ "$branch" = "$main_branch" ]; then
      continue
    fi

    # Check if worktree has uncommitted changes
    if ! git -C "$dir" diff --quiet 2>/dev/null || \
       ! git -C "$dir" diff --cached --quiet 2>/dev/null; then
      log_warn "Skipping $branch (has uncommitted changes)"
      skipped=$((skipped + 1))
      continue
    fi

    # Check for untracked files
    if [ -n "$(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null)" ]; then
      log_warn "Skipping $branch (has untracked files)"
      skipped=$((skipped + 1))
      continue
    fi

    # Check if branch has a merged PR/MR
    if check_branch_merged "$provider" "$branch"; then
      if [ "$dry_run" -eq 1 ]; then
        log_info "[dry-run] Would remove: $branch ($dir)"
        removed=$((removed + 1))
      elif [ "$yes_mode" -eq 1 ] || prompt_yes_no "Remove worktree and delete branch '$branch'?"; then
        log_step "Removing worktree: $branch"
        local remove_output
        if remove_output=$(git worktree remove "$dir" 2>&1); then
          # Also delete the local branch
          git branch -d "$branch" 2>/dev/null || git branch -D "$branch" 2>/dev/null || true
          log_info "Removed: $branch"
          removed=$((removed + 1))
        else
          if [ -n "$remove_output" ]; then
            log_error "Failed to remove worktree: $remove_output"
          else
            log_error "Failed to remove worktree: $branch"
          fi
        fi
      else
        log_warn "Skipped: $branch (user declined)"
        skipped=$((skipped + 1))
      fi
    fi
    # Branches without merged PRs are silently skipped (this is the normal case)
  done

  echo ""
  if [ "$dry_run" -eq 1 ]; then
    log_info "Dry run complete. Would remove: $removed, Skipped: $skipped"
  else
    log_info "Merged cleanup complete. Removed: $removed, Skipped: $skipped"
  fi
}

cmd_clean() {
  local _spec
  _spec="--merged
--yes|-y
--dry-run|-n"
  parse_args "$_spec" "$@"

  local merged_mode="${_arg_merged:-0}"
  local yes_mode="${_arg_yes:-0}"
  local dry_run="${_arg_dry_run:-0}"

  log_step "Cleaning up stale worktrees..."

  # Run git worktree prune
  if git worktree prune 2>/dev/null; then
    log_info "Pruned stale worktree administrative files"
  fi

  resolve_repo_context || exit 1

  local repo_root="$_ctx_repo_root" base_dir="$_ctx_base_dir" prefix="$_ctx_prefix"

  if [ ! -d "$base_dir" ]; then
    log_info "No worktrees directory to clean"
    return 0
  fi

  # Find and remove empty directories
  local cleaned=0
  local empty_dirs
  empty_dirs=$(find "$base_dir" -maxdepth 1 -type d -empty 2>/dev/null | grep -v "^${base_dir}$" || true)

  if [ -n "$empty_dirs" ]; then
    while IFS= read -r dir; do
      if [ -n "$dir" ]; then
        if rmdir "$dir" 2>/dev/null; then
          cleaned=$((cleaned + 1))
          log_info "Removed empty directory: $(basename "$dir")"
        fi
      fi
    done <<EOF
$empty_dirs
EOF
  fi

  if [ "$cleaned" -gt 0 ]; then
    log_info "Cleanup complete ($cleaned director$([ "$cleaned" -eq 1 ] && echo 'y' || echo 'ies') removed)"
  else
    log_info "Cleanup complete (no empty directories found)"
  fi

  # --merged mode: remove worktrees with merged PRs/MRs (handles squash merges)
  if [ "$merged_mode" -eq 1 ]; then
    _clean_merged "$repo_root" "$base_dir" "$prefix" "$yes_mode" "$dry_run"
  fi
}