#!/usr/bin/env bash

# Clean command (remove prunable worktrees)

# Detect hosting provider with error messaging.
# Prints provider name on success; returns 1 on failure.
_clean_detect_provider() {
  local provider
  provider=$(detect_provider) || true
  if [ -n "$provider" ]; then
    printf "%s" "$provider"
    return 0
  fi

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
  return 1
}

# Check if a worktree should be skipped during PR/MR cleanup.
# Returns 0 if should skip, 1 if should process.
# Usage: _clean_should_skip <dir> <branch> [force] [active_worktree_path]
_clean_should_skip() {
  local dir="$1" branch="$2" force="${3:-0}" active_worktree_path="${4:-}"
  local dir_canonical="$dir"
  local active_worktree_canonical="$active_worktree_path"

  if [ -n "$active_worktree_path" ]; then
    dir_canonical=$(canonicalize_path "$dir" || printf "%s" "$dir")
    active_worktree_canonical=$(canonicalize_path "$active_worktree_path" || printf "%s" "$active_worktree_path")
  fi

  if [ -n "$active_worktree_path" ] && [ "$dir_canonical" = "$active_worktree_canonical" ]; then
    log_warn "Skipping $branch (current active worktree)"
    return 0
  fi

  if [ -z "$branch" ] || [ "$branch" = "(detached)" ]; then
    log_warn "Skipping $dir (detached HEAD)"
    return 0
  fi

  if [ "$force" -eq 0 ]; then
    if ! git -C "$dir" diff --quiet 2>/dev/null || \
       ! git -C "$dir" diff --cached --quiet 2>/dev/null; then
      log_warn "Skipping $branch (has uncommitted changes)"
      return 0
    fi

    if [ -n "$(git -C "$dir" ls-files --others --exclude-standard 2>/dev/null)" ]; then
      log_warn "Skipping $branch (has untracked files)"
      return 0
    fi
  fi

  return 1
}

# Recover registry entries that are locked but whose directories are gone
# (e.g. an agent session crashed after its worktree directory was deleted).
# `git worktree prune` skips locked entries by design, so they linger and
# keep their branches checked out in a phantom worktree.
# Usage: _clean_locked_phantoms repo_root yes_mode dry_run force
_clean_locked_phantoms() {
  local repo_root="$1" yes_mode="$2" dry_run="$3" force="${4:-0}"
  local records
  records=$(list_worktree_records "$repo_root")

  local is_main="" dir="" wt_status="" line unlocked=0
  while IFS= read -r line; do
    case "$line" in
      "")
        if [ -n "$dir" ] && [ "$is_main" != "1" ] && [ "$wt_status" = "locked" ] && [ ! -e "$dir" ]; then
          log_warn "Locked worktree entry with missing directory: $dir"
          if [ "$dry_run" -eq 1 ]; then
            log_info "[dry-run] Would unlock and prune: $dir"
          elif [ "$force" -eq 1 ] || [ "$yes_mode" -eq 1 ] || \
            prompt_yes_no "Unlock and prune '$dir'?"; then
            if git -C "$repo_root" worktree unlock "$dir" 2>/dev/null; then
              log_info "Unlocked missing worktree entry: $dir"
              unlocked=$((unlocked + 1))
            else
              log_warn "Could not unlock worktree entry: $dir"
            fi
          else
            log_info "Recover manually with: git worktree unlock '$dir' && git worktree prune"
          fi
        fi
        is_main=""
        dir=""
        wt_status=""
        ;;
      "is_main "*)
        is_main="${line#is_main }"
        ;;
      "path "*)
        dir=$(_tsv_unescape_field "${line#path }")
        ;;
      "status "*)
        wt_status="${line#status }"
        ;;
    esac
  done <<EOF
$records

EOF

  if [ "$unlocked" -gt 0 ]; then
    git -C "$repo_root" worktree prune 2>/dev/null || true
    log_info "Pruned $unlocked unlocked worktree entr$([ "$unlocked" -eq 1 ] && echo 'y' || echo 'ies')"
  fi
}

# Check if a branch has any requested PR/MR cleanup state.
# Returns 0 if matched, 1 if not.
# Usage: _clean_branch_matches_pr_state provider branch target_ref branch_tip merged_mode closed_mode
_clean_branch_matches_pr_state() {
  local provider="$1" branch="$2" target_ref="$3" branch_tip="$4" merged_mode="$5" closed_mode="$6"

  if [ "$merged_mode" -eq 1 ] && check_branch_merged "$provider" "$branch" "$target_ref" "$branch_tip"; then
    return 0
  fi

  if [ "$closed_mode" -eq 1 ] && check_branch_closed "$provider" "$branch" "$target_ref" "$branch_tip"; then
    return 0
  fi

  return 1
}

# Remove worktrees whose PRs/MRs match requested cleanup states (handles squash merges)
# Usage: _clean_prs repo_root base_dir prefix yes_mode dry_run [force] [active_worktree_path] [target_ref] [merged_mode] [closed_mode]
_clean_prs() {
  local repo_root="$1" base_dir="$2" prefix="$3" yes_mode="$4" dry_run="$5" force="${6:-0}" active_worktree_path="${7:-}" target_ref="${8:-}" merged_mode="${9:-0}" closed_mode="${10:-0}"

  # base_dir and prefix are kept for the helper contract. PR/MR cleanup uses
  # Git's registry so nested registered worktrees are processed directly.
  : "$base_dir" "$prefix"

  local cleanup_label="matching"
  if [ "$merged_mode" -eq 1 ] && [ "$closed_mode" -eq 1 ]; then
    cleanup_label="merged or closed"
  elif [ "$merged_mode" -eq 1 ]; then
    cleanup_label="merged"
  elif [ "$closed_mode" -eq 1 ]; then
    cleanup_label="closed"
  fi

  log_step "Checking for worktrees with $cleanup_label PRs/MRs..."

  local provider
  provider=$(_clean_detect_provider) || exit 1
  ensure_provider_cli "$provider" || exit 1

  log_step "Fetching from origin..."
  git fetch origin --prune 2>/dev/null || log_warn "Could not fetch from origin"

  local removed=0 skipped=0
  local main_branch
  main_branch=$(current_branch "$repo_root")
  local records
  records=$(list_worktree_records "$repo_root")

  local is_main="" dir="" branch="" line
  while IFS= read -r line; do
    case "$line" in
      "")
        if [ -n "$dir" ] && [ "$is_main" != "1" ]; then
          local branch_tip
          branch_tip=$(git -C "$dir" rev-parse HEAD 2>/dev/null || true)

          # Skip main repo branch silently (not counted)
          [ "$branch" = "$main_branch" ] && continue

          if _clean_should_skip "$dir" "$branch" "$force" "$active_worktree_path"; then
            skipped=$((skipped + 1))
            continue
          fi

          # Check if branch has a PR/MR matching any requested state
          if _clean_branch_matches_pr_state "$provider" "$branch" "$target_ref" "$branch_tip" "$merged_mode" "$closed_mode"; then
            if [ "$dry_run" -eq 1 ]; then
              log_info "[dry-run] Would remove: $branch ($dir)"
              removed=$((removed + 1))
            elif [ "$yes_mode" -eq 1 ] || prompt_yes_no "Remove worktree and delete branch '$branch'?"; then
              log_step "Removing worktree: $branch"

              if ! run_hooks_in preRemove "$dir" \
                REPO_ROOT="$repo_root" \
                WORKTREE_PATH="$dir" \
                BRANCH="$branch"; then
                log_warn "Pre-remove hook failed for $branch, skipping"
                skipped=$((skipped + 1))
                continue
              fi

              if remove_worktree "$dir" "$force"; then
                git branch -d "$branch" 2>/dev/null || git branch -D "$branch" 2>/dev/null || true
                removed=$((removed + 1))

                if ! run_hooks postRemove \
                  REPO_ROOT="$repo_root" \
                  WORKTREE_PATH="$dir" \
                  BRANCH="$branch"; then
                  log_warn "Post-remove hook failed for $branch"
                fi
              fi
            else
              log_warn "Skipped: $branch (user declined)"
              skipped=$((skipped + 1))
            fi
          fi
        fi
        is_main=""
        dir=""
        branch=""
        ;;
      "is_main "*)
        is_main="${line#is_main }"
        ;;
      "path "*)
        dir=$(_tsv_unescape_field "${line#path }")
        ;;
      "branch "*)
        branch=$(_tsv_unescape_field "${line#branch }")
        ;;
    esac
  done <<EOF
$records

EOF

  echo ""
  if [ "$dry_run" -eq 1 ]; then
    log_info "Dry run complete. Would remove: $removed, Skipped: $skipped"
  else
    log_info "PR cleanup complete. Removed: $removed, Skipped: $skipped"
  fi
}

# shellcheck disable=SC2154  # _arg_* set by parse_args, _ctx_* set by resolve_*
cmd_clean() {
  local _spec
  _spec="--merged
--closed
--to: value
--yes|-y
--dry-run|-n
--force|-f"
  parse_args "$_spec" "$@"

  local merged_mode="${_arg_merged:-0}"
  local closed_mode="${_arg_closed:-0}"
  local target_ref="${_arg_to:-}"
  local yes_mode="${_arg_yes:-0}"
  local dry_run="${_arg_dry_run:-0}"
  local force="${_arg_force:-0}"
  local active_worktree_path=""

  if [ -n "$target_ref" ] && [ "$merged_mode" -ne 1 ] && [ "$closed_mode" -ne 1 ]; then
    log_error "--to can only be used with --merged or --closed"
    return 1
  fi

  log_step "Cleaning up stale worktrees..."

  # Run git worktree prune
  if git worktree prune 2>/dev/null; then
    log_info "Pruned stale worktree administrative files"
  fi

  resolve_repo_context || exit 1

  local repo_root="$_ctx_repo_root" base_dir="$_ctx_base_dir" prefix="$_ctx_prefix"

  active_worktree_path=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [ -n "$active_worktree_path" ]; then
    active_worktree_path=$(canonicalize_path "$active_worktree_path" || printf "%s" "$active_worktree_path")
  fi

  # Locked entries with missing directories survive `git worktree prune`;
  # offer to unlock and prune them (may live outside base_dir)
  _clean_locked_phantoms "$repo_root" "$yes_mode" "$dry_run" "$force"

  if [ ! -d "$base_dir" ]; then
    log_info "No worktrees directory to clean"
    return 0
  fi

  # Find and remove empty directories
  local cleaned=0
  local empty_dirs
  empty_dirs=$(find "$base_dir" -maxdepth 1 -type d -empty 2>/dev/null | grep -Fxv "$base_dir" || true)

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

  # PR/MR cleanup mode: remove worktrees with matching PRs/MRs (handles squash merges)
  if [ "$merged_mode" -eq 1 ] || [ "$closed_mode" -eq 1 ]; then
    _clean_prs "$repo_root" "$base_dir" "$prefix" "$yes_mode" "$dry_run" "$force" "$active_worktree_path" "$target_ref" "$merged_mode" "$closed_mode"
  fi
}
