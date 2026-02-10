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

# Check if a branch has a merged PR/MR on the detected provider
# Usage: check_branch_merged <provider> <branch>
# Returns 0 if merged, 1 if not
check_branch_merged() {
  local provider="$1"
  local branch="$2"

  case "$provider" in
    github)
      local pr_state
      pr_state=$(gh pr list --head "$branch" --state merged --json state --jq '.[0].state' 2>/dev/null || true)
      [ "$pr_state" = "MERGED" ]
      ;;
    gitlab)
      local mr_result
      mr_result=$(glab mr list --source-branch "$branch" --merged --per-page 1 --output json 2>/dev/null || true)
      [ -n "$mr_result" ] && [ "$mr_result" != "[]" ] && [ "$mr_result" != "null" ]
      ;;
    *)
      return 1
      ;;
  esac
}
