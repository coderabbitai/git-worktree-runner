#!/usr/bin/env bats
# Whole-record postCd hooks in the generated shells, using disposable repositories.

load test_helper

setup() {
  HOOK_FIXTURE=$(cd -P "$(mktemp -d)" && pwd)
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL="$HOOK_FIXTURE/global.gitconfig"
  export XDG_CONFIG_HOME="$HOOK_FIXTURE/config" XDG_CACHE_HOME="$HOOK_FIXTURE/cache"
  export XDG_DATA_HOME="$HOOK_FIXTURE/data"
  export PATH="$PROJECT_ROOT/bin:$PATH"
  export REPO_FIXTURE="$HOOK_FIXTURE/repo with spaces"
  export WT_FIXTURE="$HOOK_FIXTURE/worktree with spaces"
  export INIT_FIXTURE="$HOOK_FIXTURE/init"
  : > "$GIT_CONFIG_GLOBAL"
  git init --quiet "$REPO_FIXTURE"
  git -C "$REPO_FIXTURE" -c user.name=Fixture -c user.email=fixture@example.test \
    commit --allow-empty --quiet -m init
  git -C "$REPO_FIXTURE" worktree add --quiet -b feature "$WT_FIXTURE"
  source "$PROJECT_ROOT/lib/commands/init.sh"
  source "$PROJECT_ROOT/lib/hooks.sh"
}

teardown() {
  rm -rf "$HOOK_FIXTURE"
}

require_hook_shell() {
  command -v "$1" >/dev/null 2>&1 || skip "$1 is not installed"
}

add_hook() {
  if [ "$1" = git ]; then
    git -C "$REPO_FIXTURE" config --add gtr.hook.postCd "$2"
  else
    git config -f "$REPO_FIXTURE/.gtrconfig" --add hooks.postCd "$2"
  fi
}

configure_multiline_hooks() {
  local shell_name="$1" config_source template
  for config_source in git file; do
    if [ "$shell_name" = fish ]; then
      IFS= read -r -d '' template <<'HOOK' || true
if false
  echo escaped >> "$WORKTREE_PATH/__SOURCE__-escaped"
end
HOOK
      add_hook "$config_source" "${template//__SOURCE__/$config_source}"
      IFS= read -r -d '' template <<'HOOK' || true
for item in first second
  echo "$item" >> "$WORKTREE_PATH/__SOURCE__-loop"
end
function gtr_record___SOURCE__
  echo __SOURCE__ >> "$WT_FIXTURE/functions"
end
gtr_record___SOURCE__
set -gx GTR___SOURCE___ENV '__SOURCE__ value'
HOOK
    else
      IFS= read -r -d '' template <<'HOOK' || true
if false; then
  echo escaped >> "$WORKTREE_PATH/__SOURCE__-escaped"
fi
HOOK
      add_hook "$config_source" "${template//__SOURCE__/$config_source}"
      IFS= read -r -d '' template <<'HOOK' || true
for item in first second; do
  echo "$item" >> "$WORKTREE_PATH/__SOURCE__-loop"
done
gtr_record___SOURCE__() {
  echo __SOURCE__ >> "$WT_FIXTURE/functions"
}
gtr_record___SOURCE__
export GTR___SOURCE___ENV='__SOURCE__ value'
cat <<'END_HOOK' > "$WORKTREE_PATH/__SOURCE__-heredoc"
literal $HOME and `commands` and \
same
same
END_HOOK
HOOK
    fi
    add_hook "$config_source" "${template//__SOURCE__/$config_source}"
    template='echo repeat >> "$WORKTREE_PATH/__SOURCE__-repeat"'
    template="${template//__SOURCE__/$config_source}"
    # Repeated body lines are not duplicate records. Nor is a one-line hook
    # identical to the two-line hook that contains it.
    add_hook "$config_source" "$template"$'\n'"$template"
    add_hook "$config_source" "$template"
    add_hook "$config_source" "echo $config_source >> \"\$WORKTREE_PATH/order\""
    add_hook "$config_source" ''
  done
  template='echo shared >> "$WORKTREE_PATH/shared"'$'\n''echo shared >> "$WORKTREE_PATH/shared"'
  add_hook git "$template"
  add_hook git "$template"
  add_hook file "$template"
  # Trailing newlines are part of the value, so these are distinct records.
  template='echo trailing >> "$WORKTREE_PATH/trailing"'
  add_hook git "$template"
  add_hook file "$template"$'\n\n'
  _hooks_mark_trusted "$REPO_FIXTURE/.gtrconfig"
}

check_multiline_hooks() {
  local shell_name="$1" config_source
  configure_multiline_hooks "$shell_name"
  cmd_init "$shell_name" > "$INIT_FIXTURE"
  if [ "$shell_name" = fish ]; then
    run fish -c '
      source "$INIT_FIXTURE"
      cd "$REPO_FIXTURE"
      gtr cd feature; or exit 1
      test "$PWD" = "$WT_FIXTURE"; or exit 1
      test "$GTR_git_ENV" = "git value"; or exit 1
      test "$GTR_file_ENV" = "file value"; or exit 1
      gtr_record_git; or exit 1
      gtr_record_file; or exit 1
      command sh -c '\''test "$GTR_git_ENV" = "git value" && test "$GTR_file_ENV" = "file value"'\''
    '
  else
    run "$shell_name" -c '
      set -eu
      compdef() { :; }
      source "$INIT_FIXTURE"
      cd "$REPO_FIXTURE"
      gtr cd feature
      [ "$PWD" = "$WT_FIXTURE" ]
      [ "$GTR_git_ENV" = "git value" ]
      [ "$GTR_file_ENV" = "file value" ]
      gtr_record_git
      gtr_record_file
      command sh -c '\''test "$GTR_git_ENV" = "git value" && test "$GTR_file_ENV" = "file value"'\''
    '
  fi
  [ "$status" -eq 0 ]
  [[ "$output" != *'postCd hook failed'* ]]
  [ "$(cat "$WT_FIXTURE/order")" = $'git\nfile' ]
  [ "$(cat "$WT_FIXTURE/functions")" = $'git\nfile\ngit\nfile' ]
  [ "$(cat "$WT_FIXTURE/shared")" = $'shared\nshared' ]
  [ "$(cat "$WT_FIXTURE/trailing")" = $'trailing\ntrailing' ]
  for config_source in git file; do
    [ ! -e "$WT_FIXTURE/$config_source-escaped" ]
    [ "$(cat "$WT_FIXTURE/$config_source-loop")" = $'first\nsecond' ]
    [ "$(cat "$WT_FIXTURE/$config_source-repeat")" = $'repeat\nrepeat\nrepeat' ]
    if [ "$shell_name" != fish ]; then
      [ "$(cat "$WT_FIXTURE/$config_source-heredoc")" = 'literal $HOME and `commands` and \'$'\nsame\nsame' ]
    fi
  done
}

@test "bash postCd preserves and deduplicates complete values from both sources" {
  check_multiline_hooks bash
}

@test "zsh postCd preserves and deduplicates complete values from both sources" {
  require_hook_shell zsh
  check_multiline_hooks zsh
}

@test "fish postCd preserves and deduplicates complete values from both sources" {
  require_hook_shell fish
  check_multiline_hooks fish
}

run_hook_runner() {
  local shell_name="$1" prelude='set -e; compdef() { :; };'
  [ "$shell_name" != fish ] || prelude=''
  run "$shell_name" -c "$prelude"'
    source "$INIT_FIXTURE"
    cd "$REPO_FIXTURE"
    gtr_run_post_cd_hooks "$TARGET_FIXTURE"
  '
}

check_hook_boundaries_and_failures() {
  local shell_name="$1" config_source
  export TARGET_FIXTURE="$WT_FIXTURE"
  cmd_init "$shell_name" > "$INIT_FIXTURE"
  # Missing hook keys must remain successful, including with errexit enabled.
  run_hook_runner "$shell_name"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  for config_source in git file; do
    add_hook "$config_source" "echo before-$config_source >> \"\$WORKTREE_PATH/order\""$'\nfalse'
    add_hook "$config_source" "echo after-$config_source >> \"\$WORKTREE_PATH/order\""
  done
  # An untrusted multiline file value must never be partially evaluated.
  run_hook_runner "$shell_name"
  [ "$status" -eq 0 ]
  [[ "$output" == *'Untrusted .gtrconfig hooks skipped'* ]]
  [ "$(cat "$WT_FIXTURE/order")" = $'before-git\nafter-git' ]
  rm "$WT_FIXTURE/order"
  _hooks_mark_trusted "$REPO_FIXTURE/.gtrconfig"
  # Destination failure must prevent every hook, even when both sources exist.
  TARGET_FIXTURE="$WT_FIXTURE/missing" run_hook_runner "$shell_name"
  [ "$status" -ne 0 ]
  [ ! -e "$WT_FIXTURE/order" ]
  [ ! -e "$REPO_FIXTURE/order" ]
  run_hook_runner "$shell_name"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'postCd hook failed:')" -eq 2 ]
  [ "$(cat "$WT_FIXTURE/order")" = $'before-git\nafter-git\nbefore-file\nafter-file' ]
}

@test "bash postCd retains trust, destination, and failure behavior for whole hooks" {
  check_hook_boundaries_and_failures bash
}

@test "zsh postCd retains trust, destination, and failure behavior for whole hooks" {
  require_hook_shell zsh
  check_hook_boundaries_and_failures zsh
}

@test "fish postCd retains trust, destination, and failure behavior for whole hooks" {
  require_hook_shell fish
  check_hook_boundaries_and_failures fish
}
