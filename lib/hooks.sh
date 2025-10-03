#!/bin/sh
# Hook execution system

# Run hooks for a specific phase
# Usage: run_hooks phase [env_vars...]
# Example: run_hooks postCreate REPO_ROOT="$root" WORKTREE_PATH="$path"
run_hooks() {
  local phase="$1"
  shift

  local hooks
  hooks=$(cfg_get_all "gtr.hook.$phase")

  if [ -z "$hooks" ]; then
    # No hooks configured for this phase
    return 0
  fi

  log_step "Running $phase hooks..."

  local hook_count=0
  local failed=0

  # Export provided environment variables
  while [ $# -gt 0 ]; do
    export "$1"
    shift
  done

  # Execute each hook (without subshell to preserve state)
  while IFS= read -r hook; do
    [ -z "$hook" ] && continue

    hook_count=$((hook_count + 1))
    log_info "Hook $hook_count: $hook"

    # Run hook and capture exit code
    if eval "$hook"; then
      log_info "Hook $hook_count completed successfully"
    else
      local rc=$?
      log_error "Hook $hook_count failed with exit code $rc"
      failed=$((failed + 1))
    fi
  done <<EOF
$hooks
EOF

  if [ "$failed" -gt 0 ]; then
    log_warn "$failed hook(s) failed"
    return 1
  fi

  return 0
}

# Run hooks in a specific directory
# Usage: run_hooks_in phase directory [env_vars...]
run_hooks_in() {
  local phase="$1"
  local directory="$2"
  shift 2

  local old_pwd
  old_pwd=$(pwd)

  if [ ! -d "$directory" ]; then
    log_error "Directory does not exist: $directory"
    return 1
  fi

  cd "$directory" || return 1

  run_hooks "$phase" "$@"
  local result=$?

  cd "$old_pwd" || return 1

  return $result
}
