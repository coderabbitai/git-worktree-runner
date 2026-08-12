#!/usr/bin/env bash

# Pull request command
# Creates a worktree for a GitHub pull request, similar to gh pr checkout.
# shellcheck disable=SC2154  # _arg_* _pa_* set by parse_args, _ctx_* set by resolve_*

declare _ctx_pr_number _ctx_pr_head_ref _ctx_pr_head_owner _ctx_pr_head_repo _ctx_pr_url
declare _ctx_pr_maintainer_can_modify _ctx_pr_is_cross_repository

_pr_resolve() {
  local selector="$1" repo_arg="$2"

  if ! command -v gh >/dev/null 2>&1; then
    log_error "gh is required for 'git gtr pr'"
    log_info "Install GitHub CLI: https://cli.github.com/"
    return 1
  fi

  local output gh_stderr err_file
  local json_fields="number,headRefName,headRepositoryOwner,headRepository,url,maintainerCanModify,isCrossRepository"
  local template='{{.number}}{{"\t"}}{{.headRefName}}{{"\t"}}{{.headRepositoryOwner.login}}{{"\t"}}{{.headRepository.name}}{{"\t"}}{{.url}}{{"\t"}}{{.maintainerCanModify}}{{"\t"}}{{.isCrossRepository}}'
  err_file=$(mktemp "${TMPDIR:-/tmp}/gtr-gh.XXXXXX") || {
    log_error "Could not create temporary file for gh output"
    return 1
  }

  if [ -n "$repo_arg" ]; then
    output=$(gh pr view "$selector" --repo "$repo_arg" --json "$json_fields" --template "$template" 2>"$err_file") || {
      gh_stderr=$(cat "$err_file" 2>/dev/null || true)
      rm -f "$err_file"
      log_error "Could not resolve pull request: $selector"
      [ -n "$gh_stderr" ] && log_info "$gh_stderr"
      return 1
    }
  else
    output=$(gh pr view "$selector" --json "$json_fields" --template "$template" 2>"$err_file") || {
      gh_stderr=$(cat "$err_file" 2>/dev/null || true)
      rm -f "$err_file"
      log_error "Could not resolve pull request: $selector"
      [ -n "$gh_stderr" ] && log_info "$gh_stderr"
      return 1
    }
  fi
  rm -f "$err_file"

  local old_ifs="$IFS"
  IFS="$(printf '\t')"
  read -r _ctx_pr_number _ctx_pr_head_ref _ctx_pr_head_owner _ctx_pr_head_repo _ctx_pr_url _ctx_pr_maintainer_can_modify _ctx_pr_is_cross_repository <<EOF
$output
EOF
  IFS="$old_ifs"

  if [ -z "$_ctx_pr_number" ]; then
    log_error "Could not read pull request number from gh output"
    return 1
  fi
}

_pr_gh_supports_worktree() {
  gh pr checkout --help 2>&1 | grep -q -- '--worktree'
}

_pr_url_with_git_suffix() {
  local repo_url="$1"
  case "$repo_url" in
    *.git) printf "%s" "$repo_url" ;;
    *) printf "%s.git" "$repo_url" ;;
  esac
}

_pr_base_repo_url() {
  local pr_url="$1"

  [ -z "$pr_url" ] && return 1
  case "$pr_url" in
    */pull/*) _pr_url_with_git_suffix "${pr_url%%/pull/*}" ;;
    *) return 1 ;;
  esac
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
  _pr_url_with_git_suffix "$host_url/$head_owner/$head_repo"
}

_pr_normalize_repo_url() {
  local repo_url="$1"
  repo_url="${repo_url%/}"
  repo_url="${repo_url%.git}"

  case "$repo_url" in
    git@*:*)
      repo_url="${repo_url#git@}"
      repo_url="${repo_url/:/\/}"
      ;;
    *://*)
      repo_url="${repo_url#*://}"
      repo_url="${repo_url#*@}"
      ;;
  esac

  printf "%s" "$repo_url"
}

_pr_remote_for_url() {
  local repo_url="$1"
  local wanted
  wanted=$(_pr_normalize_repo_url "$repo_url")

  local remote_name remote_url remote_norm
  while IFS= read -r remote_name; do
    [ -z "$remote_name" ] && continue
    remote_url=$(git config --get "remote.$remote_name.url" 2>/dev/null) || continue
    remote_norm=$(_pr_normalize_repo_url "$remote_url")
    if [ "$remote_norm" = "$wanted" ]; then
      printf "%s" "$remote_name"
      return 0
    fi
  done <<EOF
$(git remote 2>/dev/null)
EOF

  return 1
}

_pr_repo_url_for_gh_protocol() {
  local repo_url="$1"

  case "$repo_url" in
    http://*|https://*) ;;
    *)
      printf "%s" "$repo_url"
      return 0
      ;;
  esac

  local host path protocol
  host="${repo_url#*://}"
  host="${host%%/*}"
  path="${repo_url#*://}"
  path="${path#*/}"
  protocol=$(gh config get git_protocol --host "$host" 2>/dev/null) || protocol=""

  if [ "$protocol" = "ssh" ]; then
    printf "git@%s:%s" "$host" "$path"
  else
    printf "%s" "$repo_url"
  fi
}

_pr_preferred_repo_source() {
  local repo_url="$1" remote_name
  remote_name=$(_pr_remote_for_url "$repo_url") || remote_name=""
  if [ -n "$remote_name" ]; then
    printf "%s" "$remote_name"
  else
    _pr_repo_url_for_gh_protocol "$repo_url"
  fi
}

_pr_configure_base_remote_for_gh() {
  local pr_number="$1" base_repo_url="$2"

  [ -z "$base_repo_url" ] && return 0

  local remote_name
  remote_name=$(_pr_remote_for_url "$base_repo_url") || remote_name=""

  if [ -z "$remote_name" ]; then
    local candidate="gtr-pr-$pr_number-base" suffix=1
    remote_name="$candidate"
    while git remote get-url "$remote_name" >/dev/null 2>&1; do
      remote_name="$candidate-$suffix"
      suffix=$((suffix + 1))
    done
    local preferred_url
    preferred_url=$(_pr_repo_url_for_gh_protocol "$base_repo_url") || preferred_url="$base_repo_url"
    git remote add "$remote_name" "$preferred_url" || return 1
  fi

  git config "remote.$remote_name.gh-resolved" base
}

_pr_config_set() {
  local branch_name="$1" key="$2" value="$3" preserve_existing="$4"
  local config_key="branch.$branch_name.$key"

  if [ "$preserve_existing" -eq 1 ] && git config --get "$config_key" >/dev/null 2>&1; then
    return 0
  fi

  git config "$config_key" "$value"
}

_pr_configure_branch_for_gh() {
  local branch_name="$1" remote_source="$2" merge_ref="$3" push_source="$4" preserve_existing="${5:-0}"

  [ -z "$remote_source" ] && return 0
  [ -z "$merge_ref" ] && return 0

  _pr_config_set "$branch_name" remote "$remote_source" "$preserve_existing" || return 1
  if [ -n "$push_source" ]; then
    _pr_config_set "$branch_name" pushRemote "$push_source" "$preserve_existing" || return 1
  fi
  _pr_config_set "$branch_name" merge "$merge_ref" "$preserve_existing" || return 1
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
  local remote_arg="${_arg_remote:-}"
  local remote="${remote_arg:-$(resolve_default_remote)}"
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
  local maintainer_can_modify="$_ctx_pr_maintainer_can_modify" is_cross_repository="$_ctx_pr_is_cross_repository"
  local head_repo_url base_repo_url fetch_source
  head_repo_url=$(_pr_head_repo_url "$pr_url" "$pr_head_owner" "$pr_head_repo") || head_repo_url=""
  base_repo_url=$(_pr_base_repo_url "$pr_url") || base_repo_url=""
  if [ -n "$remote_arg" ]; then
    fetch_source="$remote_arg"
  elif [ -n "$base_repo_url" ]; then
    fetch_source=$(_pr_preferred_repo_source "$base_repo_url") || fetch_source="$base_repo_url"
  else
    fetch_source="$remote"
  fi
  if [ -z "$branch_name" ]; then
    branch_name="$pr_head_ref"
    if [ -z "$branch_name" ]; then
      branch_name="pr/$pr_number"
    fi
  fi

  local folder_name
  folder_name=$(_resolve_folder_name "$branch_name" "$custom_name" "$folder_override") || exit 1

  local expected_worktree_path="$base_dir/${prefix}${folder_name}"
  if [ -d "$expected_worktree_path" ]; then
    log_error "Worktree $folder_name already exists at $expected_worktree_path"
    exit 1
  fi

  log_step "Creating worktree: $folder_name"
  echo "Location: $base_dir/${prefix}${folder_name}"
  echo "Pull request: #$pr_number"
  [ -n "$pr_head_ref" ] && echo "Head branch: $pr_head_ref"
  echo "Local branch: $branch_name"

  local worktree_path native_checkout=0
  if [ -z "$remote_arg" ] && [ "$force" -eq 0 ] && _pr_gh_supports_worktree; then
    local gh_checkout_args=(pr checkout "$selector" --worktree "$expected_worktree_path" --branch "$branch_name")
    [ -n "$repo_arg" ] && gh_checkout_args+=(--repo "$repo_arg")
    mkdir -p "$base_dir"
    if ! gh "${gh_checkout_args[@]}"; then
      log_error "Could not create pull request worktree with gh"
      exit 1
    fi
    worktree_path="$expected_worktree_path"
    native_checkout=1
  else
    log_step "Fetching pull request #$pr_number..."
    if ! git fetch "$fetch_source" "refs/pull/$pr_number/head"; then
      log_error "Could not fetch pull request #$pr_number from $fetch_source"
      exit 1
    fi

    local track_mode="none" branch_preexisted=0
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
      branch_preexisted=1
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

    if ! worktree_path=$(create_worktree "$base_dir" "$prefix" "$branch_name" "FETCH_HEAD" "$track_mode" "1" "$force" "$custom_name" "$folder_override" "$remote"); then
      exit 1
    fi
  fi

  if [ "$native_checkout" -eq 0 ]; then
    if ! _pr_configure_base_remote_for_gh "$pr_number" "$base_repo_url"; then
      log_warn "Could not configure base repository metadata for gh pr view"
    fi

    local branch_remote="$fetch_source" branch_merge_ref="refs/pull/$pr_number/head" branch_push_remote=""
    local matching_head_remote=""
    if [ -n "$head_repo_url" ]; then
      matching_head_remote=$(_pr_remote_for_url "$head_repo_url") || matching_head_remote=""
    fi
    if [ -n "$matching_head_remote" ]; then
      branch_remote="$matching_head_remote"
      branch_push_remote="$matching_head_remote"
      branch_merge_ref="refs/heads/$pr_head_ref"
    elif [ "$is_cross_repository" != "true" ]; then
      branch_push_remote="$fetch_source"
      branch_merge_ref="refs/heads/$pr_head_ref"
    elif [ "$maintainer_can_modify" = "true" ] && [ -n "$head_repo_url" ]; then
      branch_remote=$(_pr_preferred_repo_source "$head_repo_url") || branch_remote="$head_repo_url"
      branch_push_remote="$branch_remote"
      branch_merge_ref="refs/heads/$pr_head_ref"
    fi

    if ! _pr_configure_branch_for_gh "$branch_name" "$branch_remote" "$branch_merge_ref" "$branch_push_remote" "$branch_preexisted"; then
      log_warn "Could not configure branch metadata for gh pr view"
    fi
  fi

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
