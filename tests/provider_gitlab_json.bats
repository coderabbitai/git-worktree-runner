#!/usr/bin/env bats
# Structural SHA matching must also work with only the supported shell tools.
load test_helper

setup() {
  source "$PROJECT_ROOT/lib/provider.sh"
  TEST_REPO=""
  NO_JQ_BIN="$BATS_TEST_TMPDIR/no-jq"
  mkdir -p "$NO_JQ_BIN"
  ln -s "$(command -v awk)" "$NO_JQ_BIN/awk"
}

teardown() {
  if [ -n "${TEST_REPO:-}" ]; then teardown_integration_repo; fi
}

without_jq() (
  PATH="$NO_JQ_BIN"
  ! command -v jq >/dev/null 2>&1 || return 99
  "$@"
)

assert_match() {
  local expected="$1" json="$2" tip="${3:-abc123}"
  run without_jq _gitlab_mr_matches_tip "$json" "$tip"
  [ "$output" = "" ]
  [ "$status" -eq "$expected" ]

  # Exercise the production jq path with the identical JSON when installed.
  if command -v jq >/dev/null 2>&1; then
    run _gitlab_mr_matches_tip "$json" "$tip"
    [ "$output" = "" ]
    [ "$status" -eq "$expected" ] || {
      printf 'jq status %s (expected %s): %s\n' "$status" "$expected" "$json" >&2
      return 1
    }
  fi
}

@test "GitLab SHA matching finds top-level fields after nested objects and arrays" {
  assert_match 0 '[{"author":{"id":1},"sha":"abc123"}]'
  assert_match 0 '[{"labels":[{"name":"one"},{"name":"two"}],"head_sha":"abc123"}]'
  assert_match 0 '[{"metadata":{"nested":[[{}],{"sha":"old"}]},"sha":"abc123"}]'
}

@test "GitLab SHA matching ignores unrelated nested SHA and diff_refs fields" {
  local json
  while IFS= read -r json; do
    assert_match 1 "$json"
  done <<'JSON'
[{"metadata":{"sha":"abc123","head_sha":"abc123"}}]
[{"metadata":{"diff_refs":{"head_sha":"abc123"}}}]
[{"items":[{}, {"sha":"abc123"}]}]
[{"items":[{}, {"head_sha":"abc123"}]}]
[{"items":[{}, {"diff_refs":{"head_sha":"abc123"}}]}]
[{"diff_refs":{"metadata":{"head_sha":"abc123"}}}]
[{"sha":{"head_sha":"abc123"}}]
[{"head_sha":["abc123"]}]
JSON
}

@test "GitLab SHA matching respects diff_refs scope regardless of field order" {
  assert_match 0 '[{"diff_refs":{"metadata":{"head_sha":"old"},"head_sha":"abc123"}}]'
  assert_match 0 '[{"diff_refs":{"head_sha":"abc123"},"metadata":{"diff_refs":{"head_sha":"old"}}}]'
  assert_match 1 '[{"diff_refs":{"head_sha":"old"},"metadata":{"diff_refs":{"head_sha":"abc123"}}}]'
  assert_match 0 '[{"sha":"old","head_sha":"abc123","diff_refs":{"head_sha":"old"}}]'
}

@test "GitLab SHA matching checks all MR records independently" {
  assert_match 0 '[{"sha":"old"},{"author":{"id":1},"sha":"abc123"},{"sha":"older"}]'
  assert_match 0 '[{"sha":"abc123"},{"diff_refs":{"head_sha":"old"}}]'
  assert_match 1 '[{"sha":"old"},{"metadata":{"diff_refs":{"head_sha":"abc123"}}}]'
  assert_match 1 '[]'
}

@test "GitLab SHA matching compares full commit IDs exactly without numeric coercion" {
  local tip=0123456789012345678901234567890123456789
  assert_match 0 "[{\"sha\":\"$tip\"}]" "$tip"
  assert_match 1 '[{"sha":"0123456789012345678901234567890123456788"}]' "$tip"
  tip=0123456789012345678901234567890123456789012345678901234567890123
  assert_match 0 "[{\"diff_refs\":{\"head_sha\":\"$tip\"}}]" "$tip"
  assert_match 1 "[{\"head_sha\":\"${tip%3}2\"}]" "$tip"
}

@test "GitLab SHA matching ignores quoted delimiters and escaped JSON fragments" {
  assert_match 1 '[{"title":"},{\"sha\":\"abc123\"},{"}]'
  assert_match 1 '[{"title":"\"diff_refs\":{\"head_sha\":\"abc123\"}"}]'
  assert_match 0 '[{"title":"[{}],:\"\\\/\b\f\n\r\t","sha":"abc123"}]'
  assert_match 0 '[{"title":"ends in a backslash\\","sha":"abc123"}]'
}

@test "GitLab SHA matching preserves whitespace inside strings" {
  assert_match 1 '[{"sha":"abc 123"}]'
  assert_match 1 '[{"head_sha":" abc123"}]'
  assert_match 1 '[{"diff_refs":{"head_sha":"abc123 "}}]'
  assert_match 1 '[{"sha":"abc\n123"}]'
  assert_match 1 '[{"head_sha":"abc\t123"}]'
  assert_match 1 '[{"s ha":"abc123"}]'
  assert_match 0 $' [\n { "author" : { },\r\n "sha" : "abc123" }\n ]\t'
}

@test "GitLab SHA matching decodes escaped keys and SHA values" {
  assert_match 0 '[{"\u0073ha":"\u0061bc123"}]'
  assert_match 0 '[{"head\u005fsha":"abc\u003123"}]'
  assert_match 0 '[{"diff\u005frefs":{"head_\u0073ha":"abc123"}}]'
  assert_match 1 '[{"\u0073ha":"abc\u0020123"}]'
  assert_match 1 '[{"sha":"\u0000abc123"}]'
}

@test "GitLab SHA matching validates unrelated JSON values without interpreting them as SHAs" {
  assert_match 0 '[{"data":[true,false,null,0,-0,1.5,-2.5e+10,1E-3,{},[]],"sha":"abc123"}]'
  assert_match 0 '[{"title":"caf\u00e9 ☕ \ud83d\ude00 \u0000","sha":"abc123"}]'
  assert_match 1 '[{"sha":null,"head_sha":false,"diff_refs":null}]'
  assert_match 1 '[{"sha":123,"head_sha":{},"diff_refs":{"head_sha":["abc123"]}}]'
}

@test "GitLab SHA matching rejects malformed data even after a matching record" {
  local json
  while IFS= read -r json; do
    assert_match 1 "$json"
  done <<'JSON'
[{"sha":"abc123"}
garbage
[{"sha":"abc123"}] garbage
[{"sha":"abc123"}] []
[{"sha":"abc123"},]
[{"sha":"abc123",}]
[{"sha":"abc123" "id":1}]
[{"sha":"abc123"},{"id" 1}]
[{"sha":"abc123"},{"data":[1,]}]
[{"sha":"abc123"},{"data":tru}]
[{"sha":"abc123"},{"data":1e}]
[{"sha":"abc123"},{"data":"unterminated}]
[{"sha":"abc123"},{"data":"bad\q"}]
[{"sha":"abc123"},{"data":"bad\u123x"}]
JSON
  assert_match 1 $'[{"sha":"abc123","title":"raw\nnewline"}]'
  assert_match 1 $'[{"sha":"abc123","title":"raw\ttab"}]'
  assert_match 1 $'[{"sha":"abc123"}]\v'
}

@test "GitLab no-jq matching rejects non-JSON numbers accepted by some jq versions" {
  local number
  for number in 01 1. +1 NaN Infinity -Infinity; do
    run without_jq _gitlab_mr_matches_tip "[{\"sha\":\"abc123\",\"data\":$number}]" abc123
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
  done
}

@test "GitLab SHA matching requires exactly one array of MR objects and a nonempty tip" {
  assert_match 1 ''
  assert_match 1 'null'
  assert_match 1 '{}'
  assert_match 1 '{"record":{"sha":"abc123"}}'
  assert_match 1 '[[{"sha":"abc123"}]]'
  assert_match 1 '[{"sha":"abc123"},null]'
  assert_match 1 '[{"sha":"abc123"},1]'
  assert_match 1 '[{"sha":"abc123"},"record"]'
  run without_jq _gitlab_mr_matches_tip '[{}]' ''
  [ "$status" -eq 1 ]
}

@test "GitLab no-jq matching rejects ambiguous duplicate keys" {
  local json
  while IFS= read -r json; do
    # jq normally keeps the last duplicate; the fallback conservatively rejects
    # these ambiguous records instead of authorizing deletion using either one.
    run without_jq _gitlab_mr_matches_tip "$json" abc123
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
  done <<'JSON'
[{"sha":"abc123","sha":"old"}]
[{"sha":"old","sha":"abc123"}]
[{"head_sha":"abc123","head_sha":"old"}]
[{"diff_refs":{"head_sha":"abc123","head_sha":"old"}}]
[{"diff_refs":{"head_sha":"abc123"},"diff_refs":{"head_sha":"old"}}]
[{"sha":"abc123","\u0073ha":"old"}]
[{"metadata":{"café":1,"caf\u00e9":2},"sha":"abc123"}]
JSON
}

@test "GitLab no-jq matching rejects invalid Unicode surrogate escapes" {
  local json
  while IFS= read -r json; do
    run without_jq _gitlab_mr_matches_tip "$json" abc123
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
  done <<'JSON'
[{"sha":"abc123","title":"\ud800"}]
[{"sha":"abc123","title":"\udc00"}]
[{"sha":"abc123","title":"\ud800\u0000"}]
JSON
}

@test "GitLab no-jq matching rejects invalid UTF-8" {
  local invalid
  for invalid in $'\200' $'\300\241' $'\342\202' $'\355\240\200' $'\364\220\200\200'; do
    run without_jq _gitlab_mr_matches_tip "[{\"sha\":\"abc123\",\"title\":\"$invalid\"}]" abc123
    [ "$status" -eq 1 ]
    [ "$output" = "" ]
  done
}

@test "GitLab no-jq matching fails closed on excessive nesting" {
  local json='[{"sha":"abc123","data":' i
  for ((i = 0; i < 130; i++)); do json="${json}["; done
  json="${json}0"
  for ((i = 0; i < 130; i++)); do json="${json}]"; done
  json="${json}}]"
  run without_jq _gitlab_mr_matches_tip "$json" abc123
  [ "$status" -eq 1 ]
  [ "$output" = "" ]
}

@test "GitLab no-jq matching normalizes parser execution failures" {
  awk() { printf 'parser resource limit\n' >&2; return 2; }

  run without_jq _gitlab_mr_matches_tip '[{"sha":"abc123"}]' abc123

  [ "$status" -eq 1 ]
  [ "$output" = "" ]
}

@test "GitLab no-jq matching is safe in a Bash 3.2 errexit conditional" {
  run /bin/bash -e -c '
    source "$1/lib/provider.sh"
    PATH="$2"
    if _gitlab_mr_matches_tip '\''[{"sha":"abc123"}] trailing'\'' abc123; then exit 99; fi
    if _gitlab_mr_matches_tip '\''[{"author":{},"sha":"abc123"}]'\'' abc123; then
      printf "matched"
    else exit 98; fi
  ' bash "$PROJECT_ROOT" "$NO_JQ_BIN"
  [ "$status" -eq 0 ]
  [ "$output" = matched ]
}

@test "GitLab cleanup without jq preserves nested matches and removes a matching MR tip" {
  setup_integration_repo
  source_gtr_commands
  create_test_worktree structural-sha
  local tip response
  tip=$(git -C "$TEST_WT_PATH" rev-parse HEAD)
  _clean_detect_provider() { printf gitlab; }
  ensure_provider_cli() { return 0; }
  glab() { printf '%s' "$response"; }
  # Keep the full toolchain for cleanup, hiding only jq discovery.
  command() {
    if [ "$1" = -v ] && [ "${2:-}" = jq ]; then return 1; fi
    builtin command "$@"
  }

  response="[{\"state\":\"merged\",\"metadata\":{\"diff_refs\":{\"head_sha\":\"$tip\"}}}]"
  run cmd_clean --merged --yes
  [ "$status" -eq 0 ]
  [ -d "$TEST_WT_PATH" ]

  response="[{\"state\":\"merged\",\"author\":{\"id\":1},\"sha\":\"$tip\"}]"
  run cmd_clean --merged --yes
  [ "$status" -eq 0 ]
  [ ! -d "$TEST_WT_PATH" ]
}
