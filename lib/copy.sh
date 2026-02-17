#!/usr/bin/env bash
# File copying utilities with pattern matching

# --- Context Globals Contract ---
# merge_copy_patterns() -> _ctx_copy_includes  _ctx_copy_excludes
declare _ctx_copy_includes _ctx_copy_excludes

# Check if a path/pattern is unsafe (absolute or contains directory traversal)
# Usage: _is_unsafe_path "pattern"
# Returns: 0 if unsafe, 1 if safe
_is_unsafe_path() {
  case "$1" in
    /*|*/../*|../*|*/..|..) return 0 ;;
  esac
  return 1
}

# Check if a path matches any exclude pattern
# Usage: is_excluded "path" "excludes_newline_separated"
# Returns: 0 if excluded, 1 if not
is_excluded() {
  local path="$1"
  local excludes="$2"

  [ -z "$excludes" ] && return 1

  while IFS= read -r exclude_pattern; do
    [ -z "$exclude_pattern" ] && continue
    # Intentional glob pattern matching for exclusion
    # shellcheck disable=SC2254
    case "$path" in
      $exclude_pattern) return 0 ;;
    esac
  done <<EOF
$excludes
EOF

  return 1
}

# Parse .gitignore-style pattern file
# Usage: parse_pattern_file file_path
# Returns: newline-separated patterns (comments and empty lines stripped)
parse_pattern_file() {
  local file_path="$1"

  if [ ! -f "$file_path" ]; then
    return 0
  fi

  # Read file, strip comments and empty lines
  grep -v '^#' "$file_path" 2>/dev/null | grep -v '^[[:space:]]*$' || true
}

# Merge copy patterns from config and .worktreeinclude file
# Usage: merge_copy_patterns repo_root
# Sets: _ctx_copy_includes, _ctx_copy_excludes (newline-separated patterns)
merge_copy_patterns() {
  local repo_root="$1"

  _ctx_copy_includes=$(cfg_get_all gtr.copy.include copy.include)
  _ctx_copy_excludes=$(cfg_get_all gtr.copy.exclude copy.exclude)

  # Read .worktreeinclude file if exists
  local file_includes
  file_includes=$(parse_pattern_file "$repo_root/.worktreeinclude")

  # Merge file patterns into includes
  if [ -n "$file_includes" ]; then
    if [ -n "$_ctx_copy_includes" ]; then
      _ctx_copy_includes="$_ctx_copy_includes"$'\n'"$file_includes"
    else
      _ctx_copy_includes="$file_includes"
    fi
  fi
}

# Copy a directory using CoW (copy-on-write) when available, falling back to standard cp.
# macOS APFS: cp -cRP (clone); Linux Btrfs/XFS: cp --reflink=auto -RP
# Callers must guard the return value with `if` or `|| true` (set -e safe).
# Usage: _fast_copy_dir src dest
# Cached OS value for _fast_copy_dir; set on first call.
_fast_copy_os=""

_fast_copy_dir() {
  local src="$1" dest="$2"
  if [ -z "$_fast_copy_os" ]; then
    _fast_copy_os=$(detect_os)
  fi
  local os="$_fast_copy_os"

  case "$os" in
    darwin)
      # Try CoW clone first; if unsupported, fall back to regular copy
      if cp -cRP "$src" "$dest" 2>/dev/null; then
        return 0
      fi
      # Clean up any partial clone output before fallback
      local _clone_target="${dest%/}/$(basename "$src")"
      if [ -e "$_clone_target" ]; then rm -rf "$_clone_target"; fi
      cp -RP "$src" "$dest"
      ;;
    linux)
      cp --reflink=auto -RP "$src" "$dest"
      ;;
    *)
      cp -RP "$src" "$dest"
      ;;
  esac
}

# Copy a single file to destination, handling exclusion, path preservation, and dry-run
# Usage: _copy_pattern_file file dst_root excludes preserve_paths dry_run
# Returns: 0 if file was copied (or would be in dry-run), 1 if skipped/failed
_copy_pattern_file() {
  local file="$1"
  local dst_root="$2"
  local excludes="$3"
  local preserve_paths="$4"
  local dry_run="$5"

  # Remove leading ./
  file="${file#./}"

  # Skip if excluded
  is_excluded "$file" "$excludes" && return 1

  # Determine destination path
  local dest_file
  if [ "$preserve_paths" = "true" ]; then
    dest_file="$dst_root/$file"
  else
    dest_file="$dst_root/$(basename "$file")"
  fi

  # Copy the file (or show what would be copied in dry-run mode)
  if [ "$dry_run" = "true" ]; then
    log_info "[dry-run] Would copy: $file"
    return 0
  fi

  local dest_dir
  dest_dir=$(dirname "$dest_file")
  mkdir -p "$dest_dir"
  if cp "$file" "$dest_file" 2>/dev/null; then
    log_info "Copied $file"
    return 0
  else
    log_warn "Failed to copy $file"
    return 1
  fi
}

# Process a single glob pattern: expand via globstar or find fallback, copy matching files.
# Must be called from within the source directory with shell options already configured.
# Prints the number of files copied to stdout.
# Usage: _expand_and_copy_pattern <pattern> <dst_root> <excludes> <preserve_paths> <dry_run> <have_globstar>
_expand_and_copy_pattern() {
  local pattern="$1" dst_root="$2" excludes="$3"
  local preserve_paths="$4" dry_run="$5" have_globstar="$6"
  local count=0

  if [ "$have_globstar" -eq 0 ] && echo "$pattern" | grep -q '\*\*'; then
    # Fallback to find for ** patterns on Bash 3.2
    while IFS= read -r file; do
      if _copy_pattern_file "$file" "$dst_root" "$excludes" "$preserve_paths" "$dry_run"; then
        count=$((count + 1))
      fi
    done <<EOF
$(find . -path "./$pattern" -type f 2>/dev/null || true)
EOF
  else
    # Use native Bash glob expansion (supports ** if available)
    for file in $pattern; do
      [ -f "$file" ] || continue
      if _copy_pattern_file "$file" "$dst_root" "$excludes" "$preserve_paths" "$dry_run"; then
        count=$((count + 1))
      fi
    done
  fi

  printf "%s" "$count"
}

# Copy files matching patterns from source to destination
# Usage: copy_patterns src_root dst_root includes excludes [preserve_paths] [dry_run]
# includes: newline-separated glob patterns to include
# excludes: newline-separated glob patterns to exclude
# preserve_paths: true (default) to preserve directory structure
# dry_run: true to only show what would be copied without copying
copy_patterns() {
  local src_root="$1" dst_root="$2" includes="$3" excludes="$4"
  local preserve_paths="${5:-true}" dry_run="${6:-false}"

  [ -z "$includes" ] && return 0

  local old_pwd
  old_pwd=$(pwd)
  cd "$src_root" || return 1

  # Save and configure shell options for glob expansion
  local shopt_save
  shopt_save="$(shopt -p nullglob dotglob globstar 2>/dev/null || true)"
  local have_globstar=0
  if shopt -s globstar 2>/dev/null; then
    have_globstar=1
  fi
  shopt -s nullglob dotglob 2>/dev/null || true

  local copied_count=0

  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue

    if _is_unsafe_path "$pattern"; then
      log_warn "Skipping unsafe pattern (absolute path or '..' path segment): $pattern"
      continue
    fi

    local pattern_copied
    pattern_copied=$(_expand_and_copy_pattern "$pattern" "$dst_root" "$excludes" "$preserve_paths" "$dry_run" "$have_globstar")
    copied_count=$((copied_count + pattern_copied))
  done <<EOF
$includes
EOF

  eval "$shopt_save" 2>/dev/null || true
  cd "$old_pwd" || return 1

  if [ "$copied_count" -gt 0 ]; then
    if [ "$dry_run" = "true" ]; then
      log_info "[dry-run] Would copy $copied_count file(s)"
    else
      log_info "Copied $copied_count file(s)"
    fi
  fi

  return 0
}

# Remove excluded subdirectories from a copied directory.
# Supports patterns like "node_modules/.cache", "*/.cache", "node_modules/*", "*/.*"
# Usage: _apply_directory_excludes <dest_parent> <dir_path> <excludes>
_apply_directory_excludes() {
  local dest_parent="$1" dir_path="$2" excludes="$3"

  [ -z "$excludes" ] && return 0

  local exclude_pattern
  while IFS= read -r exclude_pattern; do
    [ -z "$exclude_pattern" ] && continue

    if _is_unsafe_path "$exclude_pattern"; then
      log_warn "Skipping unsafe exclude pattern: $exclude_pattern"
      continue
    fi

    # Only process patterns with directory separators
    case "$exclude_pattern" in
      */*)
        local pattern_prefix="${exclude_pattern%%/*}"
        local pattern_suffix="${exclude_pattern#*/}"

        # Intentional glob pattern matching for directory prefix
        # shellcheck disable=SC2254
        case "$dir_path" in
          $pattern_prefix)
            local exclude_old_pwd
            exclude_old_pwd=$(pwd)
            cd "$dest_parent/$dir_path" 2>/dev/null || continue

            local exclude_shopt_save
            exclude_shopt_save="$(shopt -p dotglob 2>/dev/null || true)"
            shopt -s dotglob 2>/dev/null || true

            local removed_any=0
            for matched_path in $pattern_suffix; do
              if [ -e "$matched_path" ]; then
                if rm -rf "$matched_path" 2>/dev/null; then
                  removed_any=1
                fi
              fi
            done

            eval "$exclude_shopt_save" 2>/dev/null || true
            cd "$exclude_old_pwd" || true

            if [ "$removed_any" -eq 1 ]; then
              log_info "Excluded subdirectory $exclude_pattern"
            fi
            ;;
        esac
        ;;
    esac
  done <<EOF
$excludes
EOF
}

# Copy directories matching patterns (typically git-ignored directories like node_modules)
# Usage: copy_directories src_root dst_root dir_patterns excludes
# dir_patterns: newline-separated directory names to copy (e.g., "node_modules", ".venv")
# excludes: newline-separated directory patterns to exclude (supports globs like "node_modules/.cache")
# WARNING: This copies entire directories including potentially sensitive files.
#          Use gtr.copy.excludeDirs to exclude sensitive directories.
copy_directories() {
  local src_root="$1"
  local dst_root="$2"
  local dir_patterns="$3"
  local excludes="$4"

  if [ -z "$dir_patterns" ]; then
    return 0
  fi

  local old_pwd
  old_pwd=$(pwd)
  cd "$src_root" || return 1

  local copied_count=0

  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue

    if _is_unsafe_path "$pattern"; then
      log_warn "Skipping unsafe pattern: $pattern"
      continue
    fi

    # Find directories matching the pattern
    # Use -path for patterns with slashes (e.g., vendor/bundle), -name for basenames
    # Note: case inside $() inside heredocs breaks Bash 3.2, so compute first
    local find_results
    case "$pattern" in
      */*) find_results=$(find . -type d -path "./$pattern" 2>/dev/null) ;;
      *)   find_results=$(find . -type d -name "$pattern" 2>/dev/null) ;;
    esac

    while IFS= read -r dir_path; do
      [ -z "$dir_path" ] && continue
      dir_path="${dir_path#./}"

      is_excluded "$dir_path" "$excludes" && continue
      [ ! -d "$dir_path" ] && continue

      local dest_dir="$dst_root/$dir_path"
      local dest_parent
      dest_parent=$(dirname "$dest_dir")
      mkdir -p "$dest_parent"

      # Copy directory using CoW when available (preserves symlinks as symlinks)
      if _fast_copy_dir "$dir_path" "$dest_parent/"; then
        log_info "Copied directory $dir_path"
        copied_count=$((copied_count + 1))
        _apply_directory_excludes "$dest_parent" "$dir_path" "$excludes"
      else
        log_warn "Failed to copy directory $dir_path"
      fi
    done <<EOF
$find_results
EOF
  done <<EOF
$dir_patterns
EOF

  cd "$old_pwd" || return 1

  if [ "$copied_count" -gt 0 ]; then
    log_info "Copied $copied_count directories"
  fi

  return 0
}
