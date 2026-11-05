#!/usr/bin/env bash
# Remote hosting provider detection and CLI integration
# Used by cmd_clean --merged/--closed to support GitHub (gh) and GitLab (glab)

# Extract hostname from a git remote URL
# Handles SSH shorthand, SSH with scheme, and HTTPS:
#   git@github.com:user/repo.git       -> github.com
#   ssh://git@github.com/user/repo.git -> github.com
#   https://github.com/user/repo.git   -> github.com
# Usage: extract_hostname <url>
extract_hostname() {
  local url="$1"

  case "$url" in
    *@*:*/*)
      # SSH shorthand: git@host:user/path
      local hostname="${url#*@}"
      printf "%s" "${hostname%%:*}"
      ;;
    *://*)
      # SSH or HTTPS with scheme
      local hostname="${url#*://}"
      hostname="${hostname#*@}"
      hostname="${hostname%%/*}"
      hostname="${hostname%%:*}"
      printf "%s" "$hostname"
      ;;
    *)
      return 1
      ;;
  esac
}

# Detect the hosting provider from origin remote URL
# Checks gtr.provider config override first, then auto-detects from URL
# Usage: detect_provider
# Prints: "github", "gitlab", or returns 1 if unknown
detect_provider() {
  # 1. Check explicit config override (handles self-hosted instances)
  local provider
  provider=$(cfg_default "gtr.provider" "GTR_PROVIDER" "")
  if [ -n "$provider" ]; then
    printf "%s" "$provider"
    return 0
  fi

  # 2. Auto-detect from origin URL
  local remote_url
  remote_url=$(git remote get-url origin 2>/dev/null || true)
  if [ -z "$remote_url" ]; then
    return 1
  fi

  local hostname
  hostname=$(extract_hostname "$remote_url") || return 1

  case "$hostname" in
    github.com)  printf "github" ;;
    gitlab.com)  printf "gitlab" ;;
    *)           return 1 ;;
  esac
}

# Ensure the provider's CLI tool is installed and authenticated
# Usage: ensure_provider_cli <provider>
# Returns 0 on success, 1 on failure (with error messages)
ensure_provider_cli() {
  local provider="$1"

  case "$provider" in
    github)
      if ! command -v gh >/dev/null 2>&1; then
        log_error "GitHub CLI (gh) not found. Install from: https://cli.github.com/"
        return 1
      fi
      if ! gh repo view >/dev/null 2>&1; then
        log_error "Not authenticated with GitHub or not a GitHub repository"
        log_info "Run: gh auth login"
        return 1
      fi
      ;;
    gitlab)
      if ! command -v glab >/dev/null 2>&1; then
        log_error "GitLab CLI (glab) not found. Install from: https://gitlab.com/gitlab-org/cli"
        return 1
      fi
      if ! glab repo view >/dev/null 2>&1; then
        log_error "Not authenticated with GitLab or not a GitLab repository"
        log_info "Run: glab auth login"
        return 1
      fi
      ;;
    *)
      log_error "Unsupported hosting provider: $provider"
      return 1
      ;;
  esac
}

# Normalize user-provided refs to plain branch names for provider filters.
# Usage: normalize_target_ref [target_ref]
normalize_target_ref() {
  local target_ref="${1:-}"
  local remote_ref

  [ -n "$target_ref" ] || return 0

  case "$target_ref" in
    refs/heads/*)
      printf "%s" "${target_ref#refs/heads/}"
      ;;
    refs/remotes/*)
      remote_ref="${target_ref#refs/remotes/}"
      printf "%s" "${remote_ref#*/}"
      ;;
    origin/*|upstream/*)
      printf "%s" "${target_ref#*/}"
      ;;
    *)
      if git show-ref --verify --quiet "refs/remotes/$target_ref" 2>/dev/null; then
        printf "%s" "${target_ref#*/}"
      else
        printf "%s" "$target_ref"
      fi
      ;;
  esac
}

# Keep only MR records with an explicit top-level state before checking their tips.
# Track raw nesting and strings even with jq so duplicate keys, nested fields,
# and adjacent records cannot supply the state of an MR. SHA extraction remains
# in the helper below. Escaped keys are conservatively treated as ambiguous.
# Usage: _gitlab_mrs_in_state <mr_json> <merged|closed>
# Prints a nonempty JSON array; returns 1 if the state cannot be established.
_gitlab_mrs_in_state() {
  local mr_result="$1" pr_state="$2"

  if command -v jq >/dev/null 2>&1; then
    # Validate syntax without rewriting the response: jq keeps the last duplicate.
    printf "%s" "$mr_result" | jq -e 'type == "array"' >/dev/null 2>&1 || return 1
  fi

  printf "%s\n" "$mr_result" | awk -v state="$pr_state" '
    # Count literal top-level state keys and reject keys needing escape decoding.
    # Reset the field buffer after each property to avoid mixing adjacent keys.
    function check_field() {
      # Escaped keys could spell a second state field.
      if (field ~ /^"[^"]*\\/) ambiguous = 1
      if (field ~ /^"state":/) {
        state_count++
        state_matches = (field == "\"state\":\"" state "\"")
      }
      field = ""
    }
    BEGIN { expect = "array" }
    {
      for (i = 1; i <= length($0); i++) {
        c = substr($0, i, 1)
        if (quoted) {
          record = record c
          if (depth == 2) field = field c
          if (escaped) escaped = 0
          else if (c == "\\") escaped = 1
          else if (c == "\"") quoted = 0
          continue
        }
        if (c ~ /[[:space:]]/) continue
        if (depth == 0) {
          if (expect != "array" || c != "[") { invalid = 1; exit }
          depth = 1
          expect = "first"
          continue
        }
        if (depth == 1) {
          if (c == "{" && (expect == "first" || expect == "record")) {
            stack[++depth] = c
            record = c
            field = ""
            state_count = state_matches = ambiguous = 0
          } else if (c == "," && expect == "comma") {
            expect = "record"
          } else if (c == "]" && (expect == "first" || expect == "comma")) {
            depth = 0
            expect = "end"
          } else { invalid = 1; exit }
          continue
        }
        record = record c
        if (c == "\"") {
          quoted = 1
          if (depth == 2) field = field c
        } else if (c == "{" || c == "[") {
          if (depth == 2) field = field c
          stack[++depth] = c
        } else if (c == "}" || c == "]") {
          if ((c == "}" && stack[depth] != "{") ||
              (c == "]" && stack[depth] != "[")) { invalid = 1; exit }
          if (depth == 2) {
            check_field()
            if (state_count == 1 && state_matches && !ambiguous) {
              matches = matches separator record
              separator = ","
              count++
            }
            expect = "comma"
          }
          depth--
          if (depth == 2) field = field c
        } else if (c == "," && depth == 2) {
          check_field()
        } else if (depth == 2) field = field c
      }
      if (quoted) { invalid = 1; exit }
    }
    END {
      if (invalid || depth != 0 || expect != "end" || !count) exit 1
      print "[" matches "]"
    }
  '
}

# Check whether state-filtered GitLab MR JSON has a source-head SHA matching branch_tip.
# Uses jq when available; otherwise validates the complete response with
# POSIX awk, keeping cleanup usable without adding a runtime dependency.
# Usage: _gitlab_mr_matches_tip <mr_json> <branch_tip>
_gitlab_mr_matches_tip() {
  local mr_result="$1"
  local branch_tip="$2"

  [ -n "$branch_tip" ] || return 1

  if command -v jq >/dev/null 2>&1; then
    printf "%s" "$mr_result" | jq -e -s --arg branch_tip "$branch_tip" '
      if length == 1 and (.[0] | type == "array") then
        .[0] | if all(.[]; type == "object") then
          map(select((.sha // "") == $branch_tip or
                     (.head_sha // "") == $branch_tip or
                     (.diff_refs.head_sha // "") == $branch_tip)) | length > 0
        else false end
      else false end
    ' >/dev/null 2>&1 || return 1
    return
  fi

  # Track grammar and context separately: root -> MR -> diff_refs -> SHA.
  # Validate even ignored values and the suffix after a match. Duplicate keys
  # and excessive nesting fail closed. Hex-encoded UTF-8 strings keep escaped
  # keys/values comparable without relying on awk support for embedded NULs.
  printf "%s" "$mr_result" | GTR_MR_TIP="$branch_tip" LC_ALL=C awk '
    function fail() { exit 1 }
    function whitespace() {
      while (substr(json, pos, 1) ~ /^[ \t\r\n]$/) pos++
    }
    function encode(text,    i, result) {
      for (i = 1; i <= length(text); i++) result = result bytes[substr(text, i, 1)]
      return result
    }
    function hex4(    text, i, n) {
      text = tolower(substr(json, pos, 4))
      if (length(text) != 4 || text ~ /[^0-9a-f]/) fail()
      pos += 4
      for (i = 1; i <= 4; i++) n = n * 16 + index("0123456789abcdef", substr(text, i, 1)) - 1
      return n
    }
    function unicode(n) {
      if (n < 128) return sprintf("%02x", n)
      if (n < 2048) return sprintf("%02x%02x", 192 + int(n / 64), 128 + n % 64)
      if (n < 65536)
        return sprintf("%02x%02x%02x", 224 + int(n / 4096), 128 + int(n / 64) % 64, 128 + n % 64)
      return sprintf("%02x%02x%02x%02x", 240 + int(n / 262144),
                     128 + int(n / 4096) % 64, 128 + int(n / 64) % 64, 128 + n % 64)
    }
    function utf8(n,    count, minimum, next_byte) {
      if (n < 128) return sprintf("%02x", n)
      if (n >= 194 && n <= 223) { count = 1; minimum = 128; n -= 192 }
      else if (n >= 224 && n <= 239) { count = 2; minimum = 2048; n -= 224 }
      else if (n >= 240 && n <= 244) { count = 3; minimum = 65536; n -= 240 }
      else fail()
      while (count-- > 0) {
        next_byte = ord[substr(json, pos++, 1)]
        if (next_byte < 128 || next_byte > 191) fail()
        n = n * 64 + next_byte - 128
      }
      if (n < minimum || n > 1114111 || (n >= 55296 && n <= 57343)) fail()
      return unicode(n)
    }
    function string(    c, escape, n, low, result) {
      if (substr(json, pos++, 1) != "\"") fail()
      while (pos <= length(json)) {
        c = substr(json, pos++, 1)
        if (c == "\"") return result
        if (ord[c] < 32) fail()
        if (c != "\\") {
          result = result utf8(ord[c])
          continue
        }
        escape = substr(json, pos++, 1)
        if (escape == "u") {
          n = hex4()
          if (n >= 55296 && n <= 56319) {
            if (substr(json, pos, 2) != "\\u") fail()
            pos += 2
            low = hex4()
            if (low < 56320 || low > 57343) fail()
            n = 65536 + (n - 55296) * 1024 + low - 56320
          } else if (n >= 56320 && n <= 57343) fail()
          result = result unicode(n)
        } else if (escape in escapes) {
          result = result escapes[escape]
        } else fail()
      }
      fail()
    }
    function value(context, depth,    c, closing, id, key, child, token, text) {
      if (depth > 128) fail()
      whitespace()
      c = substr(json, pos, 1)
      if (context == "root" && c != "[") fail()
      if (context == "mr" && c != "{") fail()
      if (context == "diff" && c != "{" && substr(json, pos, 4) != "null") fail()
      if (c == "{" || c == "[") {
        closing = (c == "{" ? "}" : "]")
        id = ++object_id
        pos++
        whitespace()
        if (substr(json, pos, 1) == closing) { pos++; return }
        while (1) {
          child = "ignore"
          if (c == "{") {
            key = string()
            if ((id SUBSEP key) in seen) fail()
            seen[id, key] = 1
            whitespace()
            if (substr(json, pos++, 1) != ":") fail()
            if (context == "mr" && (key == sha_key || key == head_key)) child = "sha"
            if (context == "mr" && key == diff_key) child = "diff"
            if (context == "diff" && key == head_key) child = "sha"
          } else if (context == "root") child = "mr"
          value(child, depth + 1)
          whitespace()
          token = substr(json, pos++, 1)
          if (token == closing) return
          if (token != ",") fail()
          whitespace()
        }
      }
      if (c == "\"") {
        text = string()
        if (context == "sha" && text == tip) matched = 1
        return
      }
      text = substr(json, pos)
      if (match(text, /^(true|false|null)/) ||
          match(text, /^-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?/)) {
        pos += RLENGTH
        return
      }
      fail()
    }
    BEGIN {
      for (i = 1; i < 256; i++) {
        c = sprintf("%c", i)
        bytes[c] = sprintf("%02x", i)
        ord[c] = i
      }
      escapes["\""] = "22"; escapes["\\"] = "5c"; escapes["/"] = "2f"
      escapes["b"] = "08"; escapes["f"] = "0c"; escapes["n"] = "0a"
      escapes["r"] = "0d"; escapes["t"] = "09"
      sha_key = encode("sha"); head_key = encode("head_sha"); diff_key = encode("diff_refs")
      tip = encode(ENVIRON["GTR_MR_TIP"])
    }
    { json = json $0 "\n" }
    END {
      pos = 1
      value("root", 0)
      whitespace()
      if (pos <= length(json) || !matched) fail()
    }
  '
}

# Check if a branch has a PR/MR with the requested state on the detected provider.
# When branch_tip is provided, require the PR/MR to point at the same commit so
# reused branch names do not match older PRs/MRs.
# Usage: check_branch_pr_state <provider> <branch> <merged|closed> [target_ref] [branch_tip]
# Returns 0 if found, 1 if not
check_branch_pr_state() {
  local provider="$1"
  local branch="$2"
  local pr_state="$3"
  local target_ref="${4:-}"
  local branch_tip="${5:-}"
  local normalized_target_ref

  case "$pr_state" in
    merged|closed) ;;
    *) return 1 ;;
  esac

  normalized_target_ref=$(normalize_target_ref "$target_ref") || true

  case "$provider" in
    github)
      local -a gh_args
      local expected_state pr_matches
      expected_state=$(printf "%s" "$pr_state" | tr '[:lower:]' '[:upper:]')
      gh_args=(pr list --head "$branch" --state "$pr_state" --limit 1000)
      if [ -n "$normalized_target_ref" ]; then
        gh_args+=(--base "$normalized_target_ref")
      fi
      if [ -n "$branch_tip" ]; then
        pr_matches=$(gh "${gh_args[@]}" --json state,headRefOid --jq "map(select(.state == \"$expected_state\" and .headRefOid == \"$branch_tip\")) | length" 2>/dev/null || true)
      else
        pr_matches=$(gh "${gh_args[@]}" --json state --jq "map(select(.state == \"$expected_state\")) | length" 2>/dev/null || true)
      fi
      [ "${pr_matches:-0}" -gt 0 ]
      ;;
    gitlab)
      local mr_result
      local -a glab_args
      # --all overrides --merged/--closed in glab; it is not a pagination flag.
      glab_args=(mr list --source-branch "$branch" "--$pr_state" --output json)
      if [ -n "$normalized_target_ref" ]; then
        glab_args+=(--target-branch "$normalized_target_ref")
      fi

      mr_result=$(glab "${glab_args[@]}" 2>/dev/null) || return 1
      mr_result=$(_gitlab_mrs_in_state "$mr_result" "$pr_state") || return 1

      if [ -n "$branch_tip" ]; then
        _gitlab_mr_matches_tip "$mr_result" "$branch_tip"
        return
      fi

      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# Check if a branch has a merged PR/MR on the detected provider.
# Usage: check_branch_merged <provider> <branch> [target_ref] [branch_tip]
check_branch_merged() {
  check_branch_pr_state "$1" "$2" merged "${3:-}" "${4:-}"
}

# Check if a branch has a closed, unmerged PR/MR on the detected provider.
# Usage: check_branch_closed <provider> <branch> [target_ref] [branch_tip]
check_branch_closed() {
  check_branch_pr_state "$1" "$2" closed "${3:-}" "${4:-}"
}
