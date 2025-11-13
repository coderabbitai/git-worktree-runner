#!/usr/bin/env bash
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

# Sanitize branch name for use as directory name
# Usage: sanitize_branch_name branch_name
# Converts special characters to hyphens for valid folder names
sanitize_branch_name() {
  local branch="$1"

  # Replace slashes, spaces, and other problematic chars with hyphens
  # Remove any leading/trailing hyphens
  printf "%s" "$branch" | sed -e 's/[\/\\ :*?"<>|]/-/g' -e 's/^-*//' -e 's/-*$//'
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
  else
    # Expand tilde to home directory
    case "$base_dir" in
      ~/*) base_dir="$HOME/${base_dir#~/}" ;;
      ~) base_dir="$HOME" ;;
    esac

    # Check if absolute or relative
    if [ "${base_dir#/}" = "$base_dir" ]; then
      # Relative path - resolve from repo root
      base_dir="$repo_root/$base_dir"
    fi
    # Absolute paths (starting with /) are used as-is
  fi

  # Warn if worktree dir is inside repo (but not a sibling)
  if [[ "$base_dir" == "$repo_root"/* ]]; then
    local rel_path="${base_dir#$repo_root/}"
    # Check if .gitignore exists and whether it includes the worktree directory
    if [ -f "$repo_root/.gitignore" ]; then
      if ! grep -qE "^/?${rel_path}/?\$|^/?${rel_path}/\*?\$" "$repo_root/.gitignore" 2>/dev/null; then
        log_warn "Worktrees are inside repository at: $rel_path"
        log_warn "Consider adding '/$rel_path/' to .gitignore to avoid committing worktrees"
      fi
    else
      log_warn "Worktrees are inside repository at: $rel_path"
      log_warn "Consider adding '/$rel_path/' to .gitignore"
    fi
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

# Get the current branch of a worktree
# Usage: current_branch worktree_path
current_branch() {
  local worktree_path="$1"
  local branch

  if [ ! -d "$worktree_path" ]; then
    return 1
  fi

  # Try --show-current (Git 2.22+), fallback to rev-parse for older Git
  branch=$(cd "$worktree_path" && git branch --show-current 2>/dev/null)
  if [ -z "$branch" ]; then
    branch=$(cd "$worktree_path" && git rev-parse --abbrev-ref HEAD 2>/dev/null)
  fi

  # Normalize detached HEAD
  if [ "$branch" = "HEAD" ]; then
    branch="(detached)"
  fi

  printf "%s" "$branch"
}

# Get the status of a worktree from git
# Usage: worktree_status worktree_path
# Returns: status (ok, detached, locked, prunable, or missing)
worktree_status() {
  local target_path="$1"
  local porcelain_output
  local in_section=0
  local status="ok"
  local found=0

  # Parse git worktree list --porcelain line by line
  porcelain_output=$(git worktree list --porcelain 2>/dev/null)

  while IFS= read -r line; do
    # Check if this is the start of our target worktree
    if [ "$line" = "worktree $target_path" ]; then
      in_section=1
      found=1
      continue
    fi

    # If we're in the target section, check for status lines
    if [ "$in_section" -eq 1 ]; then
      # Empty line marks end of section
      if [ -z "$line" ]; then
        break
      fi

      # Check for status indicators (priority: locked > prunable > detached)
      case "$line" in
        locked*)
          status="locked"
          ;;
        prunable*)
          [ "$status" = "ok" ] && status="prunable"
          ;;
        detached)
          [ "$status" = "ok" ] && status="detached"
          ;;
      esac
    fi
  done <<EOF
$porcelain_output
EOF

  # If worktree not found in git's list
  if [ "$found" -eq 0 ]; then
    status="missing"
  fi

  printf "%s" "$status"
}

# Resolve a worktree target from branch name or special ID '1' for main repo
# Usage: resolve_target identifier repo_root base_dir prefix
# Returns: tab-separated "is_main\tpath\tbranch" on success (is_main: 1 for main repo, 0 for worktrees)
# Exit code: 0 on success, 1 if not found
resolve_target() {
  local identifier="$1"
  local repo_root="$2"
  local base_dir="$3"
  local prefix="$4"
  local id path branch sanitized_name

  # Special case: ID 1 is always the repo root
  if [ "$identifier" = "1" ]; then
    path="$repo_root"
    # Try --show-current (Git 2.22+), fallback to rev-parse for older Git
    branch=$(git -C "$repo_root" branch --show-current 2>/dev/null)
    [ -z "$branch" ] && branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null)
    printf "1\t%s\t%s\n" "$path" "$branch"
    return 0
  fi

  # For all other identifiers, treat as branch name
  # First check if it's the current branch in repo root (if not ID 1)
  branch=$(git -C "$repo_root" branch --show-current 2>/dev/null)
  [ -z "$branch" ] && branch=$(git -C "$repo_root" rev-parse --abbrev-ref HEAD 2>/dev/null)
  if [ "$branch" = "$identifier" ]; then
    printf "1\t%s\t%s\n" "$repo_root" "$identifier"
    return 0
  fi

  # Try direct path match with sanitized branch name
  sanitized_name=$(sanitize_branch_name "$identifier")
  path="$base_dir/${prefix}${sanitized_name}"
  if [ -d "$path" ]; then
    branch=$(current_branch "$path")
    printf "0\t%s\t%s\n" "$path" "$branch"
    return 0
  fi

  # Search worktree directories for matching branch (fallback)
  if [ -d "$base_dir" ]; then
    for dir in "$base_dir/${prefix}"*; do
      [ -d "$dir" ] || continue
      branch=$(current_branch "$dir")
      if [ "$branch" = "$identifier" ]; then
        printf "0\t%s\t%s\n" "$dir" "$branch"
        return 0
      fi
    done
  fi

  log_error "Worktree not found for branch: $identifier"
  return 1
}

# Create a new git worktree
# Usage: create_worktree base_dir prefix branch_name from_ref track_mode [skip_fetch] [force] [custom_name]
# track_mode: auto, remote, local, or none
# skip_fetch: 0 (default, fetch) or 1 (skip)
# force: 0 (default, check branch) or 1 (allow same branch in multiple worktrees)
# custom_name: optional custom name suffix (e.g., "backend" creates "feature-auth-backend")
create_worktree() {
  local base_dir="$1"
  local prefix="$2"
  local branch_name="$3"
  local from_ref="$4"
  local track_mode="${5:-auto}"
  local skip_fetch="${6:-0}"
  local force="${7:-0}"
  local custom_name="${8:-}"
  local sanitized_name worktree_path

  # Construct folder name
  if [ -n "$custom_name" ]; then
    sanitized_name="$(sanitize_branch_name "$branch_name")-${custom_name}"
  else
    sanitized_name=$(sanitize_branch_name "$branch_name")
  fi

  worktree_path="$base_dir/${prefix}${sanitized_name}"
  local force_flag=""

  if [ "$force" -eq 1 ]; then
    force_flag="--force"
  fi

  # Check if worktree already exists
  if [ -d "$worktree_path" ]; then
    log_error "Worktree $sanitized_name already exists at $worktree_path"
    return 1
  fi

  # Create base directory if needed
  mkdir -p "$base_dir"

  # Fetch latest refs (unless --no-fetch)
  if [ "$skip_fetch" -eq 0 ]; then
    log_step "Fetching remote branches..."
    git fetch origin 2>/dev/null || log_warn "Could not fetch from origin"
  fi

  local remote_exists=0
  local local_exists=0

  git show-ref --verify --quiet "refs/remotes/origin/$branch_name" && remote_exists=1
  git show-ref --verify --quiet "refs/heads/$branch_name" && local_exists=1

  case "$track_mode" in
    remote)
      # Force use of remote branch
      if [ "$remote_exists" -eq 1 ]; then
        log_step "Creating worktree from remote branch origin/$branch_name"
        if git worktree add $force_flag "$worktree_path" -b "$branch_name" "origin/$branch_name" 2>/dev/null || \
           git worktree add $force_flag "$worktree_path" "$branch_name" 2>/dev/null; then
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
        if git worktree add $force_flag "$worktree_path" "$branch_name" 2>/dev/null; then
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
      if git worktree add $force_flag "$worktree_path" -b "$branch_name" "$from_ref" 2>/dev/null; then
        log_info "Worktree created with new branch $branch_name"
        printf "%s" "$worktree_path"
        return 0
      else
        log_error "Failed to create worktree with new branch"
        return 1
      fi
      ;;

    auto|*)
      # Auto-detect best option with proper tracking
      if [ "$remote_exists" -eq 1 ] && [ "$local_exists" -eq 0 ]; then
        # Remote exists, no local branch - create local with tracking
        log_step "Branch '$branch_name' exists on remote"

        # Create tracking branch first for explicit upstream configuration
        if git branch --track "$branch_name" "origin/$branch_name" 2>/dev/null; then
          log_info "Created local branch tracking origin/$branch_name"
        fi

        # Now add worktree using the tracking branch
        if git worktree add $force_flag "$worktree_path" "$branch_name" 2>/dev/null; then
          log_info "Worktree created tracking origin/$branch_name"
          printf "%s" "$worktree_path"
          return 0
        fi
      elif [ "$local_exists" -eq 1 ]; then
        log_step "Using existing local branch $branch_name"
        if git worktree add $force_flag "$worktree_path" "$branch_name" 2>/dev/null; then
          log_info "Worktree created with local branch $branch_name"
          printf "%s" "$worktree_path"
          return 0
        fi
      else
        log_step "Creating new branch $branch_name from $from_ref"
        if git worktree add $force_flag "$worktree_path" -b "$branch_name" "$from_ref" 2>/dev/null; then
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
  local force="${2:-0}"

  if [ ! -d "$worktree_path" ]; then
    log_error "Worktree not found at $worktree_path"
    return 1
  fi

  local force_flag=""
  if [ "$force" -eq 1 ]; then
    force_flag="--force"
  fi

  if git worktree remove $force_flag "$worktree_path" 2>/dev/null; then
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
