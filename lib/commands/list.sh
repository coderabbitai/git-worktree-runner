#!/usr/bin/env bash

# List command
# shellcheck disable=SC2154  # _arg_* set by parse_args, _ctx_* set by resolve_*
cmd_list() {
  parse_args "--porcelain
--ids" "$@"

  local porcelain="${_arg_porcelain:-0}"
  local ids="${_arg_ids:-0}"

  resolve_repo_context || exit 1

  local repo_root="$_ctx_repo_root"
  local records
  records=$(list_worktree_records "$repo_root") || return 1

  # Machine-readable output (porcelain)
  if [ "$porcelain" -eq 1 ] || [ "$ids" -eq 1 ]; then
    # Output: path (or escaped path: identity)<tab>branch<tab>status
    local is_main="" path="" branch="" status="" linked_rows="" line
    while IFS= read -r line; do
      case "$line" in
        "")
          [ -z "$path" ] && continue
          if [ "$is_main" = "1" ]; then
            if [ "$ids" -eq 1 ]; then
              printf "path:%s" "$path"
            else
              _tsv_unescape_field "$path"
            fi
            printf "\t%s\t%s\n" "$branch" "$status"
          else
            linked_rows="${linked_rows}${path}"$'\t'"${branch}"$'\t'"${status}"$'\n'
          fi
          is_main=""
          path=""
          branch=""
          status=""
          ;;
        "is_main "*)
          is_main="${line#is_main }"
          ;;
        "path "*)
          # Keep paths escaped through line-based buffering and sorting.
          path="${line#path }"
          ;;
        "branch "*)
          branch=$(_tsv_unescape_field "${line#branch }")
          ;;
        "status "*)
          status="${line#status }"
          ;;
      esac
    done <<EOF
$records
EOF

    if [ -n "$path" ]; then
      if [ "$is_main" = "1" ]; then
        if [ "$ids" -eq 1 ]; then
          printf "path:%s" "$path"
        else
          _tsv_unescape_field "$path"
        fi
        printf "\t%s\t%s\n" "$branch" "$status"
      else
        linked_rows="${linked_rows}${path}"$'\t'"${branch}"$'\t'"${status}"$'\n'
      fi
    fi

    if [ -n "$linked_rows" ]; then
      printf "%s" "$linked_rows" | LC_ALL=C sort -t "$(printf '\t')" -k2,2 -k1,1 | while IFS=$'\t' read -r path branch status; do
        if [ "$ids" -eq 1 ]; then
          printf "path:%s" "$path"
        else
          _tsv_unescape_field "$path"
        fi
        printf "\t%s\t%s\n" "$branch" "$status"
      done
    fi
    return 0
  fi

  # Human-readable output - table format
  echo "Git Worktrees"
  echo ""
  printf "%-30s %s\n" "BRANCH" "PATH"
  printf "%-30s %s\n" "------" "----"

  local is_main="" path="" branch="" status="" linked_rows="" line
  while IFS= read -r line; do
    case "$line" in
      "")
        [ -z "$path" ] && continue
        if [ "$is_main" = "1" ]; then
          printf "%-30s " "$branch [main repo]"
          _tsv_unescape_field "$path"
          printf '\n'
        else
          linked_rows="${linked_rows}${branch}"$'\t'"${path}"$'\n'
        fi
        is_main=""
        path=""
        branch=""
        status=""
        ;;
      "is_main "*)
        is_main="${line#is_main }"
        ;;
      "path "*)
        path="${line#path }"
        ;;
      "branch "*)
        branch=$(_tsv_unescape_field "${line#branch }")
        ;;
      "status "*)
        status="${line#status }"
        ;;
    esac
  done <<EOF
$records
EOF

  if [ -n "$path" ]; then
    if [ "$is_main" = "1" ]; then
      printf "%-30s " "$branch [main repo]"
      _tsv_unescape_field "$path"
      printf '\n'
    else
      linked_rows="${linked_rows}${branch}"$'\t'"${path}"$'\n'
    fi
  fi

  if [ -n "$linked_rows" ]; then
    printf "%s" "$linked_rows" | LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2 | while IFS=$'\t' read -r branch path; do
      [ -z "$path" ] && continue
      printf "%-30s " "$branch"
      _tsv_unescape_field "$path"
      printf '\n'
    done
  fi

  echo ""
  echo ""
  echo "Tip: Use 'git gtr list --porcelain' for machine-readable output"
}
