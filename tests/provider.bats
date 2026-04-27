#!/usr/bin/env bats
# Tests for lib/provider.sh — hostname extraction and provider detection
load test_helper

setup() {
  source "$PROJECT_ROOT/lib/provider.sh"
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
  git remote remove upstream >/dev/null 2>&1 || true
  run git remote add upstream https://example.com/repo.git
  [ "$status" -eq 0 ]
  run git update-ref refs/remotes/upstream/main HEAD
  [ "$status" -eq 0 ]

  result=$(normalize_target_ref "upstream/main")
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

@test "check_branch_merged passes target branch and branch tip to glab" {
  glab() {
    [ "$1" = "mr" ] || return 1
    [ "$2" = "list" ] || return 1
    [ "$3" = "--source-branch" ] || return 1
    [ "$4" = "feature/test" ] || return 1
    [ "$5" = "--merged" ] || return 1
    [ "$6" = "--all" ] || return 1
    [ "$7" = "--output" ] || return 1
    [ "$8" = "json" ] || return 1
    [ "${9}" = "--target-branch" ] || return 1
    [ "${10}" = "main" ] || return 1
    printf '[{"iid":1,"sha":"abc123"}]'
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
    [ "$6" = "--all" ] || return 1
    [ "$7" = "--output" ] || return 1
    [ "$8" = "json" ] || return 1
    [ "${9}" = "--target-branch" ] || return 1
    [ "${10}" = "main" ] || return 1
    printf '[{"iid":1,"sha":"old123"}]'
  }

  run check_branch_merged gitlab feature/test main def456
  [ "$status" -eq 1 ]
}

@test "check_branch_merged accepts GitLab diff_refs head SHA matches" {
  glab() {
    [ "$1" = "mr" ] || return 1
    [ "$2" = "list" ] || return 1
    [ "$3" = "--source-branch" ] || return 1
    [ "$4" = "feature/test" ] || return 1
    [ "$5" = "--merged" ] || return 1
    [ "$6" = "--all" ] || return 1
    [ "$7" = "--output" ] || return 1
    [ "$8" = "json" ] || return 1
    [ "${9}" = "--target-branch" ] || return 1
    [ "${10}" = "main" ] || return 1
    printf '[{"iid":1,"diff_refs":{"head_sha":"abc123"}}]'
  }

  run check_branch_merged gitlab feature/test main abc123
  [ "$status" -eq 0 ]
}

@test "check_branch_merged still accepts GitLab merged MR without branch tip" {
  glab() {
    [ "$1" = "mr" ] || return 1
    [ "$2" = "list" ] || return 1
    [ "$3" = "--source-branch" ] || return 1
    [ "$4" = "feature/test" ] || return 1
    [ "$5" = "--merged" ] || return 1
    [ "$6" = "--all" ] || return 1
    [ "$7" = "--output" ] || return 1
    [ "$8" = "json" ] || return 1
    [ "${9}" = "--target-branch" ] || return 1
    [ "${10}" = "main" ] || return 1
    printf '[{"iid":1}]'
  }

  run check_branch_merged gitlab feature/test main
  [ "$status" -eq 0 ]
}
