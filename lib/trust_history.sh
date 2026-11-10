#!/usr/bin/env bash
# Shared by CLI trust checks and the self-contained generated shell helpers.

# Bind approval to both the Git directory and its object database. Replacing
# children while retaining only .git must not preserve the repository identity.
# Normal commits, repacks and linked worktrees retain these directory instances.
_hooks_repo_identity() {
  local repo_root="$1" common_dir directory identity birth_time
  common_dir=$(git -C "$repo_root" rev-parse --git-common-dir 2>/dev/null) || return 1
  common_dir=$(cd "$repo_root" && cd "$common_dir" && pwd -P) || return 1
  for directory in "$common_dir" "$common_dir/objects"; do
    directory=$(cd "$directory" && pwd -P) || return 1
    # GNU %W loses fractional seconds; %w and BSD %.9FB retain birth precision.
    identity=$(LC_ALL=C TZ=UTC stat -c '%d:%i:%W:%w' "$directory" 2>/dev/null) ||
      identity=$(LC_ALL=C stat -f '%d:%i:%.9FB' "$directory" 2>/dev/null) || return 1
    birth_time="${identity#*:*:}"
    birth_time="${birth_time%%:*}"
    case "$birth_time" in ''|0|0.*|*[!0-9.]*) return 1 ;; esac
    printf '%s\n%s\n' "$directory" "$identity"
  done
}

# Require actual shared commit history, not just objects retained in a replaced
# database. Repository-owned replace refs, grafts and commit-graph caches cannot
# establish continuity. Approval checks must never fetch from a promisor remote.
# This attests repository continuity, not the bytes of delegated scripts.
_hooks_history_matches() {
  local repo_root="$1" approved_commit="$2"
  case "$approved_commit" in ''|*[!0-9a-f]*) return 1 ;; esac
  case "${#approved_commit}" in 40|64) ;; *) return 1 ;; esac
  # The transport allowlist also blocks lazy fetches on older Git versions that
  # do not recognize GIT_NO_LAZY_FETCH. Read parent links from actual objects.
  GIT_ALLOW_PROTOCOL='' GIT_NO_LAZY_FETCH=1 GIT_NO_REPLACE_OBJECTS=1 GIT_GRAFT_FILE=/dev/null \
    git -C "$repo_root" -c core.commitGraph=false merge-base "$approved_commit" HEAD >/dev/null 2>&1
}
