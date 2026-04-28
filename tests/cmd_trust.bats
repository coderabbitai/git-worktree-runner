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

@test "cmd_trust marks executable commands as trusted after confirmation" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[hooks]
  postCd = echo hi
[defaults]
  ai = claude
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
  _hooks_write_trust_marker() { return 1; }

  local output_file="$BATS_TMPDIR/cmd-trust-failure.out"
  local rc=0
  if cmd_trust >"$output_file" 2>&1; then
    rc=0
  else
    rc=$?
  fi

  [ "$rc" -eq 1 ]
  grep -F "Failed to mark executable commands as trusted" "$output_file"
}

@test "cmd_trust trusts the reviewed snapshot and fails if hooks change during confirmation" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[hooks]
  postCd = echo reviewed
EOF

  local reviewed_trust_path
  reviewed_trust_path=$(_hooks_trust_path "$TEST_REPO/.gtrconfig")

  prompt_yes_no() {
    cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[hooks]
  postCd = echo changed
EOF
    return 0
  }

  local output_file="$BATS_TMPDIR/cmd-trust-changed.out"
  local rc=0
  if cmd_trust >"$output_file" 2>&1; then
    rc=0
  else
    rc=$?
  fi

  [ "$rc" -eq 1 ]
  [ -f "$reviewed_trust_path" ]
  ! _hooks_are_trusted "$TEST_REPO/.gtrconfig"
  grep -F "Executable commands changed during review; current commands remain untrusted" "$output_file"
}

@test "cmd_trust writes the reviewed marker when hooks change during confirmation" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[hooks]
  postCd = echo original
EOF

  local reviewed_marker
  reviewed_marker="$(_hooks_trust_path "$TEST_REPO/.gtrconfig")"

  prompt_yes_no() {
    cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[hooks]
  postCd = echo changed
EOF
    return 0
  }

  run cmd_trust
  [ "$status" -eq 1 ]
  [[ "$output" == *"Executable commands changed during review; current commands remain untrusted"* ]]
  [ -f "$reviewed_marker" ]

  run _hooks_are_trusted "$TEST_REPO/.gtrconfig"
  [ "$status" -eq 1 ]
}
