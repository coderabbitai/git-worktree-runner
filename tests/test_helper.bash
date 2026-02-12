#!/usr/bin/env bash
# Shared test helper — sources libs with minimal stubs for isolated testing

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

# Stubs for ui.sh functions (avoid log output in tests)
log_info() { :; }
log_warn() { :; }
log_error() { :; }
log_step() { :; }
# show_command_help is called by parse_args on -h/--help — stub exits 0
show_command_help() { exit 0; }
export -f log_info log_warn log_error log_step show_command_help

# Stubs for config.sh functions (tests that need real config should source it explicitly)
cfg_default() { printf "%s" "${3:-}"; }
cfg_get_all() { :; }
export -f cfg_default cfg_get_all

# ── Integration test helpers ─────────────────────────────────────────────────

# Set up a disposable git repo for integration tests
# Sets: TEST_REPO, TEST_WORKTREES_DIR
setup_integration_repo() {
  TEST_REPO=$(mktemp -d)
  TEST_WORKTREES_DIR="${TEST_REPO}-worktrees"
  git -C "$TEST_REPO" init --quiet
  git -C "$TEST_REPO" config user.name "Test User"
  git -C "$TEST_REPO" config user.email "test@example.com"
  git -C "$TEST_REPO" commit --allow-empty -m "init" --quiet
  export GTR_DIR="$PROJECT_ROOT"
  cd "$TEST_REPO" || return 1
}

# Clean up: remove worktrees first, then temp dirs
teardown_integration_repo() {
  cd / 2>/dev/null || true
  if [ -d "$TEST_REPO" ]; then
    # Remove worktrees properly before deleting
    git -C "$TEST_REPO" worktree list --porcelain 2>/dev/null | while IFS= read -r line; do
      case "$line" in
        "worktree "*)
          local wt_path="${line#worktree }"
          [ "$wt_path" = "$TEST_REPO" ] && continue
          git -C "$TEST_REPO" worktree remove --force "$wt_path" 2>/dev/null || true
          ;;
      esac
    done
    rm -rf "$TEST_REPO" "$TEST_WORKTREES_DIR"
  fi
}

# Source the full library chain (without running main)
source_gtr_libs() {
  export GTR_DIR="$PROJECT_ROOT"
  # shellcheck disable=SC1091
  . "$PROJECT_ROOT/lib/ui.sh"
  # shellcheck disable=SC1091
  . "$PROJECT_ROOT/lib/args.sh"
  # shellcheck disable=SC1091
  . "$PROJECT_ROOT/lib/config.sh"
  # shellcheck disable=SC1091
  . "$PROJECT_ROOT/lib/platform.sh"
  # shellcheck disable=SC1091
  . "$PROJECT_ROOT/lib/core.sh"
  # shellcheck disable=SC1091
  . "$PROJECT_ROOT/lib/copy.sh"
  # shellcheck disable=SC1091
  . "$PROJECT_ROOT/lib/hooks.sh"
  # shellcheck disable=SC1091
  . "$PROJECT_ROOT/lib/provider.sh"
  # shellcheck disable=SC1091
  . "$PROJECT_ROOT/lib/adapters.sh"
}
