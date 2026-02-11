#!/usr/bin/env bash
# Shared test helper — sources libs with minimal stubs for isolated testing

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$TESTS_DIR/.." && pwd)"

# Stubs for ui.sh functions (avoid log output in tests)
log_info() { :; }
log_warn() { :; }
log_error() { :; }
log_step() { :; }
export -f log_info log_warn log_error log_step

# Stubs for config.sh functions (tests that need real config should source it explicitly)
cfg_default() { printf "%s" "${3:-}"; }
cfg_get_all() { :; }
export -f cfg_default cfg_get_all
