#!/usr/bin/env bash

# List command
cmd_list() {
  local porcelain=0

  # Parse flags
  while [ $# -gt 0 ]; do
    case "$1" in
      --porcelain)
        porcelain=1
        shift
        ;;
      *)
        shift
        ;;
    esac
  done

  local repo_root base_dir prefix
  repo_root=$(discover_repo_root) 2>/dev/null || return 0
  base_dir=$(resolve_base_dir "$repo_root")
  prefix=$(cfg_default gtr.worktrees.prefix GTR_WORKTREES_PREFIX "")

  # Machine-readable output (porcelain)
  if [ "$porcelain" -eq 1 ]; then
    # Output: path<tab>branch<tab>status
    local branch status
    branch=$(current_branch "$repo_root")
    status=$(worktree_status "$repo_root")
    printf "%s\t%s\t%s\n" "$repo_root" "$branch" "$status"

    if [ -d "$base_dir" ]; then
      # Find all worktree directories and output: path<tab>branch<tab>status
      # Exclude the base directory itself to avoid matching when prefix is empty
      find "$base_dir" -maxdepth 1 -type d -name "${prefix}*" 2>/dev/null | while IFS= read -r dir; do
        # Skip the base directory itself
        [ "$dir" = "$base_dir" ] && continue
        local branch status
        branch=$(current_branch "$dir")
        [ -z "$branch" ] && branch="(detached)"
        status=$(worktree_status "$dir")
        printf "%s\t%s\t%s\n" "$dir" "$branch" "$status"
      done | LC_ALL=C sort -k2,2
    fi
    return 0
  fi

  # Human-readable output - table format
  echo "Git Worktrees"
  echo ""
  printf "%-30s %s\n" "BRANCH" "PATH"
  printf "%-30s %s\n" "------" "----"

  # Always show repo root first
  local branch
  branch=$(current_branch "$repo_root")
  printf "%-30s %s\n" "$branch [main repo]" "$repo_root"

  # Show worktrees sorted by branch name
  if [ -d "$base_dir" ]; then
    find "$base_dir" -maxdepth 1 -type d -name "${prefix}*" 2>/dev/null | while IFS= read -r dir; do
      # Skip the base directory itself
      [ "$dir" = "$base_dir" ] && continue
      local branch
      branch=$(current_branch "$dir")
      [ -z "$branch" ] && branch="(detached)"
      printf "%-30s %s\n" "$branch" "$dir"
    done | LC_ALL=C sort -k1,1
  fi

  echo ""
  echo ""
  echo "Tip: Use 'git gtr list --porcelain' for machine-readable output"
}