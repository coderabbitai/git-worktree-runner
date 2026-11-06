#!/usr/bin/env bash

# Fail only the selected find invocation, optionally after a complete NUL record.
# Other scans use the real find, so Git and test cleanup remain unaffected.
# Usage: install_copy_find_stub <private_bin_dir>
# Set TEST_COPY_FIND_ARGS and TEST_COPY_FIND_RECORD to select the failing scan.
install_copy_find_stub() {
  local mock_bin="$1"
  export TEST_COPY_REAL_FIND TEST_COPY_FIND_HIT TEST_COPY_FIND_ARGS TEST_COPY_FIND_RECORD
  TEST_COPY_REAL_FIND=$(command -v find)
  TEST_COPY_FIND_HIT="$mock_bin/find-hit"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/find" <<'SCRIPT'
#!/usr/bin/env bash
if [ "$*" = "$TEST_COPY_FIND_ARGS" ]; then
  printf 'called\n' >> "$TEST_COPY_FIND_HIT"
  if [ -n "$TEST_COPY_FIND_RECORD" ]; then
    printf '%s\0' "$TEST_COPY_FIND_RECORD"
  fi
  echo 'find: injected discovery failure' >&2
  exit 7
fi
exec "$TEST_COPY_REAL_FIND" "$@"
SCRIPT
  chmod +x "$mock_bin/find"
  export PATH="$mock_bin:$PATH"
}
