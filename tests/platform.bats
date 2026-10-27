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

@test "macOS terminals treat command substitutions and quotes in paths as literal data" {
  export OSTYPE=darwin
  local terminal
  for terminal in iTerm Terminal; do
    export GTR_TEST_TERMINAL="$terminal"
    export GTR_TEST_SCRIPT="$_platform_mock_bin/applescript"
    cat > "$_platform_mock_bin/osascript" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = -e ]; then
  printf '%s\n' "$GTR_TEST_TERMINAL"
else
  cat > "$GTR_TEST_SCRIPT"
fi
EOF
    chmod +x "$_platform_mock_bin/osascript"
    local path="$_platform_mock_bin/"'$(touch injected) `touch injected2` '\''quote"back\slash'
    mkdir -p "$path"
    local expected_path
    expected_path=$(cd -P "$path" && pwd)
    spawn_terminal_in "$path" 'title' ''
    # Decode the AppleScript string and run the actual shell command it carries.
    python3 - "$GTR_TEST_SCRIPT" "$_platform_mock_bin/command" <<'PYCODE'
import re, sys
s = open(sys.argv[1]).read()
m = re.search(r'(?:write text|do script) "((?:\\.|[^"\\])*)"', s)
assert m, s
command = re.sub(r'\\([\\"])', r'\1', m.group(1))
open(sys.argv[2], 'w').write(command + '\npwd -P\n')
PYCODE
    run bash "$_platform_mock_bin/command"
    [ "$status" -eq 0 ]
    [ "$output" = "$expected_path" ]
    [ ! -e injected ]
    [ ! -e injected2 ]
  done
}
