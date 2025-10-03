#!/bin/sh
# Core git worktree operations

# Discover the root of the current git repository
# Returns: absolute path to repo root
# Exit code: 0 on success, 1 if not in a git repo
discover_repo_root() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null)

  if [ -z "$root" ]; then
    log_error "Not in a git repository"
    return 1
  fi

  printf "%s" "$root"
}

# Resolve the base directory for worktrees
# Usage: resolve_base_dir repo_root
resolve_base_dir() {
  local repo_root="$1"
  local repo_name
  local base_dir

  repo_name=$(basename "$repo_root")

  # Check config first (gtr.worktrees.dir), then environment (GTR_WORKTREES_DIR), then default
  base_dir=$(cfg_default "gtr.worktrees.dir" "GTR_WORKTREES_DIR" "")

  if [ -z "$base_dir" ]; then
    # Default: <repo>-worktrees next to the repo
    base_dir="$(dirname "$repo_root")/${repo_name}-worktrees"
  elif [ "${base_dir#/}" = "$base_dir" ]; then
    # Relative path - resolve from repo parent
    base_dir="$(dirname "$repo_root")/$base_dir"
  fi

  printf "%s" "$base_dir"
}

# Resolve the default branch name
# Usage: resolve_default_branch [repo_root]
resolve_default_branch() {
  local repo_root="${1:-$(pwd)}"
  local default_branch
  local configured_branch

  # Check config first
  configured_branch=$(cfg_default "gtr.defaultBranch" "GTR_DEFAULT_BRANCH" "auto")

  if [ "$configured_branch" != "auto" ]; then
    printf "%s" "$configured_branch"
    return 0
  fi

  # Auto-detect from origin/HEAD
  default_branch=$(git symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's|refs/remotes/origin/||')

  if [ -n "$default_branch" ]; then
    printf "%s" "$default_branch"
    return 0
  fi

  # Fallback: try common branch names
  if git show-ref --verify --quiet "refs/remotes/origin/main"; then
    printf "main"
  elif git show-ref --verify --quiet "refs/remotes/origin/master"; then
    printf "master"
  else
    # Last resort: just use 'main'
    printf "main"
  fi
}

# Find the next available worktree ID
# Usage: next_available_id base_dir prefix [start_id]
next_available_id() {
  local base_dir="$1"
  local prefix="$2"
  local start_id="${3:-2}"
  local id="$start_id"

  while [ -d "$base_dir/${prefix}${id}" ]; do
    id=$((id + 1))
  done

  printf "%s" "$id"
}

# Get the current branch of a worktree
# Usage: current_branch worktree_path
current_branch() {
  local worktree_path="$1"

  if [ ! -d "$worktree_path" ]; then
    return 1
  fi

  (cd "$worktree_path" && git branch --show-current 2>/dev/null) || true
}

# Create a new git worktree
# Usage: create_worktree base_dir prefix id branch_name from_ref track_mode
# track_mode: auto, remote, local, or none
create_worktree() {
  local base_dir="$1"
  local prefix="$2"
  local id="$3"
  local branch_name="$4"
  local from_ref="$5"
  local track_mode="${6:-auto}"
  local worktree_path="$base_dir/${prefix}${id}"

  # Check if worktree already exists
  if [ -d "$worktree_path" ]; then
    log_error "Worktree ${prefix}${id} already exists at $worktree_path"
    return 1
  fi

  # Create base directory if needed
  mkdir -p "$base_dir"

  # Fetch latest refs
  log_step "Fetching remote branches..."
  git fetch origin 2>/dev/null || log_warn "Could not fetch from origin"

  local remote_exists=0
  local local_exists=0

  git show-ref --verify --quiet "refs/remotes/origin/$branch_name" && remote_exists=1
  git show-ref --verify --quiet "refs/heads/$branch_name" && local_exists=1

  case "$track_mode" in
    remote)
      # Force use of remote branch
      if [ "$remote_exists" -eq 1 ]; then
        log_step "Creating worktree from remote branch origin/$branch_name"
        if git worktree add "$worktree_path" -b "$branch_name" "origin/$branch_name" 2>/dev/null || \
           git worktree add "$worktree_path" "$branch_name" 2>/dev/null; then
          log_info "Worktree created tracking origin/$branch_name"
          printf "%s" "$worktree_path"
          return 0
        fi
      else
        log_error "Remote branch origin/$branch_name does not exist"
        return 1
      fi
      ;;

    local)
      # Force use of local branch
      if [ "$local_exists" -eq 1 ]; then
        log_step "Creating worktree from local branch $branch_name"
        if git worktree add "$worktree_path" "$branch_name" 2>/dev/null; then
          log_info "Worktree created with local branch $branch_name"
          printf "%s" "$worktree_path"
          return 0
        fi
      else
        log_error "Local branch $branch_name does not exist"
        return 1
      fi
      ;;

    none)
      # Create new branch from from_ref
      log_step "Creating new branch $branch_name from $from_ref"
      if git worktree add "$worktree_path" -b "$branch_name" "$from_ref" 2>/dev/null; then
        log_info "Worktree created with new branch $branch_name"
        printf "%s" "$worktree_path"
        return 0
      else
        log_error "Failed to create worktree with new branch"
        return 1
      fi
      ;;

    auto|*)
      # Auto-detect best option
      if [ "$remote_exists" -eq 1 ]; then
        log_step "Branch '$branch_name' exists on remote"
        if git worktree add "$worktree_path" -b "$branch_name" "origin/$branch_name" 2>/dev/null || \
           git worktree add "$worktree_path" "$branch_name" 2>/dev/null; then
          log_info "Worktree created tracking origin/$branch_name"
          printf "%s" "$worktree_path"
          return 0
        fi
      elif [ "$local_exists" -eq 1 ]; then
        log_step "Using existing local branch $branch_name"
        if git worktree add "$worktree_path" "$branch_name" 2>/dev/null; then
          log_info "Worktree created with local branch $branch_name"
          printf "%s" "$worktree_path"
          return 0
        fi
      else
        log_step "Creating new branch $branch_name from $from_ref"
        if git worktree add "$worktree_path" -b "$branch_name" "$from_ref" 2>/dev/null; then
          log_info "Worktree created with new branch $branch_name"
          printf "%s" "$worktree_path"
          return 0
        fi
      fi
      ;;
  esac

  log_error "Failed to create worktree"
  return 1
}

# Remove a git worktree
# Usage: remove_worktree worktree_path
remove_worktree() {
  local worktree_path="$1"

  if [ ! -d "$worktree_path" ]; then
    log_error "Worktree not found at $worktree_path"
    return 1
  fi

  if git worktree remove "$worktree_path" 2>/dev/null; then
    log_info "Worktree removed: $worktree_path"
    return 0
  else
    log_error "Failed to remove worktree"
    return 1
  fi
}

# List all worktrees
list_worktrees() {
  git worktree list
}
