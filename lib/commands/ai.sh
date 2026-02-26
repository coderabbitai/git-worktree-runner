#!/usr/bin/env bash

# AI command
# shellcheck disable=SC2154  # _arg_* _pa_* set by parse_args, _ctx_* set by resolve_*
cmd_ai() {
  parse_args "--ai: value" "$@"
  require_args 1 "Usage: git gtr ai <id|branch> [--ai <name>] [-- args...]"

  local identifier="${_pa_positional[0]}"
  local ai_tool="${_arg_ai:-}"
  local -a ai_args=("${_pa_passthrough[@]}")

  # Get AI tool from flag or config (with .gtrconfig support)
  if [ -z "$ai_tool" ]; then
    ai_tool=$(_cfg_ai_default)
  fi

  # Check if AI tool is configured
  if [ "$ai_tool" = "none" ]; then
    log_error "No AI tool configured"
    log_info "Set default: git gtr config set gtr.ai.default claude"
    exit 1
  fi

  resolve_repo_context || exit 1

  local repo_root="$_ctx_repo_root" base_dir="$_ctx_base_dir" prefix="$_ctx_prefix"

  # Load AI adapter (after context — fail fast on bad repo first)
  load_ai_adapter "$ai_tool" || exit 1

  # Resolve target branch
  local worktree_path branch
  resolve_worktree "$identifier" "$repo_root" "$base_dir" "$prefix" || exit 1

  worktree_path="$_ctx_worktree_path" branch="$_ctx_branch"

  log_step "Starting $ai_tool for: $branch"
  log_info "Directory: $worktree_path"
  log_info "Branch: $branch"

  # Run postCd hooks + AI in a subshell so hook env vars propagate to AI
  (
    cd "$worktree_path" || exit 1
    run_hooks_export "postCd" \
      REPO_ROOT="$repo_root" \
      WORKTREE_PATH="$worktree_path" \
      BRANCH="$branch"
    ai_start "$worktree_path" "${ai_args[@]}"
  )
}