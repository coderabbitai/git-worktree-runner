#!/usr/bin/env bash
# Core git worktree operations

# --- Context Globals Contract ---
# Resolver functions set these globals as a return mechanism (Bash lacks multi-return).
# Callers should copy into locals immediately after calling the resolver.
#
# resolve_repo_context() -> _ctx_repo_root  _ctx_base_dir  _ctx_prefix
# resolve_worktree()     -> _ctx_is_main    _ctx_worktree_path  _ctx_branch
declare _ctx_repo_root _ctx_base_dir _ctx_prefix
declare _ctx_is_main _ctx_worktree_path _ctx_branch

# Discover the root of the main git repository
# Works correctly from both the main repo and from inside worktrees.
# Returns: absolute path to main repo root
# Exit code: 0 on success, 1 if not in a git repo
discover_repo_root() {
  local root git_common_dir
  git_common_dir=$(git rev-parse --git-common-dir 2>/dev/null)

  if [ -z "$git_common_dir" ]; then
    log_error "Not in a git repository"
    return 1
  fi

  # --git-common-dir returns:
  #   ".git" (relative) when in the main repo
  #   "/absolute/path/to/repo/.git" when in a worktree
  if [ "$git_common_dir" = ".git" ]; then
    root=$(git rev-parse --show-toplevel 2>/dev/null)
  else
    root="${git_common_dir%/.git}"
  fi

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
  printf "%s" "$branch" | sed -e 's/[\/\\ :*?"<>|#]/-/g' -e 's/^-*//' -e 's/-*$//'
}

# Canonicalize a path to its absolute form, resolving symlinks
# Usage: canonicalize_path path
# Returns: canonical path or empty string on failure
canonicalize_path() {
  local path="$1"
  # Unset CDPATH to prevent unexpected directory changes
  # Suppress stderr to hide errors for non-existent directories
  # Use subshell to avoid changing current working directory
  ( unset CDPATH && cd -P -- "$path" 2>/dev/null && pwd -P )
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
    # Expand literal tilde to home directory
    # Patterns must quote ~ to prevent bash tilde expansion in case arms
    # shellcheck disable=SC2088
    case "$base_dir" in
      "~/"*) base_dir="$HOME/${base_dir#"~/"}" ;;
      "~") base_dir="$HOME" ;;
    esac

    # Check if absolute or relative
    if [ "${base_dir#/}" = "$base_dir" ]; then
      # Relative path - resolve from repo root
      base_dir="$repo_root/$base_dir"
    fi
    # Absolute paths (starting with /) are used as-is
  fi

  # Canonicalize base_dir if it exists
  if [ -d "$base_dir" ]; then
    local canonical_base
    canonical_base=$(canonicalize_path "$base_dir")
    if [ -n "$canonical_base" ]; then
      base_dir="$canonical_base"
    fi
    # If canonicalization fails (empty result), base_dir keeps its absolute form
  fi

  # Canonicalize repo_root before comparison
  local canonical_repo_root
  canonical_repo_root=$(canonicalize_path "$repo_root")
  # Warn if canonicalization fails (indicates repository issue)
  if [ -z "$canonical_repo_root" ]; then
    log_warn "Unable to canonicalize repository path: $repo_root"
    canonical_repo_root="$repo_root"
  fi

  # Warn if worktree dir is inside repo (but not a sibling)
  if [[ "$base_dir" == "$canonical_repo_root"/* ]]; then
    local rel_path="${base_dir#"$canonical_repo_root"/}"
    # Check if .gitignore exists and whether it includes the worktree directory
    if [ -f "$canonical_repo_root/.gitignore" ]; then
      if ! grep -qE "^/?${rel_path}/?\$|^/?${rel_path}/\*?\$" "$canonical_repo_root/.gitignore" 2>/dev/null; then
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

# Get current branch name with Git 2.22+ fallback
# Usage: get_current_branch [directory]
# Returns: branch name, "HEAD" if detached, or empty
get_current_branch() {
  if [ -n "${1:-}" ]; then
    git -C "$1" branch --show-current 2>/dev/null ||
      git -C "$1" rev-parse --abbrev-ref HEAD 2>/dev/null
  else
    git branch --show-current 2>/dev/null ||
      git rev-parse --abbrev-ref HEAD 2>/dev/null
  fi
}

# Get the current branch of a worktree (with detached HEAD normalization)
# Usage: current_branch worktree_path
current_branch() {
  local worktree_path="$1"

  if [ ! -d "$worktree_path" ]; then
    return 1
  fi

  local branch
  branch=$(get_current_branch "$worktree_path")

  # Normalize detached HEAD or empty (failed detection)
  if [ -z "$branch" ] || [ "$branch" = "HEAD" ]; then
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
  local path branch sanitized_name

  # Special case: ID 1 is always the repo root
  if [ "$identifier" = "1" ]; then
    path="$repo_root"
    branch=$(get_current_branch "$repo_root")
    printf "1\t%s\t%s\n" "$path" "$branch"
    return 0
  fi

  # For all other identifiers, treat as branch name
  # First check if it's the current branch in repo root (if not ID 1)
  branch=$(get_current_branch "$repo_root")
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

  # Last resort: ask git for all worktrees (catches non-gtr-managed worktrees)
  local wt_path wt_branch
  while IFS= read -r line; do
    case "$line" in
      "worktree "*)  wt_path="${line#worktree }" ;;
      "branch "*)
        wt_branch="${line#branch refs/heads/}"
        if [ "$wt_branch" = "$identifier" ]; then
          local is_main=0
          [ "$wt_path" = "$repo_root" ] && is_main=1
          printf "%s\t%s\t%s\n" "$is_main" "$wt_path" "$wt_branch"
          return 0
        fi
        ;;
      "")  wt_path="" ; wt_branch="" ;;
    esac
  done < <(git -C "$repo_root" worktree list --porcelain 2>/dev/null)

  log_error "Worktree not found for branch: $identifier"
  return 1
}

# Unpack TSV output from resolve_target into globals.
# Sets: _ctx_is_main, _ctx_worktree_path, _ctx_branch
# Usage: unpack_target "$target_string"
unpack_target() {
  local IFS=$'\t'
  # shellcheck disable=SC2162
  read _ctx_is_main _ctx_worktree_path _ctx_branch <<< "$1"
}

# Resolve an identifier to a worktree and set _ctx_* variables in one step
# Usage: resolve_worktree <identifier> <repo_root> <base_dir> <prefix>
# Sets: _ctx_is_main, _ctx_worktree_path, _ctx_branch
resolve_worktree() {
  local target
  target=$(resolve_target "$1" "$2" "$3" "$4") || return 1
  unpack_target "$target"
}

# Try to create a worktree, handling the common log/add/report pattern.
# Usage: _try_worktree_add <path> <step_msg> <ok_msg> [git_worktree_add_args...]
# Prints worktree path on success; returns 1 on failure (caller handles error).
# Note: step_msg may be empty to skip the log_step call.
_try_worktree_add() {
  local wt_path="$1" step_msg="$2" ok_msg="$3"
  shift 3

  [ -n "$step_msg" ] && log_step "$step_msg"

  if git worktree add "$wt_path" "$@" >&2; then
    log_info "$ok_msg"
    printf "%s" "$wt_path"
    return 0
  fi
  return 1
}

# Build and validate folder name from branch/custom/override.
# Prints sanitized folder name on success; returns 1 on validation failure.
# Usage: _resolve_folder_name <branch_name> [custom_name] [folder_override]
_resolve_folder_name() {
  local branch_name="$1" custom_name="${2:-}" folder_override="${3:-}"
  local sanitized_name

  if [ -n "$folder_override" ]; then
    sanitized_name=$(sanitize_branch_name "$folder_override")
  elif [ -n "$custom_name" ]; then
    sanitized_name="$(sanitize_branch_name "$branch_name")-${custom_name}"
  else
    sanitized_name=$(sanitize_branch_name "$branch_name")
  fi

  if [ -z "$sanitized_name" ] || [ "$sanitized_name" = "." ] || [ "$sanitized_name" = ".." ]; then
    if [ -n "$folder_override" ]; then
      log_error "Invalid --folder value: $folder_override"
    else
      log_error "Invalid worktree folder name derived from branch: $branch_name"
    fi
    return 1
  fi

  printf "%s" "$sanitized_name"
}

# Check if a branch exists on remote and/or locally.
# Sets globals: _wt_remote_exists, _wt_local_exists (0 or 1)
# Usage: _check_branch_refs <branch_name>
declare _wt_remote_exists _wt_local_exists
_check_branch_refs() {
  _wt_remote_exists=0
  _wt_local_exists=0
  git show-ref --verify --quiet "refs/remotes/origin/$1" && _wt_remote_exists=1
  git show-ref --verify --quiet "refs/heads/$1" && _wt_local_exists=1
  return 0
}

# Auto-track: create local tracking branch from remote if needed, then add worktree.
# Usage: _worktree_add_tracked <worktree_path> <branch_name> [force_args...]
# shellcheck disable=SC2317  # Called indirectly from create_worktree
_worktree_add_tracked() {
  local wt_path="$1" branch_name="$2"
  shift 2

  log_step "Branch '$branch_name' exists on remote"
  if git branch --track "$branch_name" "origin/$branch_name" >/dev/null 2>&1; then
    log_info "Created local branch tracking origin/$branch_name"
  fi
  _try_worktree_add "$wt_path" "" \
    "Worktree created tracking origin/$branch_name" \
    "$@" "$branch_name"
}

# Create a new git worktree
# Usage: create_worktree base_dir prefix branch_name from_ref track_mode [skip_fetch] [force] [custom_name] [folder_override]
# track_mode: auto, remote, local, or none
# skip_fetch: 0 (default, fetch) or 1 (skip)
# force: 0 (default, check branch) or 1 (allow same branch in multiple worktrees)
# custom_name: optional custom name suffix (e.g., "backend" creates "feature-auth-backend")
# folder_override: optional complete folder name override (replaces default naming)
create_worktree() {
  local base_dir="$1" prefix="$2" branch_name="$3" from_ref="$4"
  local track_mode="${5:-auto}" skip_fetch="${6:-0}" force="${7:-0}"
  local custom_name="${8:-}" folder_override="${9:-}"

  local sanitized_name
  sanitized_name=$(_resolve_folder_name "$branch_name" "$custom_name" "$folder_override") || return 1

  local worktree_path="$base_dir/${prefix}${sanitized_name}"
  local force_args=()
  [ "$force" -eq 1 ] && force_args=(--force)

  if [ -d "$worktree_path" ]; then
    log_error "Worktree $sanitized_name already exists at $worktree_path"
    return 1
  fi

  mkdir -p "$base_dir"

  if [ "$skip_fetch" -eq 0 ]; then
    log_step "Fetching remote branches..."
    git fetch origin 2>/dev/null || log_warn "Could not fetch from origin"
  fi

  _check_branch_refs "$branch_name"

  # Resolve from_ref to a commit SHA to prevent git's guess-remote logic
  # from overriding the -b flag when from_ref matches a remote branch name.
  # Try the ref as-is first, then with origin/ prefix for remote-only refs.
  local resolved_ref
  resolved_ref=$(git rev-parse --verify "${from_ref}^{commit}" 2>/dev/null) \
    || resolved_ref=$(git rev-parse --verify "origin/${from_ref}^{commit}" 2>/dev/null) \
    || resolved_ref="$from_ref"

  case "$track_mode" in
    remote)
      if [ "$_wt_remote_exists" -eq 1 ]; then
        _try_worktree_add "$worktree_path" \
          "Creating worktree from remote branch origin/$branch_name" \
          "Worktree created tracking origin/$branch_name" \
          "${force_args[@]}" -b "$branch_name" "origin/$branch_name" && return 0
        _try_worktree_add "$worktree_path" "" \
          "Worktree created tracking origin/$branch_name" \
          "${force_args[@]}" "$branch_name" && return 0
      fi
      log_error "Remote branch origin/$branch_name does not exist"
      return 1
      ;;

    local)
      if [ "$_wt_local_exists" -eq 1 ]; then
        _try_worktree_add "$worktree_path" \
          "Creating worktree from local branch $branch_name" \
          "Worktree created with local branch $branch_name" \
          "${force_args[@]}" "$branch_name" && return 0
      fi
      log_error "Local branch $branch_name does not exist"
      return 1
      ;;

    none)
      _try_worktree_add "$worktree_path" \
        "Creating new branch $branch_name from $from_ref" \
        "Worktree created with new branch $branch_name" \
        "${force_args[@]}" -b "$branch_name" "$resolved_ref" && return 0
      log_error "Failed to create worktree with new branch"
      return 1
      ;;

    auto|*)
      if [ "$_wt_remote_exists" -eq 1 ] && [ "$_wt_local_exists" -eq 0 ]; then
        _worktree_add_tracked "$worktree_path" "$branch_name" "${force_args[@]}" && return 0
      elif [ "$_wt_local_exists" -eq 1 ]; then
        _try_worktree_add "$worktree_path" \
          "Using existing local branch $branch_name" \
          "Worktree created with local branch $branch_name" \
          "${force_args[@]}" "$branch_name" && return 0
      else
        _try_worktree_add "$worktree_path" \
          "Creating new branch $branch_name from $from_ref" \
          "Worktree created with new branch $branch_name" \
          "${force_args[@]}" -b "$branch_name" "$resolved_ref" && return 0
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

  local force_args=()
  if [ "$force" -eq 1 ]; then
    force_args=(--force)
  fi

  local remove_output
  if remove_output=$(git worktree remove "${force_args[@]}" "$worktree_path" 2>&1); then
    log_info "Worktree removed: $worktree_path"
    return 0
  else
    if [ -n "$remove_output" ]; then
      log_error "Failed to remove worktree: $remove_output"
    else
      log_error "Failed to remove worktree"
    fi
    return 1
  fi
}

# Resolve common repo context used by most cmd_* handlers.
# Sets globals: _ctx_repo_root, _ctx_base_dir, _ctx_prefix
# Usage: resolve_repo_context || exit 1
resolve_repo_context() {
  _ctx_repo_root=$(discover_repo_root) || return 1
  _ctx_base_dir=$(resolve_base_dir "$_ctx_repo_root")
  _ctx_prefix=$(cfg_default gtr.worktrees.prefix GTR_WORKTREES_PREFIX "")
}

# List all worktree branch names (excluding main repo)
# Usage: list_worktree_branches base_dir prefix
# Returns: newline-separated list of branch names
list_worktree_branches() {
  local base_dir="$1"
  local prefix="$2"

  [ ! -d "$base_dir" ] && return 0

  for dir in "$base_dir/${prefix}"*; do
    [ -d "$dir" ] || continue
    local branch
    branch=$(current_branch "$dir")
    [ -n "$branch" ] && echo "$branch"
  done
}
