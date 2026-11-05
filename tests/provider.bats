#!/usr/bin/env bats
# Tests for lib/provider.sh — hostname extraction and provider detection
load test_helper

setup() {
  source "$PROJECT_ROOT/lib/provider.sh"
}

# Check each response through both parsing paths. The glab stub deliberately
# ignores the requested filter: only the returned MR state can authorize cleanup.
assert_gitlab_state() {
  local expected_status="$1" state="$2" tip="${3-abc123}"
  glab() { printf '%s\n' "$mr_json"; return "${glab_status:-0}"; }

  if command -v jq >/dev/null 2>&1; then
    run check_branch_pr_state gitlab feature/test "$state" main "$tip"
    [ "$status" -eq "$expected_status" ] || return 1
  fi
  run without_jq check_branch_pr_state gitlab feature/test "$state" main "$tip"
  [ "$status" -eq "$expected_status" ]
}

# ── extract_hostname ─────────────────────────────────────────────────────────

@test "extract_hostname from SSH shorthand" {
  result=$(extract_hostname "git@github.com:user/repo.git")
  [ "$result" = "github.com" ]
}

@test "extract_hostname from HTTPS URL" {
  result=$(extract_hostname "https://github.com/user/repo.git")
  [ "$result" = "github.com" ]
}

@test "extract_hostname from SSH scheme URL" {
  result=$(extract_hostname "ssh://git@github.com/user/repo.git")
  [ "$result" = "github.com" ]
}

@test "extract_hostname from GitLab SSH shorthand" {
  result=$(extract_hostname "git@gitlab.com:group/repo.git")
  [ "$result" = "gitlab.com" ]
}

@test "extract_hostname from GitLab HTTPS" {
  result=$(extract_hostname "https://gitlab.com/group/subgroup/repo.git")
  [ "$result" = "gitlab.com" ]
}

@test "extract_hostname from self-hosted SSH" {
  result=$(extract_hostname "git@git.example.com:org/repo.git")
  [ "$result" = "git.example.com" ]
}

@test "extract_hostname from HTTPS with port" {
  result=$(extract_hostname "https://git.example.com:8443/org/repo.git")
  [ "$result" = "git.example.com" ]
}

@test "extract_hostname fails on bare path" {
  run extract_hostname "/local/path"
  [ "$status" -ne 0 ]
}

@test "extract_hostname fails on empty input" {
  run extract_hostname ""
  [ "$status" -ne 0 ]
}

@test "normalize_target_ref strips refs/heads prefix" {
  result=$(normalize_target_ref "refs/heads/main")
  [ "$result" = "main" ]
}

@test "normalize_target_ref strips refs/remotes prefix" {
  result=$(normalize_target_ref "refs/remotes/origin/release/1.0")
  [ "$result" = "release/1.0" ]
}

@test "normalize_target_ref strips remote prefix when remote ref exists" {
  local test_repo
  test_repo=$(mktemp -d)
  git -C "$test_repo" init --quiet
  git -C "$test_repo" config user.name "Test User"
  git -C "$test_repo" config user.email "test@example.com"
  git -C "$test_repo" commit --allow-empty -m init --quiet
  git -C "$test_repo" remote add upstream https://example.com/repo.git
  git -C "$test_repo" update-ref refs/remotes/upstream/main HEAD

  result=$(cd "$test_repo" && normalize_target_ref "upstream/main")
  rm -rf "$test_repo"
  [ "$result" = "main" ]
}

# ── check_branch_merged ───────────────────────────────────────────────────────

@test "check_branch_merged passes normalized base ref and limit to gh" {
  gh() {
    [ "$1" = "pr" ] || return 1
    [ "$2" = "list" ] || return 1
    [ "$3" = "--head" ] || return 1
    [ "$4" = "feature/test" ] || return 1
    [ "$5" = "--state" ] || return 1
    [ "$6" = "merged" ] || return 1
    [ "$7" = "--limit" ] || return 1
    [ "$8" = "1000" ] || return 1
    [ "$9" = "--base" ] || return 1
    [ "${10}" = "main" ] || return 1
    [ "${11}" = "--json" ] || return 1
    [ "${12}" = "state,headRefOid" ] || return 1
    [ "${13}" = "--jq" ] || return 1
    [[ "${14}" == *'.headRefOid == "abc123"'* ]] || return 1
    printf "1"
  }

  run check_branch_merged github feature/test refs/heads/main abc123
  [ "$status" -eq 0 ]
}

@test "check_branch_merged rejects reused GitHub branch names with different HEAD" {
  gh() {
    printf "0"
  }

  run check_branch_merged github feature/test main def456
  [ "$status" -eq 1 ]
}

@test "check_branch_closed passes closed state and branch tip to gh" {
  gh() {
    [ "$1" = "pr" ] || return 1
    [ "$2" = "list" ] || return 1
    [ "$3" = "--head" ] || return 1
    [ "$4" = "feature/test" ] || return 1
    [ "$5" = "--state" ] || return 1
    [ "$6" = "closed" ] || return 1
    [ "$7" = "--limit" ] || return 1
    [ "$8" = "1000" ] || return 1
    [ "$9" = "--base" ] || return 1
    [ "${10}" = "main" ] || return 1
    [ "${11}" = "--json" ] || return 1
    [ "${12}" = "state,headRefOid" ] || return 1
    [ "${13}" = "--jq" ] || return 1
    [[ "${14}" == *'.state == "CLOSED"'* ]] || return 1
    [[ "${14}" == *'.headRefOid == "abc123"'* ]] || return 1
    printf "1"
  }

  run check_branch_closed github feature/test main abc123
  [ "$status" -eq 0 ]
}

@test "check_branch_merged passes target branch and branch tip to glab" {
  glab() {
    [ "$1" = "mr" ] || return 1
    [ "$2" = "list" ] || return 1
    [ "$3" = "--source-branch" ] || return 1
    [ "$4" = "feature/test" ] || return 1
    [ "$5" = "--merged" ] || return 1
    [ "$6" = "--output" ] || return 1
    [ "$7" = "json" ] || return 1
    [ "$8" = "--target-branch" ] || return 1
    [ "$9" = "main" ] || return 1
    [ "$#" -eq 9 ] || return 1
    printf '[{"iid":1,"state":"merged","sha":"abc123"}]'
  }

  run check_branch_merged gitlab feature/test origin/main abc123
  [ "$status" -eq 0 ]
}

@test "check_branch_merged rejects reused GitLab branch names with different HEAD" {
  glab() {
    [ "$1" = "mr" ] || return 1
    [ "$2" = "list" ] || return 1
    [ "$3" = "--source-branch" ] || return 1
    [ "$4" = "feature/test" ] || return 1
    [ "$5" = "--merged" ] || return 1
    [ "$6" = "--output" ] || return 1
    [ "$7" = "json" ] || return 1
    [ "$8" = "--target-branch" ] || return 1
    [ "$9" = "main" ] || return 1
    [ "$#" -eq 9 ] || return 1
    printf '[{"iid":1,"state":"merged","sha":"old123"}]'
  }

  run check_branch_merged gitlab feature/test main def456
  [ "$status" -eq 1 ]
}

@test "check_branch_closed passes target branch and branch tip to glab" {
  glab() {
    [ "$1" = "mr" ] || return 1
    [ "$2" = "list" ] || return 1
    [ "$3" = "--source-branch" ] || return 1
    [ "$4" = "feature/test" ] || return 1
    [ "$5" = "--closed" ] || return 1
    [ "$6" = "--output" ] || return 1
    [ "$7" = "json" ] || return 1
    [ "$8" = "--target-branch" ] || return 1
    [ "$9" = "main" ] || return 1
    [ "$#" -eq 9 ] || return 1
    printf '[{"iid":1,"state":"closed","sha":"abc123"}]'
  }

  run check_branch_closed gitlab feature/test main abc123
  [ "$status" -eq 0 ]
}

@test "check_branch_merged accepts GitLab top-level head SHA without jq" {
  local mock_bin old_path
  mock_bin=$(mktemp -d)
  ln -s "$(command -v sed)" "$mock_bin/sed"
  ln -s "$(command -v tr)" "$mock_bin/tr"
  ln -s "$(command -v awk)" "$mock_bin/awk"
  old_path="$PATH"
  PATH="$mock_bin"

  glab() {
    [ "$1" = "mr" ] || return 1
    [ "$2" = "list" ] || return 1
    [ "$3" = "--source-branch" ] || return 1
    [ "$4" = "feature/test" ] || return 1
    [ "$5" = "--merged" ] || return 1
    [ "$6" = "--output" ] || return 1
    [ "$7" = "json" ] || return 1
    [ "$8" = "--target-branch" ] || return 1
    [ "$9" = "main" ] || return 1
    [ "$#" -eq 9 ] || return 1
    printf '[{"iid":1,"state":"merged","head_sha":"abc123"}]'
  }

  run check_branch_merged gitlab feature/test main abc123
  PATH="$old_path"
  rm -rf "$mock_bin"
  [ "$status" -eq 0 ]
}

@test "check_branch_merged accepts GitLab diff_refs head SHA matches" {
  glab() {
    [ "$1" = "mr" ] || return 1
    [ "$2" = "list" ] || return 1
    [ "$3" = "--source-branch" ] || return 1
    [ "$4" = "feature/test" ] || return 1
    [ "$5" = "--merged" ] || return 1
    [ "$6" = "--output" ] || return 1
    [ "$7" = "json" ] || return 1
    [ "$8" = "--target-branch" ] || return 1
    [ "$9" = "main" ] || return 1
    [ "$#" -eq 9 ] || return 1
    printf '[{"iid":1,"state":"merged","diff_refs":{"head_sha":"abc123"}}]'
  }

  run check_branch_merged gitlab feature/test main abc123
  [ "$status" -eq 0 ]
}

@test "check_branch_merged ignores unrelated GitLab nested head SHA fields" {
  command -v jq >/dev/null 2>&1 || skip "jq is required for structural GitLab JSON validation"

  glab() {
    [ "$1" = "mr" ] || return 1
    [ "$2" = "list" ] || return 1
    [ "$3" = "--source-branch" ] || return 1
    [ "$4" = "feature/test" ] || return 1
    [ "$5" = "--merged" ] || return 1
    [ "$6" = "--output" ] || return 1
    [ "$7" = "json" ] || return 1
    [ "$8" = "--target-branch" ] || return 1
    [ "$9" = "main" ] || return 1
    [ "$#" -eq 9 ] || return 1
    printf '[{"iid":1,"state":"merged","sha":"old123","metadata":{"head_sha":"abc123"}}]'
  }

  run check_branch_merged gitlab feature/test main abc123
  [ "$status" -eq 1 ]
}

@test "check_branch_merged still accepts GitLab merged MR without branch tip" {
  glab() {
    [ "$1" = "mr" ] || return 1
    [ "$2" = "list" ] || return 1
    [ "$3" = "--source-branch" ] || return 1
    [ "$4" = "feature/test" ] || return 1
    [ "$5" = "--merged" ] || return 1
    [ "$6" = "--output" ] || return 1
    [ "$7" = "json" ] || return 1
    [ "$8" = "--target-branch" ] || return 1
    [ "$9" = "main" ] || return 1
    [ "$#" -eq 9 ] || return 1
    printf '[{"iid":1,"state":"merged"}]'
  }

  run check_branch_merged gitlab feature/test main
  [ "$status" -eq 0 ]
}

@test "GitLab open MR at current tip never matches merged or closed cleanup" {
  local mr_json='[{"state":"opened","sha":"abc123"}]' state
  for state in merged closed; do
    assert_gitlab_state 1 "$state"
    assert_gitlab_state 1 "$state" ""
  done
}

@test "GitLab state and all supported tip fields match on the same MR" {
  local mr_json state tip_field
  for state in merged closed; do
    for tip_field in '"sha":"abc123"' '"head_sha":"abc123"' '"diff_refs":{"head_sha":"abc123"}'; do
      mr_json="[{\"state\":\"$state\",$tip_field}]"
      assert_gitlab_state 0 "$state"
      assert_gitlab_state 1 "$state" def456
    done
    assert_gitlab_state 0 "$state" ""
  done
}

@test "GitLab merged and closed states are not interchangeable" {
  local mr_json='[{"state":"merged","sha":"abc123"}]'
  assert_gitlab_state 1 closed
  mr_json='[{"state":"closed","sha":"abc123"}]'
  assert_gitlab_state 1 merged
}

@test "GitLab mixed states cannot borrow the current tip from an open MR" {
  local mr_json state
  for state in merged closed; do
    mr_json="[{\"state\":\"$state\",\"sha\":\"old123\"},{\"state\":\"opened\",\"sha\":\"abc123\"}]"
    assert_gitlab_state 1 "$state"
    mr_json="[{\"state\":\"opened\",\"sha\":\"abc123\"},{\"state\":\"$state\",\"diff_refs\":{\"head_sha\":\"old123\"}}]"
    assert_gitlab_state 1 "$state"
    mr_json="[{\"state\":\"opened\",\"sha\":\"old123\"},{\"state\":\"$state\",\"sha\":\"abc123\"}]"
    assert_gitlab_state 0 "$state"
  done
}

@test "GitLab requires an explicit top-level state even without a tip" {
  local mr_json state
  for state in merged closed; do
    for mr_json in \
      '[{"sha":"abc123"}]' \
      '[{"state":null,"sha":"abc123"}]' \
      '[{"state":"unknown","sha":"abc123"}]' \
      '[{"metadata":{"state":"merged"},"sha":"abc123"}]' \
      '[{"metadata":{"state":"closed"},"sha":"abc123"}]' \
      '{"record":{"state":"merged","sha":"abc123"}}' \
      '[]' 'null' 'not JSON'; do
      assert_gitlab_state 1 "$state"
      assert_gitlab_state 1 "$state" ""
    done
  done
}

@test "GitLab nested records and quoted object delimiters cannot supply MR state" {
  local mr_json='[
    {"state":"opened","sha":"abc123","reviewers":[
      {"id":1},{"state":"merged","sha":"abc123"}
    ],"title":"text },{ \"state\":\"closed\",\"sha\":\"abc123\""}
  ]'
  assert_gitlab_state 1 merged
  assert_gitlab_state 1 closed
}

@test "GitLab finds MR state after nested fields and preserves spaces in state values" {
  local mr_json='[
    {"sha":"abc123", "author":{"state":"active"}, "labels":["a", "b"], "state":"merged"}
  ]'
  assert_gitlab_state 0 merged
  mr_json='[{"state":"mer ged","sha":"abc123"}]'
  assert_gitlab_state 1 merged
}

@test "GitLab ambiguous duplicate state fields cannot authorize cleanup" {
  local mr_json='[{"state":"merged","state":"opened","sha":"abc123"}]'
  assert_gitlab_state 1 merged
  mr_json='[{"state":"merged","st\u0061te":"opened","sha":"abc123"}]'
  assert_gitlab_state 1 merged
}

@test "GitLab incomplete responses and CLI errors cannot authorize cleanup" {
  local mr_json='[{"state":"merged","sha":"abc123"}'
  assert_gitlab_state 1 merged
  mr_json='[{"state":"merged","sha":"abc123"}]'
  local glab_status=1
  assert_gitlab_state 1 merged
}
