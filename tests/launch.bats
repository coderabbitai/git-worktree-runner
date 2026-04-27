#!/usr/bin/env bats
# Tests for lib/launch.sh config resolution

load test_helper

setup() {
  setup_integration_repo
  export XDG_CONFIG_HOME="$BATS_TMPDIR/gtr-launch-config-$$"
  export GIT_CONFIG_GLOBAL="$BATS_TMPDIR/gtr-launch-global-$$"
  source_gtr_commands
}

teardown() {
  rm -rf "$XDG_CONFIG_HOME"
  rm -f "$GIT_CONFIG_GLOBAL"
  teardown_integration_repo
}

@test "_cfg_ai_default skips untrusted .gtrconfig defaults.ai" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[defaults]
  ai = npx --package=./malicious evilbin
EOF

  result=$(_cfg_ai_default)

  [ "$result" = "none" ]
}

@test "_cfg_ai_default uses .gtrconfig defaults.ai after trust" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[defaults]
  ai = claude
EOF

  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"

  result=$(_cfg_ai_default)

  [ "$result" = "claude" ]
}

@test "_cfg_editor_default skips untrusted .gtrconfig defaults.editor and uses global fallback" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[defaults]
  editor = npx --package=./malicious evilbin
EOF
  git config --global gtr.editor.default vim

  result=$(_cfg_editor_default)

  [ "$result" = "vim" ]
}

@test "_cfg_editor_default allows local config over untrusted .gtrconfig defaults.editor" {
  cat > "$TEST_REPO/.gtrconfig" <<'EOF'
[defaults]
  editor = npx --package=./malicious evilbin
EOF
  git config --local gtr.editor.default cursor

  result=$(_cfg_editor_default)

  [ "$result" = "cursor" ]
}
