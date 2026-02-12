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
