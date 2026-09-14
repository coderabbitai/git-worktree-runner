#!/usr/bin/env bats
# Tests for the GTR_DEBUG error trap in bin/git-gtr
#
# The trap is only useful when bin/git-gtr enables errtrace. An ERR trap is
# inherited by functions, command substitutions and subshells only under
# 'set -E'; with plain 'set -e' it never fires, because every command runs
# inside main() and then a cmd_* handler. These tests run the real binary as a
# subprocess so that the option line in bin/git-gtr is actually exercised.

load test_helper

setup() {
  setup_integration_repo

  # A git shim that fails one specific config write and passes everything else
  # through, standing in for an unexpected git failure at an unguarded call
  # site (cfg_set in lib/config.sh).
  REAL_GIT=$(command -v git)
  SHIM_DIR=$(mktemp -d)
  cat > "$SHIM_DIR/git" <<SCRIPT
#!/usr/bin/env bash
if [ "\$1" = "config" ]; then
  case "\$*" in
    *--get*|*--list*|*--file*) : ;;
    *gtr.editor.default*) exit 4 ;;
  esac
fi
exec "$REAL_GIT" "\$@"
SCRIPT
  chmod +x "$SHIM_DIR/git"
}

teardown() {
  [ -n "${SHIM_DIR:-}" ] && rm -rf "$SHIM_DIR"
  teardown_integration_repo
}

@test "GTR_DEBUG reports file, line and function for an unguarded failure" {
  run env PATH="$SHIM_DIR:$PATH" GTR_DEBUG=1 \
    "$PROJECT_ROOT/bin/git-gtr" config set gtr.editor.default vim
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR at "* ]]
  [[ "$output" == *"lib/config.sh"* ]]
  [[ "$output" == *"cfg_set()"* ]]
}

@test "the error trap stays silent when GTR_DEBUG is unset" {
  run env PATH="$SHIM_DIR:$PATH" \
    "$PROJECT_ROOT/bin/git-gtr" config set gtr.editor.default vim
  [ "$status" -ne 0 ]
  [[ "$output" != *"ERROR at "* ]]
}

@test "GTR_DEBUG does not report anything for a successful command" {
  run env GTR_DEBUG=1 "$PROJECT_ROOT/bin/git-gtr" config set gtr.editor.default vim
  [ "$status" -eq 0 ]
  [[ "$output" != *"ERROR at "* ]]
}

@test "GTR_DEBUG does not report handled errors" {
  # cmd_go reports a missing worktree itself; that is a deliberate error path,
  # not an unguarded failure, so the trap must not add noise to it.
  run env GTR_DEBUG=1 "$PROJECT_ROOT/bin/git-gtr" go no-such-branch
  [ "$status" -ne 0 ]
  [[ "$output" != *"ERROR at "* ]]
}

@test "GTR_DEBUG reports a failure raised inside a subshell" {
  # cmd_run executes the requested command in a subshell:
  #   (cd "$worktree_path" && "${run_args[@]}")
  # A failing command there is only reported when the ERR trap is inherited by
  # subshells, which is the other half of what errtrace buys.
  run env GTR_DEBUG=1 "$PROJECT_ROOT/bin/git-gtr" run 1 false
  [ "$status" -ne 0 ]
  [[ "$output" == *"ERROR at "* ]]
  [[ "$output" == *"lib/commands/run.sh"* ]]
  [[ "$output" == *"cmd_run()"* ]]
}

@test "a successful command under gtr run reports nothing" {
  run env GTR_DEBUG=1 "$PROJECT_ROOT/bin/git-gtr" run 1 true
  [ "$status" -eq 0 ]
  [[ "$output" != *"ERROR at "* ]]
}
