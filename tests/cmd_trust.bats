#!/usr/bin/env bats

load test_helper

setup() {
  setup_integration_repo
  export XDG_CONFIG_HOME="$BATS_TMPDIR/gtr-trust-config-$$"
  source_gtr_commands
}

teardown() {
  rm -rf "$XDG_CONFIG_HOME"
  teardown_integration_repo
}

@test "cmd_trust marks hooks as trusted after confirmation" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[hooks]
  postCd = echo hi
EOF

  prompt_yes_no() { return 0; }

  run cmd_trust
  [ "$status" -eq 0 ]
  _hooks_are_trusted "$TEST_REPO/.gtrconfig"
}

@test "cmd_trust returns an error when the trust marker cannot be written" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[hooks]
  postCd = echo hi
EOF

  prompt_yes_no() { return 0; }
  _hooks_mark_trusted() { return 1; }

  local output_file="$BATS_TMPDIR/cmd-trust-failure.out"
  local rc=0
  if cmd_trust >"$output_file" 2>&1; then
    rc=0
  else
    rc=$?
  fi

  [ "$rc" -eq 1 ]
  grep -F "Failed to mark hooks as trusted" "$output_file"
}
