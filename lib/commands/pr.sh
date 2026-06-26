#!/usr/bin/env bash

# Pull request command
# Creates a worktree for a GitHub pull request, similar to gh pr checkout.
# shellcheck disable=SC2154  # _arg_* _pa_* set by parse_args, _ctx_* set by resolve_*

declare _ctx_pr_number _ctx_pr_head_ref _ctx_pr_head_owner _ctx_pr_head_repo _ctx_pr_url

_pr_resolve() {
  local selector="$1" repo_arg="$2"

  if ! command -v gh >/dev/null 2>&1; then
    log_error "gh is required for 'git gtr pr'"
    log_info "Install GitHub CLI: https://cli.github.com/"
    return 1
  fi

  local output
  local json_fields="number,headRefName,headRepositoryOwner,headRepository,url"
  local template='{{.number}}{{"\t"}}{{.headRefName}}{{"\t"}}{{.headRepositoryOwner.login}}{{"\t"}}{{.headRepository.name}}{{"\t"}}{{.url}}'
  if [ -n "$repo_arg" ]; then
    output=$(gh pr view "$selector" --repo "$repo_arg" --json "$json_fields" --template "$template" 2>/dev/null) || {
      log_error "Could not resolve pull request: $selector"
      return 1
    }
  else
    output=$(gh pr view "$selector" --json "$json_fields" --template "$template" 2>/dev/null) || {
      log_error "Could not resolve pull request: $selector"
      return 1
    }
  fi

  local old_ifs="$IFS"
  IFS="$(printf '\t')"
  read -r _ctx_pr_number _ctx_pr_head_ref _ctx_pr_head_owner _ctx_pr_head_repo _ctx_pr_url <<EOF
$output
EOF
  IFS="$old_ifs"

  if [ -z "$_ctx_pr_number" ]; then
    log_error "Could not read pull request number from gh output"
    return 1
  fi
}

_pr_head_repo_url() {
  local pr_url="$1" head_owner="$2" head_repo="$3"

  [ -z "$pr_url" ] && return 1
  [ -z "$head_owner" ] && return 1
  [ -z "$head_repo" ] && return 1

  case "$head_owner" in
    "<no value>"|"null") return 1 ;;
  esac
  case "$head_repo" in
    "<no value>"|"null") return 1 ;;
  esac

  local host_url="$pr_url"
  host_url="${host_url%%/pull/*}"
  host_url="${host_url%/*/*}"
  printf "%s/%s/%s.git" "$host_url" "$head_owner" "$head_repo"
}

_pr_configure_branch_for_gh() {
  local branch_name="$1" head_ref="$2" head_repo_url="$3"

  [ -z "$head_ref" ] && return 0
  [ -z "$head_repo_url" ] && return 0

  git config "branch.$branch_name.remote" "$head_repo_url"
  git config "branch.$branch_name.pushRemote" "$head_repo_url"
  git config "branch.$branch_name.merge" "refs/heads/$head_ref"
}

_pr_branch_is_checked_out() {
  local branch_name="$1"
  local line

  while IFS= read -r line; do
    case "$line" in
      "branch refs/heads/$branch_name") return 0 ;;
    esac
  done <<EOF
$(git worktree list --porcelain 2>/dev/null)
EOF

  return 1
}

cmd_pr() {
  local _spec
  _spec="--branch|-b: value
--repo|-R: value
--remote: value
--no-copy
--no-hooks
--yes
--force
--name: value
--folder: value
--editor|-e
--ai|-a"
  parse_args "$_spec" "$@"

  local selector="${_pa_positional[0]:-}"
  local branch_name="${_arg_branch:-}"
  local repo_arg="${_arg_repo:-}"
  local remote="${_arg_remote:-$(resolve_default_remote)}"
  local skip_copy="${_arg_no_copy:-0}"
  local skip_hooks="${_arg_no_hooks:-0}"
  local yes_mode="${_arg_yes:-0}"
  local force="${_arg_force:-0}"
  local custom_name="${_arg_name:-}"
  local folder_override="${_arg_folder:-}"
  local open_editor="${_arg_editor:-0}"
  local start_ai="${_arg_ai:-0}"

  if [ -z "$selector" ]; then
    if [ "$yes_mode" -eq 1 ]; then
      log_error "Pull request selector required in non-interactive mode"
      exit 1
    fi
    selector=$(prompt_input "Enter pull request number, URL, or branch:")
    if [ -z "$selector" ]; then
      log_error "Pull request selector required"
      exit 1
    fi
  fi

  if [ -n "$folder_override" ] && [ -n "$custom_name" ]; then
    log_error "--folder and --name cannot be used together"
    exit 1
  fi

  if [ "$force" -eq 1 ] && [ -z "$custom_name" ] && [ -z "$folder_override" ]; then
    log_error "--force requires --name or --folder to distinguish worktrees"
    echo "Example: git gtr pr $selector --force --name review" >&2
    echo "     or: git gtr pr $selector --force --folder pr-review" >&2
    exit 1
  fi

  resolve_repo_context || exit 1
  local repo_root="$_ctx_repo_root" base_dir="$_ctx_base_dir" prefix="$_ctx_prefix"

  _pr_resolve "$selector" "$repo_arg" || exit 1
  local pr_number="$_ctx_pr_number" pr_head_ref="$_ctx_pr_head_ref"
  local pr_head_owner="$_ctx_pr_head_owner" pr_head_repo="$_ctx_pr_head_repo" pr_url="$_ctx_pr_url"
  local head_repo_url
  head_repo_url=$(_pr_head_repo_url "$pr_url" "$pr_head_owner" "$pr_head_repo") || head_repo_url=""
  if [ -z "$branch_name" ]; then
    branch_name="$pr_head_ref"
    if [ -z "$branch_name" ]; then
      branch_name="pr/$pr_number"
    fi
  fi

  local folder_name
  if [ -n "$folder_override" ]; then
    folder_name=$(sanitize_branch_name "$folder_override")
  elif [ -n "$custom_name" ]; then
    folder_name="$(sanitize_branch_name "$branch_name")-${custom_name}"
  else
    folder_name=$(sanitize_branch_name "$branch_name")
  fi

  local expected_worktree_path="$base_dir/${prefix}${folder_name}"
  if [ -d "$expected_worktree_path" ]; then
    log_error "Worktree $folder_name already exists at $expected_worktree_path"
    exit 1
  fi

  log_step "Fetching pull request #$pr_number..."
  if ! git fetch "$remote" "refs/pull/$pr_number/head"; then
    log_error "Could not fetch pull request #$pr_number from $remote"
    exit 1
  fi

  local track_mode="none"
  if git show-ref --verify --quiet "refs/heads/$branch_name"; then
    local branch_oid fetch_oid
    branch_oid=$(git rev-parse --verify "refs/heads/$branch_name^{commit}" 2>/dev/null) || branch_oid=""
    fetch_oid=$(git rev-parse --verify "FETCH_HEAD^{commit}" 2>/dev/null) || fetch_oid=""
    if [ -z "$branch_oid" ] || [ "$branch_oid" != "$fetch_oid" ]; then
      log_error "Local branch $branch_name already exists and differs from pull request #$pr_number"
      log_info "Use --branch <name> to choose a different local branch name"
      exit 1
    fi
    track_mode="local"
    if _pr_branch_is_checked_out "$branch_name"; then
      log_warn "Local branch $branch_name is already checked out; using it without resetting"
    fi
  fi

  log_step "Creating worktree: $folder_name"
  echo "Location: $base_dir/${prefix}${folder_name}"
  echo "Pull request: #$pr_number"
  [ -n "$pr_head_ref" ] && echo "Head branch: $pr_head_ref"
  echo "Local branch: $branch_name"

  local worktree_path
  if ! worktree_path=$(create_worktree "$base_dir" "$prefix" "$branch_name" "FETCH_HEAD" "$track_mode" "1" "$force" "$custom_name" "$folder_override" "$remote"); then
    exit 1
  fi

  _pr_configure_branch_for_gh "$branch_name" "$pr_head_ref" "$head_repo_url"

  if [ "$skip_copy" -eq 0 ]; then
    _post_create_copy "$repo_root" "$worktree_path"
  fi

  if [ "$skip_hooks" -eq 0 ]; then
    run_hooks_in postCreate "$worktree_path" \
      REPO_ROOT="$repo_root" \
      WORKTREE_PATH="$worktree_path" \
      BRANCH="$branch_name" \
      PR_NUMBER="$pr_number" \
      PR_HEAD_REF="$pr_head_ref"
  fi

  echo ""
  log_info "Worktree created: $worktree_path"

  [ "$open_editor" -eq 1 ] && { _auto_launch_editor "$worktree_path" || true; }
  [ "$start_ai" -eq 1 ] && { _auto_launch_ai "$worktree_path" "$repo_root" "$branch_name" || true; }
  if [ "$open_editor" -eq 0 ] && [ "$start_ai" -eq 0 ]; then
    _post_create_next_steps "$branch_name" "$folder_name" "$folder_override" "$repo_root" "$base_dir" "$prefix"
  fi
}
