#!/usr/bin/env bats
# Run the actual workflow script with local archive and contents-API fixtures.
# Functions exported below are invoked by the workflow subprocess.
# shellcheck disable=SC2329

load test_helper

setup() {
  command -v jq >/dev/null || skip "jq is required for the Homebrew workflow"
  export HOMEBREW_FIXTURE="$BATS_TEST_TMPDIR/homebrew"
  mkdir -p "$HOMEBREW_FIXTURE"
  cd "$HOMEBREW_FIXTURE" || return 1
  export TAG_NAME=v2.8.0 GH_TOKEN=local-test-token
  export EXPECTED_URL="https://github.com/coderabbitai/git-worktree-runner/archive/refs/tags/${TAG_NAME}.tar.gz"
  printf 'local release archive bytes\n' > archive.tar.gz
  : > api.log

  # The workflow runs on Ubuntu. Adapt only GNU utility options on macOS.
  if [ "$(uname -s)" = Darwin ]; then
    sed() {
      if [ "${1:-}" = -i ]; then
        shift
        command sed -i '' "$@"
      else
        command sed "$@"
      fi
    }
    base64() {
      if [ "${1:-}" = -w0 ]; then
        command base64 < "$2" | tr -d '\n'
      else
        command base64 "$@"
      fi
    }
    export -f sed base64
  fi
  if ! command -v sha256sum >/dev/null; then
    sha256sum() { shasum -a 256 "$@"; }
    export -f sha256sum
  fi
  EXPECTED_SHA=$(sha256sum archive.tar.gz | awk '{print $1}')
  STALE_SHA=0000000000000000000000000000000000000000000000000000000000000000

  # Never call the real curl or gh: unexpected arguments fail the test.
  curl() {
    [ "$*" = "-fsSL --retry 3 $EXPECTED_URL -o release.tar.gz" ] || return 99
    cp "$HOMEBREW_FIXTURE/archive.tar.gz" release.tar.gz
  }
  gh() {
    local endpoint=repos/coderabbitai/homebrew-tap/contents/Formula/git-gtr.rb
    if [ "$*" = "api $endpoint" ]; then
      printf 'GET\n' >> "$HOMEBREW_FIXTURE/api.log"
      jq -n --arg sha fixture-blob-sha \
        --arg content "$(base64 < "$HOMEBREW_FIXTURE/tap.rb")" \
        '{sha: $sha, content: $content}'
      return
    fi
    [ "$#" -ge 4 ] || return 99
    [ "$1 $2 $3 $4" = "api --method PUT $endpoint" ] || return 99
    shift 4
    local content='' message='' sha=''
    while [ "$#" -gt 0 ]; do
      [ "$#" -ge 2 ] && [ "$1" = -f ] || return 99
      case "$2" in
        content=*) content=${2#content=} ;;
        message=*) message=${2#message=} ;;
        sha=*) sha=${2#sha=} ;;
        *) return 99 ;;
      esac
      shift 2
    done
    [ "$sha" = fixture-blob-sha ] && [ -n "$content" ] || return 99
    printf '%s' "$content" | base64 -d > "$HOMEBREW_FIXTURE/tap.rb"
    printf '%s\n' "$message" > "$HOMEBREW_FIXTURE/message.txt"
    printf 'PUT\n' >> "$HOMEBREW_FIXTURE/api.log"
  }
  export -f curl gh

  # Extract the sole run block without copying the behavior under test.
  awk '
    /^        run: \|$/ { in_run = 1; next }
    in_run && /^          / { print substr($0, 11); next }
    in_run && /^$/ { print; next }
    in_run { exit }
    END { if (!in_run) exit 1 }
  ' "$PROJECT_ROOT/.github/workflows/homebrew.yml" > workflow.sh
  [ -s workflow.sh ]
  bash -n workflow.sh
}

write_formula() {
  cat <<FORMULA
class GitGtr < Formula
  desc "Git Worktree Runner"
  homepage "https://github.com/coderabbitai/git-worktree-runner"
  url "$1"
  sha256 "$2"
  license "Apache-2.0"
end
FORMULA
}

assert_updated_formula() {
  [ "$status" -eq 0 ]
  write_formula "$EXPECTED_URL" "$EXPECTED_SHA" > expected.rb
  cmp expected.rb tap.rb
  [ "$(cat api.log)" = $'GET\nPUT' ]
  [ "$(cat message.txt)" = $'git-gtr 2.8.0\n\nAutomated update from https://github.com/coderabbitai/git-worktree-runner' ]
}

@test "Homebrew skips when both URL and archive checksum match" {
  write_formula "$EXPECTED_URL" "$EXPECTED_SHA" > tap.rb
  cp tap.rb original.rb

  run bash workflow.sh

  [ "$status" -eq 0 ]
  [[ "$output" == *"Formula already at ${TAG_NAME}; nothing to do."* ]]
  cmp original.rb tap.rb
  [ "$(cat api.log)" = GET ]
}

@test "Homebrew repairs a stale checksum at the intended URL" {
  write_formula "$EXPECTED_URL" "$STALE_SHA" > tap.rb

  run bash workflow.sh

  assert_updated_formula
}

@test "Homebrew updates both an older URL and checksum" {
  write_formula "${EXPECTED_URL/v2.8.0/v2.7.3}" "$STALE_SHA" > tap.rb

  run bash workflow.sh

  assert_updated_formula
}

@test "Homebrew updates an older URL even when the checksum already matches" {
  write_formula "${EXPECTED_URL/v2.8.0/v2.7.3}" "$EXPECTED_SHA" > tap.rb

  run bash workflow.sh

  assert_updated_formula
}

@test "Homebrew rerun after checksum repair is idempotent" {
  write_formula "$EXPECTED_URL" "$STALE_SHA" > tap.rb
  run bash workflow.sh
  assert_updated_formula
  cp tap.rb repaired.rb
  : > api.log

  run bash workflow.sh

  [ "$status" -eq 0 ]
  [[ "$output" == *"Formula already at ${TAG_NAME}; nothing to do."* ]]
  cmp repaired.rb tap.rb
  [ "$(cat api.log)" = GET ]
}

@test "Homebrew refuses an API update if formula verification fails" {
  write_formula "$EXPECTED_URL" "$STALE_SHA" | sed '/^  sha256 /d' > tap.rb
  cp tap.rb original.rb

  run bash workflow.sh

  [ "$status" -ne 0 ]
  cmp original.rb tap.rb
  [ "$(cat api.log)" = GET ]
}
