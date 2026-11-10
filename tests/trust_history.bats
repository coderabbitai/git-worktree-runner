#!/usr/bin/env bats

load test_helper

setup() {
  setup_integration_repo
  export XDG_CONFIG_HOME="$TEST_REPO/private-config"
  export XDG_CACHE_HOME="$TEST_REPO/private-cache"
  export XDG_DATA_HOME="$TEST_REPO/private-data"
  source_gtr_commands
}

teardown() {
  teardown_integration_repo
}

run_history_hook() {
  local runtime="$1"
  if [ "$runtime" = cli ]; then
    run_hooks postCd REPO_ROOT="$TEST_REPO"
  else
    "$runtime" -c 'source "$HISTORY_INIT"; gtr_run_post_cd_hooks "$TEST_REPO"'
  fi
}

# Preserve the filesystem identity and hook definitions, but replace the Git
# database with unrelated history. Only disposable repositories are modified.
preserved_directory_history_case() {
  local runtime="$1" history="${2:-unrelated}" initial approved identity repo_identity donor="$TEST_REPO/donor"
  export TEST_REPO HISTORY_INIT="$TEST_REPO/init.$runtime"
  initial=$(git rev-parse HEAD)
  git config -f .gtrconfig hooks.postCd 'sh "$REPO_ROOT/bootstrap.sh"'
  printf 'echo approved > "$REPO_ROOT/result"\n' > bootstrap.sh
  git add bootstrap.sh
  git commit --quiet -m approved
  approved=$(git rev-parse HEAD)
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  if [ "$runtime" != cli ]; then cmd_init "$runtime" > "$HISTORY_INIT"; fi
  run_history_hook "$runtime"
  [ "$(cat result)" = approved ]

  # Normal updates and a branch forked before approval must keep working.
  printf 'echo updated > "$REPO_ROOT/result"\n' > bootstrap.sh
  git add bootstrap.sh
  git commit --quiet -m updated
  run_history_hook "$runtime"
  [ "$(cat result)" = updated ]
  git checkout --quiet -b related "$initial"
  printf 'echo related > "$REPO_ROOT/result"\n' > bootstrap.sh
  git add bootstrap.sh
  git commit --quiet -m related
  run_history_hook "$runtime"
  [ "$(cat result)" = related ]
  rm result

  identity=$(stat -c '%d:%i:%W:%w' .git 2>/dev/null) || identity=$(stat -f '%d:%i:%.9FB' .git)
  repo_identity=$(_hooks_repo_identity "$TEST_REPO")
  if [ "$history" = related ]; then
    git clone --quiet --no-hardlinks "$TEST_REPO" "$donor"
  else
    git init --quiet "$donor"
    git -C "$donor" -c user.name=Fixture -c user.email=fixture@example.test \
      -c commit.gpgsign=false commit --allow-empty --quiet -m unrelated
  fi
  # Keep the approved objects available: mere object existence is not continuity.
  git -C "$donor" fetch --quiet "$TEST_REPO" "$approved"
  if [ "$history" = unrelated ]; then
    # Also preserve the object database directory to exercise the independent
    # history check; old objects alone and forged ancestry must not suffice.
    find "$TEST_REPO/.git" -mindepth 1 -maxdepth 1 ! -name objects -exec rm -rf -- {} +
    find "$TEST_REPO/.git/objects" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  else
    find "$TEST_REPO/.git" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
  fi
  cp -R "$donor/.git/." "$TEST_REPO/.git/"
  printf 'echo replacement > "$REPO_ROOT/result"\n' > bootstrap.sh
  local current_identity
  current_identity=$(stat -c '%d:%i:%W:%w' .git 2>/dev/null) || current_identity=$(stat -f '%d:%i:%.9FB' .git)
  [ "$current_identity" = "$identity" ]
  if [ "$history" = unrelated ]; then
    [ "$(_hooks_repo_identity "$TEST_REPO")" = "$repo_identity" ]
  fi
  run_history_hook "$runtime"
  [ ! -e result ]

  if [ "$history" = related ]; then
    _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
    run_history_hook "$runtime"
    [ "$(cat result)" = replacement ]
    return 0
  fi

  # Repository-owned grafts and replace refs must not forge shared history.
  printf '%s %s\n' "$(git rev-parse HEAD)" "$approved" > .git/info/grafts
  run_history_hook "$runtime"
  [ ! -e result ]
  rm .git/info/grafts
  git replace "$(git rev-parse HEAD)" "$approved"
  run_history_hook "$runtime"
  [ ! -e result ]
  git replace -d "$(git rev-parse HEAD)"

  # Explicitly approving the replacement repository restores execution.
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  run_history_hook "$runtime"
  [ "$(cat result)" = replacement ]
}

@test "CLI rejects unrelated Git contents with a preserved common directory" {
  preserved_directory_history_case cli
}

@test "bash hooks reject unrelated Git contents with a preserved common directory" {
  preserved_directory_history_case bash
}

@test "zsh hooks reject unrelated Git contents with a preserved common directory" {
  command -v zsh >/dev/null || skip "zsh unavailable"
  preserved_directory_history_case zsh
}

@test "fish hooks reject unrelated Git contents with a preserved common directory" {
  command -v fish >/dev/null || skip "fish unavailable"
  preserved_directory_history_case fish
}

@test "CLI rejects a replaced object database even when it retains shared history" {
  preserved_directory_history_case cli related
}

@test "bash hooks reject a replaced object database even when it retains shared history" {
  preserved_directory_history_case bash related
}

@test "zsh hooks reject a replaced object database even when it retains shared history" {
  command -v zsh >/dev/null || skip "zsh unavailable"
  preserved_directory_history_case zsh related
}

@test "fish hooks reject a replaced object database even when it retains shared history" {
  command -v fish >/dev/null || skip "fish unavailable"
  preserved_directory_history_case fish related
}

@test "old v3 approval cannot bypass history checks in the CLI or generated shells" {
  export TEST_REPO HISTORY_INIT
  git config -f .gtrconfig hooks.postCd 'echo old-approval > "$REPO_ROOT/result"'
  local key runtime common_dir identity
  common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd -P)
  identity=$(LC_ALL=C TZ=UTC stat -c '%d:%i:%W:%w' "$common_dir" 2>/dev/null) ||
    identity=$(LC_ALL=C stat -f '%d:%i:%.9FB' "$common_dir")
  key=$(printf 'v3\n%s\n%s\n%s\n%s\n' "$TEST_REPO" \
    "$common_dir" "$identity" "$(_hooks_file_hash "$TEST_REPO/.gtrconfig")" |
    shasum -a 256 | cut -d' ' -f1)
  mkdir -p "$_GTR_TRUST_DIR"
  printf '%s\n' "$TEST_REPO/.gtrconfig" > "$_GTR_TRUST_DIR/$key"
  for runtime in cli bash zsh fish; do
    command -v "$runtime" >/dev/null || [ "$runtime" = cli ] || continue
    if [ "$runtime" != cli ]; then
      HISTORY_INIT="$TEST_REPO/init.$runtime"
      cmd_init "$runtime" > "$HISTORY_INIT"
    fi
    run_history_hook "$runtime"
    [ ! -e result ]
  done
}

@test "repository commit-graph cache cannot forge ancestry for approved commands" {
  command -v python3 >/dev/null || skip "python3 unavailable"
  git help -a | grep -q 'commit-graph' || skip "Git commit-graph unavailable"
  local approved middle head
  git config -f .gtrconfig hooks.postCd 'echo escaped > "$REPO_ROOT/result"'
  approved=$(git rev-parse HEAD)
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  git checkout --quiet --orphan unrelated
  git commit --allow-empty --quiet -m unrelated
  middle=$(git rev-parse HEAD)
  git commit --allow-empty --quiet -m unrelated-child
  head=$(git rev-parse HEAD)
  git -c commitGraph.generationVersion=1 commit-graph write --reachable
  chmod u+w .git/objects/info/commit-graph
  # Forge a cached parent for an intermediate commit, preserving actual object
  # bytes. Endpoint-only checks and the public graph checksum cannot detect it.
  python3 - "$approved" "$middle" "$head" <<'PY'
import hashlib
from pathlib import Path
import struct
import sys

path = Path('.git/objects/info/commit-graph')
data = bytearray(path.read_bytes())
assert data[:5] == b'CGPH\x01'
hash_size = {1: 20, 2: 32}[data[5]]
chunks = dict(struct.unpack_from('>4sQ', data, 8 + 12 * i) for i in range(data[6]))
count = struct.unpack_from('>I', data, chunks[b'OIDF'] + 4 * 255)[0]
oids = [data[chunks[b'OIDL'] + i * hash_size:chunks[b'OIDL'] + (i + 1) * hash_size].hex()
        for i in range(count)]
entry = chunks[b'CDAT'] + oids.index(sys.argv[2]) * (hash_size + 16)
struct.pack_into('>III', data, entry + hash_size, oids.index(sys.argv[1]), 0x70000000, 2 << 2)
entry = chunks[b'CDAT'] + oids.index(sys.argv[3]) * (hash_size + 16)
struct.pack_into('>I', data, entry + hash_size + 8, 3 << 2)
data[-hash_size:] = hashlib.new('sha1' if hash_size == 20 else 'sha256', data[:-hash_size]).digest()
path.write_bytes(data)
PY
  run_hooks postCd REPO_ROOT="$TEST_REPO"
  [ ! -e result ]
}
