#!/usr/bin/env bats
# Trust approvals must remain private state across CLI and generated consumers.

load test_helper

setup() {
  setup_integration_repo
  export XDG_CONFIG_HOME="$TEST_REPO/config home"
  export XDG_CACHE_HOME="$TEST_REPO/cache"
  source_gtr_commands
  git config -f "$TEST_REPO/.gtrconfig" hooks.postCd 'echo approved > "$REPO_ROOT/result"'
  TRUST_MARKER=$(_hooks_current_trust_path "$TEST_REPO/.gtrconfig")
}

teardown() {
  teardown_integration_repo
}

file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

assert_storage_rejected() {
  run _hooks_marker_matches_config "$TRUST_MARKER" "$TEST_REPO/.gtrconfig"
  [ "$status" -eq 1 ]
  run _hooks_write_trust_marker "$TRUST_MARKER" "$TEST_REPO/.gtrconfig"
  [ "$status" -eq 1 ]
}

@test "trust creates private storage with umask 000 or 777 without changing caller umask" {
  local mask
  for mask in 000 777; do
    (
      umask "$mask"
      _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
      [ "$(umask)" = "0$mask" ]
    )
    [ "$(file_mode "$XDG_CONFIG_HOME")" = 700 ]
    [ "$(file_mode "$XDG_CONFIG_HOME/gtr")" = 700 ]
    [ "$(file_mode "$_GTR_TRUST_DIR")" = 700 ]
    [ "$(file_mode "$TRUST_MARKER")" = 600 ]
    _hooks_are_trusted "$TEST_REPO/.gtrconfig"
    rm -rf "$XDG_CONFIG_HOME"
  done
}

@test "safe existing readable storage supports approval, revocation and reapproval" {
  mkdir -p "$_GTR_TRUST_DIR"
  chmod 755 "$XDG_CONFIG_HOME" "$XDG_CONFIG_HOME/gtr" "$_GTR_TRUST_DIR"
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  chmod 644 "$TRUST_MARKER"
  _hooks_are_trusted "$TEST_REPO/.gtrconfig"
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  [ "$(file_mode "$_GTR_TRUST_DIR")" = 755 ]
  rm "$TRUST_MARKER"
  ! _hooks_are_trusted "$TEST_REPO/.gtrconfig"
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  _hooks_are_trusted "$TEST_REPO/.gtrconfig"
}

@test "trust refuses writable existing directories and ancestors without repairing permissions" {
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  local directory mode
  for directory in "$_GTR_TRUST_DIR" "$XDG_CONFIG_HOME/gtr" "$XDG_CONFIG_HOME"; do
    for mode in 777 775; do
      chmod "$mode" "$directory"
      assert_storage_rejected
      [ "$(file_mode "$directory")" = "$mode" ]
      chmod 700 "$directory"
    done
  done
  chmod 1777 "$_GTR_TRUST_DIR"
  assert_storage_rejected
}

@test "trust refuses to create storage below a writable ancestor" {
  mkdir "$XDG_CONFIG_HOME"
  chmod 777 "$XDG_CONFIG_HOME"
  assert_storage_rejected
  [ ! -e "$XDG_CONFIG_HOME/gtr" ]
}

@test "trust rejects writable markers without replacing them" {
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  local mode
  for mode in 666 660; do
    chmod "$mode" "$TRUST_MARKER"
    assert_storage_rejected
    [ "$(file_mode "$TRUST_MARKER")" = "$mode" ]
  done
}

@test "trust rejects marker symlinks, dangling links, directories and FIFOs" {
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  mv "$TRUST_MARKER" "$TEST_REPO/original-marker"
  ln -s "$TEST_REPO/original-marker" "$TRUST_MARKER"
  assert_storage_rejected
  [ -L "$TRUST_MARKER" ]
  [ "$(cat "$TEST_REPO/original-marker")" = "$TEST_REPO/.gtrconfig" ]
  rm "$TRUST_MARKER"
  ln -s "$TEST_REPO/missing-marker" "$TRUST_MARKER"
  assert_storage_rejected
  [ ! -e "$TEST_REPO/missing-marker" ]
  rm "$TRUST_MARKER"
  mkdir "$TRUST_MARKER"
  assert_storage_rejected
  [ -z "$(ls -A "$TRUST_MARKER")" ]
  rmdir "$TRUST_MARKER"
  mkfifo "$TRUST_MARKER"
  assert_storage_rejected
}

@test "trust rejects a symlinked trust directory without modifying its target" {
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  mv "$_GTR_TRUST_DIR" "$TEST_REPO/original-store"
  ln -s "$TEST_REPO/original-store" "$_GTR_TRUST_DIR"
  assert_storage_rejected
  [ -L "$_GTR_TRUST_DIR" ]
  [ "$(cat "$TRUST_MARKER")" = "$TEST_REPO/.gtrconfig" ]
}

@test "safe config-home symlinks and relative paths remain supported" {
  mkdir "$TEST_REPO/real config"
  ln -s "$TEST_REPO/real config" "$XDG_CONFIG_HOME"
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  _hooks_are_trusted "$TEST_REPO/.gtrconfig"
  _GTR_TRUST_DIR='config home/gtr/trusted'
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  _hooks_are_trusted "$TEST_REPO/.gtrconfig"
}

@test "trust validates symlink targets and every directory traversed through nested links" {
  mkdir "$TEST_REPO/real-config" "$TEST_REPO/link-parent"
  ln -s "$TEST_REPO/real-config" "$TEST_REPO/link-parent/link"
  ln -s "$TEST_REPO/link-parent/link" "$XDG_CONFIG_HOME"
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  chmod 777 "$TEST_REPO/real-config"
  assert_storage_rejected
  chmod 700 "$TEST_REPO/real-config"
  chmod 777 "$TEST_REPO/link-parent"
  assert_storage_rejected
}

@test "trust rejects symlink loops and non-directory storage parents" {
  ln -s "config home" "$XDG_CONFIG_HOME"
  assert_storage_rejected
  rm "$XDG_CONFIG_HOME"
  touch "$XDG_CONFIG_HOME"
  assert_storage_rejected
}

# A stat shim exercises foreign ownership without requiring root/chown. Other
# metadata, including repository identity, still comes from the real stat.
mock_foreign_owner() {
  export UNSAFE_STORAGE_PATH="$1"
  export REAL_STAT
  REAL_STAT=$(command -v stat)
  mkdir -p "$TEST_REPO/mock-bin"
  cat > "$TEST_REPO/mock-bin/stat" <<'SH'
#!/usr/bin/env bash
for arg in "$@"; do last="$arg"; done
if [ "$last" = "$UNSAFE_STORAGE_PATH" ]; then
  printf '999999:700\n'
else
  exec "$REAL_STAT" "$@"
fi
SH
  chmod +x "$TEST_REPO/mock-bin/stat"
  export PATH="$TEST_REPO/mock-bin:$PATH"
}

@test "trust rejects foreign-owned markers, directories, ancestors and config symlinks" {
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  mock_foreign_owner "$TRUST_MARKER"
  assert_storage_rejected
  export UNSAFE_STORAGE_PATH="$_GTR_TRUST_DIR"
  assert_storage_rejected
  export UNSAFE_STORAGE_PATH="$XDG_CONFIG_HOME"
  assert_storage_rejected
  mv "$XDG_CONFIG_HOME" "$TEST_REPO/real-config"
  ln -s "$TEST_REPO/real-config" "$XDG_CONFIG_HOME"
  assert_storage_rejected
}

@test "cmd_trust reports failure and leaves unsafe storage intact" {
  mkdir -p "$_GTR_TRUST_DIR"
  chmod 777 "$_GTR_TRUST_DIR"
  prompt_yes_no() { return 0; }
  run cmd_trust
  [ "$status" -eq 1 ]
  [[ "$output" == *'Failed to mark executable commands as trusted'* ]]
  [ ! -e "$TRUST_MARKER" ]
  [ "$(file_mode "$_GTR_TRUST_DIR")" = 777 ]
}

@test "trust refuses marker destinations outside the configured store" {
  run _hooks_write_trust_marker "$TEST_REPO/$(basename "$TRUST_MARKER")" "$TEST_REPO/.gtrconfig"
  [ "$status" -eq 1 ]
  [ ! -e "$TEST_REPO/$(basename "$TRUST_MARKER")" ]
}

@test "generated storage helpers stay identical to CLI helpers" {
  local expected actual
  expected=$(declare -f _hooks_storage_stat _hooks_trust_directory _hooks_safe_trust_path)
  eval "$(_init_emit_trust_storage_helpers)"
  actual=$(declare -f _hooks_storage_stat _hooks_trust_directory _hooks_safe_trust_path)
  [ "$expected" = "$actual" ]
}

exercise_generated_storage() (
  set -e
  local shell_name="$1" directory
  export INIT_FIXTURE="$TEST_REPO/init.$shell_name"
  export REPO_FIXTURE="$TEST_REPO"
  cmd_init "$shell_name" --as safe_gtr > "$INIT_FIXTURE"
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  chmod 755 "$_GTR_TRUST_DIR"
  chmod 644 "$TRUST_MARKER"
  "$shell_name" -c 'source "$INIT_FIXTURE"; safe_gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ "$(cat "$TEST_REPO/result")" = approved ]
  rm "$TEST_REPO/result"
  for directory in "$_GTR_TRUST_DIR" "$XDG_CONFIG_HOME/gtr" "$XDG_CONFIG_HOME"; do
    chmod 777 "$directory"
    "$shell_name" -c 'source "$INIT_FIXTURE"; safe_gtr_run_post_cd_hooks "$REPO_FIXTURE"'
    [ ! -e "$TEST_REPO/result" ]
    chmod 700 "$directory"
  done
  chmod 666 "$TRUST_MARKER"
  "$shell_name" -c 'source "$INIT_FIXTURE"; safe_gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ ! -e "$TEST_REPO/result" ]
  chmod 600 "$TRUST_MARKER"
  mv "$TRUST_MARKER" "$TEST_REPO/original-marker"
  ln -s "$TEST_REPO/original-marker" "$TRUST_MARKER"
  "$shell_name" -c 'source "$INIT_FIXTURE"; safe_gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ ! -e "$TEST_REPO/result" ]
  rm "$TRUST_MARKER"
  mv "$TEST_REPO/original-marker" "$TRUST_MARKER"
  mv "$_GTR_TRUST_DIR" "$TEST_REPO/original-store"
  ln -s "$TEST_REPO/original-store" "$_GTR_TRUST_DIR"
  "$shell_name" -c 'source "$INIT_FIXTURE"; safe_gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ ! -e "$TEST_REPO/result" ]
  rm "$_GTR_TRUST_DIR"
  mv "$TEST_REPO/original-store" "$_GTR_TRUST_DIR"
  mock_foreign_owner "$TRUST_MARKER"
  "$shell_name" -c 'source "$INIT_FIXTURE"; safe_gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ ! -e "$TEST_REPO/result" ]
  export UNSAFE_STORAGE_PATH="$_GTR_TRUST_DIR"
  "$shell_name" -c 'source "$INIT_FIXTURE"; safe_gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ ! -e "$TEST_REPO/result" ]
  export UNSAFE_STORAGE_PATH=""
  rm "$TRUST_MARKER"
  "$shell_name" -c 'source "$INIT_FIXTURE"; safe_gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ ! -e "$TEST_REPO/result" ]
  _hooks_mark_trusted "$TEST_REPO/.gtrconfig"
  "$shell_name" -c 'source "$INIT_FIXTURE"; safe_gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ "$(cat "$TEST_REPO/result")" = approved ]
  # Config-home symlinks are valid only while their target path stays safe.
  mv "$XDG_CONFIG_HOME" "$TEST_REPO/real-config"
  ln -s "$TEST_REPO/real-config" "$XDG_CONFIG_HOME"
  rm "$TEST_REPO/result"
  "$shell_name" -c 'source "$INIT_FIXTURE"; safe_gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ "$(cat "$TEST_REPO/result")" = approved ]
  rm "$TEST_REPO/result"
  chmod 777 "$TEST_REPO/real-config"
  "$shell_name" -c 'source "$INIT_FIXTURE"; safe_gtr_run_post_cd_hooks "$REPO_FIXTURE"'
  [ ! -e "$TEST_REPO/result" ]
)

@test "generated Bash helpers reject unsafe approvals and support trust revocation" {
  exercise_generated_storage bash
}

@test "generated Zsh helpers reject unsafe approvals and support trust revocation" {
  command -v zsh >/dev/null || skip 'zsh is not installed'
  exercise_generated_storage zsh
}

@test "generated Fish helpers reject unsafe approvals and support trust revocation" {
  command -v fish >/dev/null || skip 'fish is not installed'
  exercise_generated_storage fish
}
