#!/usr/bin/env bats

load test_helper

setup() {
  source "$PROJECT_ROOT/lib/platform.sh"
  _platform_mock_bin="$(mktemp -d)"
  export PATH="$_platform_mock_bin:$PATH"
  export OSTYPE="linux-gnu"
}

teardown() {
  rm -rf "$_platform_mock_bin"
}

@test "spawn_terminal_in passes multi-word commands as separate terminal args on linux" {
  cat > "$_platform_mock_bin/gnome-terminal" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" > "$BATS_TMPDIR/gnome-terminal-args"
EOF
  chmod +x "$_platform_mock_bin/gnome-terminal"

  run spawn_terminal_in "/tmp/work tree" "Test title" "echo hello"
  [ "$status" -eq 0 ]

  grep -Fx -- "--working-directory=/tmp/work tree" "$BATS_TMPDIR/gnome-terminal-args"
  grep -Fx -- "--title=Test title" "$BATS_TMPDIR/gnome-terminal-args"
  grep -Fx -- "bash" "$BATS_TMPDIR/gnome-terminal-args"
  grep -Fx -- "-lc" "$BATS_TMPDIR/gnome-terminal-args"
  grep -Fx -- "echo hello" "$BATS_TMPDIR/gnome-terminal-args"
}
