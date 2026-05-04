#!/usr/bin/env bash

# List command
# shellcheck disable=SC2154  # _arg_* set by parse_args, _ctx_* set by resolve_*
cmd_list() {
  parse_args "--porcelain" "$@"

  local porcelain="${_arg_porcelain:-0}"

  resolve_repo_context || exit 1

  local repo_root="$_ctx_repo_root"
  local records
  records=$(list_worktree_records "$repo_root")

  # Machine-readable output (porcelain)
  if [ "$porcelain" -eq 1 ]; then
    # Output: path<tab>branch<tab>status
    local is_main path branch status linked_rows=""
    while IFS=$'\t' read -r is_main path branch status; do
      [ -z "$path" ] && continue
      if [ "$is_main" = "1" ]; then
        printf "%s\t%s\t%s\n" "$path" "$branch" "$status"
      else
        linked_rows="${linked_rows}${path}"$'\t'"${branch}"$'\t'"${status}"$'\n'
      fi
    done <<EOF
$records
EOF

    if [ -n "$linked_rows" ]; then
      printf "%s" "$linked_rows" | LC_ALL=C sort -t "$(printf '\t')" -k2,2 -k1,1
    fi
    return 0
  fi

  # Human-readable output - table format
  echo "Git Worktrees"
  echo ""
  printf "%-30s %s\n" "BRANCH" "PATH"
  printf "%-30s %s\n" "------" "----"

  local is_main path branch status linked_rows=""
  while IFS=$'\t' read -r is_main path branch status; do
    [ -z "$path" ] && continue
    if [ "$is_main" = "1" ]; then
      printf "%-30s %s\n" "$branch [main repo]" "$path"
    else
      linked_rows="${linked_rows}${branch}"$'\t'"${path}"$'\n'
    fi
  done <<EOF
$records
EOF

  if [ -n "$linked_rows" ]; then
    printf "%s" "$linked_rows" | LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2 | while IFS=$'\t' read -r branch path; do
      [ -z "$path" ] && continue
      printf "%-30s %s\n" "$branch" "$path"
    done
  fi

  echo ""
  echo ""
  echo "Tip: Use 'git gtr list --porcelain' for machine-readable output"
}
