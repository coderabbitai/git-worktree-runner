#!/usr/bin/env bats
# Execute generated pickers with disposable repositories and harmless launch/delete stubs.

load test_helper

setup() {
  setup_integration_repo
  source_gtr_commands
  export PROJECT_ROOT
  export XDG_CACHE_HOME="$TEST_REPO/cache" XDG_CONFIG_HOME="$TEST_REPO/config"
  export XDG_DATA_HOME="$TEST_REPO/data" GTR_VERSION=test
  export PICKER_LOG="$TEST_REPO/action-log"
  mkdir "$TEST_REPO/bin"
  cat > "$TEST_REPO/bin/git-gtr" <<'STUB'
#!/bin/bash
set -e
. "$PROJECT_ROOT/tests/test_helper.bash"
source_gtr_commands
_open_editor() { printf '%s\0%s\0' editor "$2" > "$PICKER_LOG"; }
load_ai_adapter() { :; }
ai_start() { printf '%s\0%s\0' ai "$1" > "$PICKER_LOG"; }
remove_worktree() { printf '%s\0%s\0' rm "$1" > "$PICKER_LOG"; }
subcommand="$1"
shift
case "$subcommand" in
  rm) cmd_remove "$@" ;;
  *) "cmd_$subcommand" "$@" ;;
esac
STUB
  cat > "$TEST_REPO/bin/fzf" <<'STUB'
#!/bin/bash
set -e
selection=""
while IFS= read -r row; do
  if [ "${row%%$'\t'*}" = "$PICKER_ID" ]; then selection="$row"; fi
done
[ -n "$selection" ]
case "$PICKER_KEY" in
  ctrl-d|ctrl-y)
    for arg in "$@"; do
      case "$arg" in
        "--bind=$PICKER_KEY:execute("*)
          action="${arg#*execute(}"
          action="${action%%)*}"
          # Mimic fzf's shell-quoted placeholders, running without a TTY.
          # Reject the old ambiguous branch placeholder explicitly.
          [[ "$action" != *'{2}'* ]]
          [[ "$action" == *'{s1}'* ]]
          printf -v quoted '%q' "$PICKER_ID"
          # Concatenation preserves printf %q's backslashes across Bash versions.
          action="${action%%\{s1\}*}${quoted}${action#*\{s1\}}"
          action="${action% > /dev/tty 2>&1 < /dev/tty}"
          bash -c "$action"
          exit 0
          ;;
      esac
    done
    exit 1
    ;;
  *) printf '%s\n%s\n' "$PICKER_KEY" "$selection" ;;
esac
STUB
  chmod +x "$TEST_REPO/bin/"*
  export PATH="$TEST_REPO/bin:$PATH"
  git config gtr.editor.default stub
  git config gtr.ai.default stub
  git config gtr.copy.include payload
  printf payload > "$TEST_REPO/payload"
}

teardown() {
  teardown_integration_repo
}

exercise_picker() {
  local shell_name="$1" selected="$2" other="$3" key expected_action actual_path
  command -v "$shell_name" >/dev/null || skip "$shell_name is not installed"
  cmd_init "$shell_name" > "$TEST_REPO/init.$shell_name"
  export PICKER_ID="path:$(_tsv_escape_field "$selected")"
  for key in ctrl-e ctrl-a ctrl-d ctrl-y; do
    export PICKER_KEY="$key"
    rm -f "$PICKER_LOG"
    run "$shell_name" -c 'source "$XDG_CACHE_HOME/../init.'"$shell_name"'"; gtr cd'
    [ "$status" -eq 0 ]
    if [ "$key" = ctrl-y ]; then
      [ "$(cat "$selected/payload")" = payload ]
      [ ! -f "$other/payload" ]
    else
      case "$key" in ctrl-e) expected_action=editor ;; ctrl-a) expected_action=ai ;; ctrl-d) expected_action=rm ;; esac
      { IFS= read -r -d '' actual_action; IFS= read -r -d '' actual_path; } < "$PICKER_LOG"
      [ "$actual_action" = "$expected_action" ]
      [ "$actual_path" = "$selected" ]
    fi
    [ ! -e "$TEST_REPO/picker-injected" ]
  done
  # Enter also resolves the identity, including paths containing line breaks.
  export PICKER_KEY=""
  "$shell_name" -c 'source "$XDG_CACHE_HOME/../init.'"$shell_name"'"; gtr cd; printf "%s\0" "$PWD" > "$PICKER_LOG"'
  IFS= read -r -d '' actual_path < "$PICKER_LOG"
  [ "$actual_path" = "$selected" ]
}

exercise_duplicate_and_detached() {
  local shell_name="$1" selected other
  other="$TEST_WORKTREES_DIR/shared"
  selected="$TEST_WORKTREES_DIR/selected ' \" \$(touch picker-injected) \`touch picker-injected\` \\ tab"$'\t'"line"$'\n'"end"$'\n'"  "
  git worktree add --quiet "$other" -b shared
  git worktree add --quiet --force "$selected" shared
  exercise_picker "$shell_name" "$selected" "$other"
  git -C "$selected" checkout --detach --quiet
  git -C "$other" checkout --detach --quiet
  rm "$selected/payload"
  exercise_picker "$shell_name" "$selected" "$other"
}

@test "Bash picker actions select only the chosen duplicate or detached worktree" {
  exercise_duplicate_and_detached bash
}

@test "Zsh picker actions select only the chosen duplicate or detached worktree" {
  exercise_duplicate_and_detached zsh
}

@test "Fish picker actions select only the chosen duplicate or detached worktree" {
  exercise_duplicate_and_detached fish
}

@test "path identities preserve main removal protection and reject unregistered targets" {
  local id cmd
  for id in "path:$TEST_REPO" "path:$TEST_REPO/stray" "path:$TEST_REPO/../$(basename "$TEST_REPO")"; do
    mkdir -p "$TEST_REPO/stray"
    run git gtr rm "$id"
    [ "$status" -ne 0 ]
    [ ! -f "$PICKER_LOG" ]
  done
  for cmd in editor ai copy; do
    run git gtr "$cmd" "path:$TEST_REPO/stray"
    # copy retains its existing best-effort exit behavior, but cannot touch stray.
    if [ "$cmd" != copy ]; then [ "$status" -ne 0 ]; fi
    [ ! -f "$PICKER_LOG" ]
    [ ! -f "$TEST_REPO/stray/payload" ]
  done
}

@test "removing one registered identity leaves its duplicate branch worktree intact" {
  create_test_worktree shared
  local selected="$TEST_WORKTREES_DIR/second"
  git worktree add --quiet --force "$selected" shared
  run cmd_remove "path:$selected"
  [ "$status" -eq 0 ]
  [ ! -d "$selected" ]
  [ -d "$TEST_WT_PATH" ]
  git show-ref --verify --quiet refs/heads/shared
}
