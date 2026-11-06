#!/usr/bin/env bash

# Remove explicit worktree targets, or preview them before hook dispatch.
# Usage: cmd_remove <target>... [--delete-branch] [--force] [--yes] [--dry-run|-n]
# shellcheck disable=SC2154  # _arg_* _pa_* set by parse_args, _ctx_* set by resolve_*
cmd_remove() {
  local _spec
  _spec="--delete-branch
--yes
--force
--dry-run|-n"
  parse_args "$_spec" "$@"

  require_args 1 "Usage: git gtr rm <id|branch> [<id|branch>...] [--delete-branch] [--force] [--yes] [--dry-run|-n]"

  local delete_branch="${_arg_delete_branch:-0}"
  local yes_mode="${_arg_yes:-0}"
  local force="${_arg_force:-0}"
  local dry_run="${_arg_dry_run:-0}"
  local had_failure=0

  resolve_repo_context || exit 1

  local repo_root="$_ctx_repo_root" base_dir="$_ctx_base_dir" prefix="$_ctx_prefix"

  for identifier in "${_pa_positional[@]}"; do
    # Resolve target branch
    local is_main worktree_path branch_name
    if ! resolve_worktree "$identifier" "$repo_root" "$base_dir" "$prefix"; then
      had_failure=1
      continue
    fi

    is_main="$_ctx_is_main" worktree_path="$_ctx_worktree_path" branch_name="$_ctx_branch"

    # Cannot remove main repository
    if [ "$is_main" = "1" ]; then
      log_error "Cannot remove main repository"
      had_failure=1
      continue
    fi

    if [ "$dry_run" -eq 1 ]; then
      _remove_preview "$repo_root" "$worktree_path" "$branch_name" "$delete_branch" "$force" || had_failure=1
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
        had_failure=1
        continue
      else
        log_warn "Pre-remove hook failed, continuing due to --force"
      fi
    fi

    # Remove the worktree
    if ! remove_worktree "$worktree_path" "$force"; then
      had_failure=1
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

  return "$had_failure"
}

# Print advisory status without removing targets or entering hook/trust dispatch.
# Usage: _remove_preview repo_root worktree_path branch_name delete_branch force
_remove_preview() {
  local repo_root="$1" worktree_path="$2" branch_name="$3" delete_branch="$4" force="$5"
  local state status_output line dirty=no untracked=no locked=no
  [ "$branch_name" != "(detached)" ] || branch_name=""
  printf '[dry-run] Worktree: %s\n' "$(_tsv_escape_field "$worktree_path")"
  printf '  Branch: %s\n' "${branch_name:-detached HEAD}"
  if [ ! -d "$worktree_path" ]; then
    log_error "Worktree not found at $worktree_path"
    return 1
  fi
  state=$(worktree_status "$worktree_path") || return 1
  [ "$state" != locked ] || locked=yes
  # Avoid refreshing/writing the index. Disable fsmonitor to avoid invoking a
  # configured external helper while inspecting the worktree. Configured clean/process
  # filters may still run and write their own state during this status check.
  if ! status_output=$(GIT_OPTIONAL_LOCKS=0 git -C "$worktree_path" -c core.fsmonitor=false \
    status --porcelain=v1 --untracked-files=all --ignore-submodules=none); then
    log_error "Cannot inspect worktree: $worktree_path"
    return 1
  fi
  while IFS= read -r line; do
    case "$line" in
      '') ;;
      '?? '*) untracked=yes ;;
      *) dirty=yes ;;
    esac
  done <<EOF
$status_output
EOF
  printf '  Dirty (tracked): %s; untracked: %s; locked: %s\n' "$dirty" "$untracked" "$locked"
  if [ "$locked" = yes ]; then
    printf '  Blocked: locked worktree; the existing single --force cannot remove it.\n'
  elif [ "$dirty" = yes ] && [ "$force" -eq 0 ]; then
    printf '  Blocked without --force: modified tracked files.\n'
  fi
  if [ "$untracked" = yes ] && [ "$force" -eq 0 ]; then
    printf '  Warning: status.showUntrackedFiles=no can allow removal to delete untracked files even without --force.\n'
  fi
  printf '  Warning: --force can discard uncommitted changes and untracked files.\n'
  printf '  Hooks: preRemove/postRemove not executed; trust state unchanged.\n'
  if [ "$delete_branch" -eq 1 ]; then
    if [ -n "$branch_name" ]; then
      _remove_preview_branch "$repo_root" "$branch_name"
    else
      printf '  Branch deletion: none (detached HEAD).\n'
    fi
  fi
  printf '  Advisory only: hooks and other Git removal restrictions are not evaluated.\n'
}

# Report advisory reachability against a verified local default-base ref; never fetch.
# Usage: _remove_preview_branch repo_root branch_name
_remove_preview_branch() {
  local repo_root="$1" branch_name="$2" remote default_branch candidate base_ref="" base_oid="" branch_oid count
  remote=$(resolve_default_remote)
  default_branch=$(resolve_default_branch "$repo_root" "$remote")
  # Follow new's default selection, but never treat its last-resort name as
  # evidence that a ref exists. Fully qualified refs avoid tag ambiguity.
  for candidate in "refs/remotes/$remote/$default_branch" "refs/heads/$default_branch"; do
    if base_oid=$(git rev-parse --verify "$candidate^{commit}" 2>/dev/null); then
      base_ref="$candidate"
      break
    fi
  done
  printf '  Branch deletion requested: %s (git branch -D).\n' "$branch_name"
  if [ -z "$base_ref" ] || ! branch_oid=$(git rev-parse --verify "refs/heads/$branch_name^{commit}" 2>/dev/null); then
    printf '  Commits not reachable from base: unknown (no verified base or branch tip).\n'
  elif ! _remove_preview_history_complete "$base_oid" "$branch_oid"; then
    printf '  Commits not reachable from base: unknown (incomplete history).\n'
  elif count=$(git rev-list --count "$base_oid..$branch_oid" -- 2>/dev/null); then
    printf '  Commits not reachable from %s: %s\n' "$base_ref" "$count"
  else
    printf '  Commits not reachable from base: unknown (cannot inspect history).\n'
  fi
  printf '  Reachability is not a merged/unmerged judgment; squash/rebase can mislead.\n'
  printf '  Uses local refs only; remote-tracking refs may be stale.\n'
}

# A shallow boundary reachable from either tip may change the set difference.
_remove_preview_history_complete() {
  local base_oid="$1" branch_oid="$2" shallow_file boundary tip
  shallow_file=$(git rev-parse --git-path shallow) || return 1
  [ -e "$shallow_file" ] || return 0
  while IFS= read -r boundary; do
    for tip in "$base_oid" "$branch_oid"; do
      if git merge-base --is-ancestor "$boundary" "$tip" 2>/dev/null; then
        return 1
      elif [ "$?" -ne 1 ]; then
        return 1
      fi
    done
  done < "$shallow_file"
}
