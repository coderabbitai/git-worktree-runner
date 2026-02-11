#!/usr/bin/env bash
# File copying utilities with pattern matching

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

# Copy files matching patterns from source to destination
# Usage: copy_patterns src_root dst_root includes excludes [preserve_paths] [dry_run]
# includes: newline-separated glob patterns to include
# excludes: newline-separated glob patterns to exclude
# preserve_paths: true (default) to preserve directory structure
# dry_run: true to only show what would be copied without copying
copy_patterns() {
  local src_root="$1"
  local dst_root="$2"
  local includes="$3"
  local excludes="$4"
  local preserve_paths="${5:-true}"
  local dry_run="${6:-false}"

  if [ -z "$includes" ]; then
    # No patterns to copy
    return 0
  fi

  # Change to source directory
  local old_pwd
  old_pwd=$(pwd)
  cd "$src_root" || return 1

  # Save current shell options
  local shopt_save
  shopt_save="$(shopt -p nullglob dotglob globstar 2>/dev/null || true)"

  # Try to enable globstar for ** patterns (Bash 4.0+)
  # nullglob: patterns that don't match expand to nothing
  # dotglob: * matches hidden files
  # globstar: ** matches directories recursively
  local have_globstar=0
  if shopt -s globstar 2>/dev/null; then
    have_globstar=1
  fi
  shopt -s nullglob dotglob 2>/dev/null || true

  local copied_count=0

  # Process each include pattern (avoid pipeline subshell)
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue

    # Security: reject absolute paths and parent directory traversal
    if _is_unsafe_path "$pattern"; then
      log_warn "Skipping unsafe pattern (absolute path or '..' path segment): $pattern"
      continue
    fi

    # Detect if pattern uses ** (requires globstar)
    if [ "$have_globstar" -eq 0 ] && echo "$pattern" | grep -q '\*\*'; then
      # Fallback to find for ** patterns on Bash 3.2
      while IFS= read -r file; do
        if _copy_pattern_file "$file" "$dst_root" "$excludes" "$preserve_paths" "$dry_run"; then
          copied_count=$((copied_count + 1))
        fi
      done <<EOF
$(find . -path "./$pattern" -type f 2>/dev/null)
EOF
    else
      # Use native Bash glob expansion (supports ** if available)
      for file in $pattern; do
        # Skip if not a file
        [ -f "$file" ] || continue

        if _copy_pattern_file "$file" "$dst_root" "$excludes" "$preserve_paths" "$dry_run"; then
          copied_count=$((copied_count + 1))
        fi
      done
    fi
  done <<EOF
$includes
EOF

  # Restore previous shell options
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

  # Change to source directory
  local old_pwd
  old_pwd=$(pwd)
  cd "$src_root" || return 1

  local copied_count=0

  # Process each directory pattern
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue

    # Security: reject absolute paths and parent directory traversal
    if _is_unsafe_path "$pattern"; then
      log_warn "Skipping unsafe pattern: $pattern"
      continue
    fi

    # Find directories matching the pattern
    # Use -path for patterns with slashes (e.g., vendor/bundle), -name for basenames
    while IFS= read -r dir_path; do
      [ -z "$dir_path" ] && continue

      # Remove leading ./
      dir_path="${dir_path#./}"

      # Skip if excluded
      is_excluded "$dir_path" "$excludes" && continue

      # Ensure source directory exists
      [ ! -d "$dir_path" ] && continue

      # Determine destination
      local dest_dir="$dst_root/$dir_path"
      local dest_parent
      dest_parent=$(dirname "$dest_dir")

      # Create parent directory
      mkdir -p "$dest_parent"

      # Copy directory (cp -RP preserves symlinks as symlinks)
      if cp -RP "$dir_path" "$dest_parent/" 2>/dev/null; then
        log_info "Copied directory $dir_path"
        copied_count=$((copied_count + 1))

        # Remove excluded subdirectories after copying
        if [ -n "$excludes" ]; then
          while IFS= read -r exclude_pattern; do
            [ -z "$exclude_pattern" ] && continue

            # Security: reject absolute paths and parent directory traversal in excludes
            if _is_unsafe_path "$exclude_pattern"; then
              log_warn "Skipping unsafe exclude pattern: $exclude_pattern"
              continue
            fi

            # Check if pattern applies to this copied directory
            # Supports patterns like:
            #   "node_modules/.cache" - exact path
            #   "*/.cache" - wildcard prefix (matches any directory)
            #   "node_modules/*" - wildcard suffix (matches all subdirectories)
            #   "*/.*" - both (matches all hidden subdirectories in any directory)

            # Only process patterns with directory separators
            case "$exclude_pattern" in
              */*)
                # Extract prefix (before first /) and suffix (after first /)
                local pattern_prefix="${exclude_pattern%%/*}"
                local pattern_suffix="${exclude_pattern#*/}"

                # Check if our copied directory matches the prefix pattern
                # Intentional glob pattern matching for directory prefix
                # shellcheck disable=SC2254
                case "$dir_path" in
                  $pattern_prefix)
                    # Match! Remove matching subdirectories using suffix pattern

                    # Save current directory
                    local exclude_old_pwd
                    exclude_old_pwd=$(pwd)

                    # Change to destination directory for glob expansion
                    cd "$dest_parent/$dir_path" 2>/dev/null || continue

                    # Enable dotglob to match hidden files with wildcards
                    local exclude_shopt_save
                    exclude_shopt_save="$(shopt -p dotglob 2>/dev/null || true)"
                    shopt -s dotglob 2>/dev/null || true

                    # Expand glob pattern and remove matched paths
                    local removed_any=0
                    for matched_path in $pattern_suffix; do
                      # Check if glob matched anything (avoid literal pattern if no match)
                      if [ -e "$matched_path" ]; then
                        rm -rf "$matched_path" 2>/dev/null && removed_any=1 || true
                      fi
                    done

                    # Restore shell options and directory
                    eval "$exclude_shopt_save" 2>/dev/null || true
                    cd "$exclude_old_pwd" || true

                    # Log only if we actually removed something
                    [ "$removed_any" -eq 1 ] && log_info "Excluded subdirectory $exclude_pattern" || true
                    ;;
                esac
                ;;
            esac
          done <<EOF
$excludes
EOF
        fi
      else
        log_warn "Failed to copy directory $dir_path"
      fi
    done <<EOF
$(if [[ "$pattern" == */* ]]; then find . -type d -path "./$pattern" 2>/dev/null; else find . -type d -name "$pattern" 2>/dev/null; fi)
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

# Copy a single file, creating directories as needed
# Usage: copy_file src_file dst_file
copy_file() {
  local src="$1"
  local dst="$2"
  local dst_dir

  dst_dir=$(dirname "$dst")
  mkdir -p "$dst_dir"

  if cp "$src" "$dst" 2>/dev/null; then
    return 0
  else
    return 1
  fi
}
