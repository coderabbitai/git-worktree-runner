#!/usr/bin/env bash
# Remote hosting provider detection and CLI integration
# Used by cmd_clean --merged to support GitHub (gh) and GitLab (glab)

# Extract hostname from a git remote URL
# Handles SSH shorthand, SSH with scheme, and HTTPS:
#   git@github.com:user/repo.git       -> github.com
#   ssh://git@github.com/user/repo.git -> github.com
#   https://github.com/user/repo.git   -> github.com
# Usage: extract_hostname <url>
extract_hostname() {
  local url="$1"

  case "$url" in
    *@*:*/*)
      # SSH shorthand: git@host:user/path
      local hostname="${url#*@}"
      printf "%s" "${hostname%%:*}"
      ;;
    *://*)
      # SSH or HTTPS with scheme
      local hostname="${url#*://}"
      hostname="${hostname#*@}"
      hostname="${hostname%%/*}"
      hostname="${hostname%%:*}"
      printf "%s" "$hostname"
      ;;
    *)
      return 1
      ;;
  esac
}

# Detect the hosting provider from origin remote URL
# Checks gtr.provider config override first, then auto-detects from URL
# Usage: detect_provider
# Prints: "github", "gitlab", or returns 1 if unknown
detect_provider() {
  # 1. Check explicit config override (handles self-hosted instances)
  local provider
  provider=$(cfg_default "gtr.provider" "GTR_PROVIDER" "")
  if [ -n "$provider" ]; then
    printf "%s" "$provider"
    return 0
  fi

  # 2. Auto-detect from origin URL
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null || true)
  if [ -z "$remote_url" ]; then
    return 1
  fi

  local hostname
  hostname=$(extract_hostname "$remote_url") || return 1

  case "$hostname" in
    github.com)  printf "github" ;;
    gitlab.com)  printf "gitlab" ;;
    *)           return 1 ;;
  esac
}

# Ensure the provider's CLI tool is installed and authenticated
# Usage: ensure_provider_cli <provider>
# Returns 0 on success, 1 on failure (with error messages)
ensure_provider_cli() {
  local provider="$1"

  case "$provider" in
    github)
      if ! command -v gh >/dev/null 2>&1; then
        log_error "GitHub CLI (gh) not found. Install from: https://cli.github.com/"
        return 1
      fi
      if ! gh repo view >/dev/null 2>&1; then
        log_error "Not authenticated with GitHub or not a GitHub repository"
        log_info "Run: gh auth login"
        return 1
      fi
      ;;
    gitlab)
      if ! command -v glab >/dev/null 2>&1; then
        log_error "GitLab CLI (glab) not found. Install from: https://gitlab.com/gitlab-org/cli"
        return 1
      fi
      if ! glab repo view >/dev/null 2>&1; then
        log_error "Not authenticated with GitLab or not a GitLab repository"
        log_info "Run: glab auth login"
        return 1
      fi
      ;;
    *)
      log_error "Unsupported hosting provider: $provider"
      return 1
      ;;
  esac
}

# Normalize user-provided refs to plain branch names for provider filters.
# Usage: normalize_target_ref [target_ref]
normalize_target_ref() {
  local target_ref="${1:-}"
  local remote_ref

  [ -n "$target_ref" ] || return 0

  case "$target_ref" in
    refs/heads/*)
      printf "%s" "${target_ref#refs/heads/}"
      ;;
    refs/remotes/*)
      remote_ref="${target_ref#refs/remotes/}"
      printf "%s" "${remote_ref#*/}"
      ;;
    origin/*|upstream/*)
      printf "%s" "${target_ref#*/}"
      ;;
    *)
      if git show-ref --verify --quiet "refs/remotes/$target_ref" 2>/dev/null; then
        printf "%s" "${target_ref#*/}"
      else
        printf "%s" "$target_ref"
      fi
      ;;
  esac
}

# Check if a branch has a merged PR/MR on the detected provider.
# When branch_tip is provided, require the merged PR/MR to point at the same
# commit so reused branch names do not match older merged PRs.
# Usage: check_branch_merged <provider> <branch> [target_ref] [branch_tip]
# Returns 0 if merged, 1 if not
check_branch_merged() {
  local provider="$1"
  local branch="$2"
  local target_ref="${3:-}"
  local branch_tip="${4:-}"
  local normalized_target_ref

  normalized_target_ref=$(normalize_target_ref "$target_ref") || true

  case "$provider" in
    github)
      local -a gh_args
      local pr_matches
      gh_args=(pr list --head "$branch" --state merged --limit 1000)
      if [ -n "$normalized_target_ref" ]; then
        gh_args+=(--base "$normalized_target_ref")
      fi
      if [ -n "$branch_tip" ]; then
        pr_matches=$(gh "${gh_args[@]}" --json state,headRefOid --jq "map(select(.state == \"MERGED\" and .headRefOid == \"$branch_tip\")) | length" 2>/dev/null || true)
      else
        pr_matches=$(gh "${gh_args[@]}" --json state --jq 'map(select(.state == "MERGED")) | length' 2>/dev/null || true)
      fi
      [ "${pr_matches:-0}" -gt 0 ]
      ;;
    gitlab)
      local mr_result compact_result
      local -a glab_args
      glab_args=(mr list --source-branch "$branch" --merged --all --output json)
      if [ -n "$normalized_target_ref" ]; then
        glab_args+=(--target-branch "$normalized_target_ref")
      fi

      mr_result=$(glab "${glab_args[@]}" 2>/dev/null || true)
      [ -n "$mr_result" ] && [ "$mr_result" != "[]" ] && [ "$mr_result" != "null" ] || return 1

      if [ -n "$branch_tip" ]; then
        compact_result=$(printf "%s" "$mr_result" | tr -d '[:space:]')
        case "$compact_result" in
          *"\"sha\":\"$branch_tip\""*|*"\"head_sha\":\"$branch_tip\""*)
            return 0
            ;;
          *)
            return 1
            ;;
        esac
      fi

      return 0
      ;;
    *)
      return 1
      ;;
  esac
}
