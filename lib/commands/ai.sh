#!/usr/bin/env bash

# AI command
cmd_ai() {
  local identifier=""
  local ai_tool=""
  local -a ai_args=()

  # Parse arguments
  while [ $# -gt 0 ]; do
    case "$1" in
      --ai)
        ai_tool="$2"
        shift 2
        ;;
      --)
        shift
        ai_args=("$@")
        break
        ;;
      -*)
        log_error "Unknown flag: $1"
        exit 1
        ;;
      *)
        if [ -z "$identifier" ]; then
          identifier="$1"
        fi
        shift
        ;;
    esac
  done

  if [ -z "$identifier" ]; then
    log_error "Usage: git gtr ai <id|branch> [--ai <name>] [-- args...]"
    exit 1
  fi

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

  # Load AI adapter
  load_ai_adapter "$ai_tool" || exit 1

  resolve_repo_context || exit 1
  local repo_root="$_ctx_repo_root" base_dir="$_ctx_base_dir" prefix="$_ctx_prefix"

  # Resolve target branch
  local worktree_path branch
  resolve_worktree "$identifier" "$repo_root" "$base_dir" "$prefix" || exit 1
  worktree_path="$_ctx_worktree_path" branch="$_ctx_branch"

  log_step "Starting $ai_tool for: $branch"
  echo "Directory: $worktree_path"
  echo "Branch: $branch"

  ai_start "$worktree_path" "${ai_args[@]}"
}