#!/usr/bin/env bats

load test_helper

setup() {
  setup_integration_repo
  git branch -M main
  source_gtr_commands
  export XDG_CONFIG_HOME="$TEST_REPO/xdg"
}

teardown() {
  teardown_integration_repo
}

preview() {
  "$PROJECT_ROOT/bin/gtr" rm "$@"
}

@test "rm preview preserves files refs registry index and trust without executing hooks" {
  create_test_worktree topic
  git config gtr.hook.preRemove "touch '$TEST_REPO/pre-ran'"
  git config gtr.hook.postRemove "touch '$TEST_REPO/post-ran'"
  printf '[hooks]\n preRemove = touch team-pre\n postRemove = touch team-post\n' > "$TEST_REPO/.gtrconfig"
  cp "$TEST_REPO/.gtrconfig" "$TEST_WT_PATH/.gtrconfig"
  mkdir -p "$XDG_CONFIG_HOME/gtr/trusted"
  echo marker > "$XDG_CONFIG_HOME/gtr/trusted/existing"
  echo keep > "$TEST_WT_PATH/untracked"
  echo original > "$TEST_WT_PATH/tracked"
  git -C "$TEST_WT_PATH" add tracked
  git -C "$TEST_WT_PATH" commit -qm tracked
  # Make cached stat data stale without changing content before hashing the index.
  touch -t 200001010000 "$TEST_WT_PATH/tracked"
  local before_refs before_registry before_index
  before_refs=$(git show-ref)
  before_registry=$(git worktree list --porcelain)
  before_index=$(git hash-object "$TEST_REPO/.git/worktrees/topic/index")
  run preview topic -n --force --delete-branch --yes
  [ "$status" -eq 0 ]
  [[ "$output" == *"$TEST_WT_PATH"* ]]
  [[ "$output" == *"Branch: topic"* ]]
  [ "$(git show-ref)" = "$before_refs" ]
  [ "$(git worktree list --porcelain)" = "$before_registry" ]
  [ "$(git hash-object "$TEST_REPO/.git/worktrees/topic/index")" = "$before_index" ]
  [ "$(cat "$TEST_WT_PATH/untracked")" = keep ]
  [ "$(cat "$XDG_CONFIG_HOME/gtr/trusted/existing")" = marker ]
  [ "$(find "$XDG_CONFIG_HOME" -type f | wc -l)" -eq 1 ]
  [ ! -e "$TEST_REPO/pre-ran" ]
  [ ! -e "$TEST_REPO/post-ran" ]
  [ ! -e "$TEST_WT_PATH/team-pre" ]
  [ ! -e "$TEST_REPO/team-post" ]
}

@test "rm preview does not create absent trust storage or invoke fsmonitor" {
  create_test_worktree topic
  printf '[hooks]\n preRemove = exit 1\n' > "$TEST_REPO/.gtrconfig"
  git config core.fsmonitor "touch '$TEST_REPO/fsmonitor-ran'"
  run preview topic --dry-run
  [ "$status" -eq 0 ]
  [ ! -e "$XDG_CONFIG_HOME" ]
  [ ! -e "$TEST_REPO/fsmonitor-ran" ]
}

@test "rm preview reports tracked and untracked changes and force risk" {
  create_test_worktree topic
  echo original > "$TEST_WT_PATH/tracked"
  git -C "$TEST_WT_PATH" add tracked
  git -C "$TEST_WT_PATH" commit -qm tracked
  echo modified > "$TEST_WT_PATH/tracked"
  echo keep > "$TEST_WT_PATH/untracked"
  run preview topic --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dirty (tracked): yes; untracked: yes; locked: no"* ]]
  [[ "$output" == *"Blocked without --force"* ]]
  [[ "$output" == *"discard uncommitted changes and untracked files"* ]]
  run preview topic -n --force
  [ "$status" -eq 0 ]
  [[ "$output" != *"Blocked without --force"* ]]
  [ "$(cat "$TEST_WT_PATH/tracked")" = modified ]
}

@test "rm preview does not count ignored files as blocking" {
  create_test_worktree topic
  echo ignored > "$TEST_REPO/.git/info/exclude"
  touch "$TEST_WT_PATH/ignored"
  run preview topic -n
  [ "$status" -eq 0 ]
  [[ "$output" == *"Dirty (tracked): no; untracked: no"* ]]
  [ -f "$TEST_WT_PATH/ignored" ]
}

@test "rm preview reports locked worktrees blocked even with force" {
  create_test_worktree topic
  git worktree lock "$TEST_WT_PATH"
  run preview topic -n --force
  [ "$status" -eq 0 ]
  [[ "$output" == *"locked: yes"* ]]
  [[ "$output" == *"single --force cannot remove"* ]]
  git worktree list --porcelain | grep '^locked'
  git worktree unlock "$TEST_WT_PATH"
}

@test "rm preview uses verified local default branch when no remote ref exists" {
  create_test_worktree topic
  git -C "$TEST_WT_PATH" commit --allow-empty -qm extra
  run preview topic -n --delete-branch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Commits not reachable from refs/heads/main: 1"* ]]
}

@test "rm preview prefers configured remote and branch over local branch" {
  create_test_worktree topic
  git -C "$TEST_WT_PATH" commit --allow-empty -qm extra
  git branch release main
  git update-ref refs/remotes/upstream/release topic
  git config gtr.defaultRemote upstream
  git config gtr.defaultBranch release
  run preview topic -n --delete-branch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Commits not reachable from refs/remotes/upstream/release: 0"* ]]
}

@test "rm preview follows selected remote HEAD default branch" {
  create_test_worktree topic
  git update-ref refs/remotes/upstream/develop main
  git symbolic-ref refs/remotes/upstream/HEAD refs/remotes/upstream/develop
  git config gtr.defaultRemote upstream
  run preview topic -n --delete-branch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Commits not reachable from refs/remotes/upstream/develop: 0"* ]]
}

@test "rm preview falls back from a missing remote tip to selected local branch" {
  create_test_worktree topic
  git branch release main
  git config gtr.defaultBranch release
  run preview topic -n --delete-branch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Commits not reachable from refs/heads/release: 0"* ]]
}

@test "rm preview reports unknown for missing base and does not accept a same-name tag" {
  create_test_worktree topic
  git config gtr.defaultBranch absent
  git tag absent
  run preview topic -n --delete-branch
  [ "$status" -eq 0 ]
  [[ "$output" == *"base: unknown"* ]]
  [[ "$output" != *"refs/heads/main:"* ]]
}

@test "rm preview warns on reachability after squash merge without merge verdict" {
  create_test_worktree topic
  echo change > "$TEST_WT_PATH/file"
  git -C "$TEST_WT_PATH" add file
  git -C "$TEST_WT_PATH" commit -qm feature
  git merge --squash topic
  git commit -qm squash
  run preview topic -n --delete-branch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Commits not reachable from refs/heads/main: 1"* ]]
  [[ "$output" == *"not a merged/unmerged judgment; squash/rebase can mislead"* ]]
}

@test "rm preview handles detached HEAD without proposing branch deletion" {
  git worktree add --detach "$TEST_WORKTREES_DIR/detached" HEAD
  run preview detached -n --delete-branch
  [ "$status" -eq 0 ]
  [[ "$output" == *"Branch: detached HEAD"* ]]
  [[ "$output" == *"Branch deletion: none (detached HEAD)"* ]]
  [ -d "$TEST_WORKTREES_DIR/detached" ]
}

@test "rm preview reports valid targets on either side of invalid targets" {
  create_test_worktree first
  create_test_worktree last
  run env PATH="$PROJECT_ROOT/bin:$PATH" git gtr rm first nonexistent 1 last -n
  [ "$status" -ne 0 ]
  [[ "$output" == *"Branch: first"* ]]
  [[ "$output" == *"Cannot remove main repository"* ]]
  [[ "$output" == *"Branch: last"* ]]
  [ -d "$TEST_WORKTREES_DIR/first" ]
  [ -d "$TEST_WORKTREES_DIR/last" ]
}

@test "rm preview fails for missing registered directory and continues" {
  create_test_worktree missing
  rm -rf "$TEST_WT_PATH"
  create_test_worktree topic
  run preview missing topic -n
  [ "$status" -ne 0 ]
  [[ "$output" == *"Branch: topic"* ]]
  [ -d "$TEST_WT_PATH" ]
}

@test "rm preview reports untracked files even when Git status hides them" {
  create_test_worktree topic
  git config status.showUntrackedFiles no
  echo keep > "$TEST_WT_PATH/untracked"
  run preview topic -n
  [ "$status" -eq 0 ]
  [[ "$output" == *"untracked: yes"* ]]
  [[ "$output" == *"depending on Git status settings"* ]]
  [[ "$output" != *"Blocked without --force"* ]]
  [ "$(cat "$TEST_WT_PATH/untracked")" = keep ]
}
