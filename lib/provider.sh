#!/usr/bin/env bash
# Remote hosting provider detection and CLI integration
# Used by cmd_clean --merged/--closed to support GitHub (gh) and GitLab (glab)

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

# Check whether GitLab MR JSON includes a source-head SHA matching branch_tip.
# Uses jq when available; otherwise falls back to exact JSON key extraction to
# keep GitLab cleanup usable on systems without jq.
# Usage: _gitlab_mr_matches_tip <mr_json> <branch_tip>
_gitlab_mr_matches_tip() {
  local mr_result="$1"
  local branch_tip="$2"
  local mr_matches

  if command -v jq >/dev/null 2>&1; then
    mr_matches=$(printf "%s" "$mr_result" | jq --arg branch_tip "$branch_tip" 'map(select((.sha // "") == $branch_tip or (.head_sha // "") == $branch_tip or (.diff_refs.head_sha // "") == $branch_tip)) | length' 2>/dev/null || true)
    [ "${mr_matches:-0}" -gt 0 ]
    return
  fi

  local compact_result objects object sha_field head_sha_field diff_refs
  compact_result=$(printf "%s" "$mr_result" | tr -d '[:space:]')
  objects=$(printf "%s" "$compact_result" | sed 's/},{/}\
{/g')

  while IFS= read -r object; do
    sha_field=$(printf "%s" "$object" | sed -n 's/^[^{]*{[^{}]*"sha":"\([^"]*\)".*/\1/p')
    [ "$sha_field" = "$branch_tip" ] && return 0

    head_sha_field=$(printf "%s" "$object" | sed -n 's/^[^{]*{[^{}]*"head_sha":"\([^"]*\)".*/\1/p')
    [ "$head_sha_field" = "$branch_tip" ] && return 0

    diff_refs=$(printf "%s" "$object" | sed -n 's/.*"diff_refs":{\([^}]*\)}.*/\1/p')
    case "$diff_refs" in
      *"\"head_sha\":\"$branch_tip\""*)
        return 0
        ;;
    esac
  done <<EOF
$objects
EOF

  return 1
}

# Check if a branch has a PR/MR with the requested state on the detected provider.
# When branch_tip is provided, require the PR/MR to point at the same commit so
# reused branch names do not match older PRs/MRs.
# Usage: check_branch_pr_state <provider> <branch> <merged|closed> [target_ref] [branch_tip]
# Returns 0 if found, 1 if not
check_branch_pr_state() {
  local provider="$1"
  local branch="$2"
  local pr_state="$3"
  local target_ref="${4:-}"
  local branch_tip="${5:-}"
  local normalized_target_ref

  case "$pr_state" in
    merged|closed) ;;
    *) return 1 ;;
  esac

  normalized_target_ref=$(normalize_target_ref "$target_ref") || true

  case "$provider" in
    github)
      local -a gh_args
      local expected_state pr_matches
      expected_state=$(printf "%s" "$pr_state" | tr '[:lower:]' '[:upper:]')
      gh_args=(pr list --head "$branch" --state "$pr_state" --limit 1000)
      if [ -n "$normalized_target_ref" ]; then
        gh_args+=(--base "$normalized_target_ref")
      fi
      if [ -n "$branch_tip" ]; then
        pr_matches=$(gh "${gh_args[@]}" --json state,headRefOid --jq "map(select(.state == \"$expected_state\" and .headRefOid == \"$branch_tip\")) | length" 2>/dev/null || true)
      else
        pr_matches=$(gh "${gh_args[@]}" --json state --jq "map(select(.state == \"$expected_state\")) | length" 2>/dev/null || true)
      fi
      [ "${pr_matches:-0}" -gt 0 ]
      ;;
    gitlab)
      local mr_result
      local -a glab_args
      glab_args=(mr list --source-branch "$branch" "--$pr_state" --all --output json)
      if [ -n "$normalized_target_ref" ]; then
        glab_args+=(--target-branch "$normalized_target_ref")
      fi

      mr_result=$(glab "${glab_args[@]}" 2>/dev/null || true)
      [ -n "$mr_result" ] && [ "$mr_result" != "[]" ] && [ "$mr_result" != "null" ] || return 1

      if [ -n "$branch_tip" ]; then
        _gitlab_mr_matches_tip "$mr_result" "$branch_tip"
        return
      fi

      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Check if a branch has a merged PR/MR on the detected provider.
# Usage: check_branch_merged <provider> <branch> [target_ref] [branch_tip]
check_branch_merged() {
  check_branch_pr_state "$1" "$2" merged "${3:-}" "${4:-}"
}

# Check if a branch has a closed, unmerged PR/MR on the detected provider.
# Usage: check_branch_closed <provider> <branch> [target_ref] [branch_tip]
check_branch_closed() {
  check_branch_pr_state "$1" "$2" closed "${3:-}" "${4:-}"
}
