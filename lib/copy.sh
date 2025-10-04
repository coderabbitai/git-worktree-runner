#!/usr/bin/env bash
# File copying utilities with pattern matching

# Copy files matching patterns from source to destination
# Usage: copy_patterns src_root dst_root includes excludes [preserve_paths]
# includes: newline-separated glob patterns to include
# excludes: newline-separated glob patterns to exclude
# preserve_paths: true (default) to preserve directory structure
copy_patterns() {
  local src_root="$1"
  local dst_root="$2"
  local includes="$3"
  local excludes="$4"
  local preserve_paths="${5:-true}"

  if [ -z "$includes" ]; then
    # No patterns to copy
    return 0
  fi

  # Change to source directory
  local old_pwd
  old_pwd=$(pwd)
  cd "$src_root" || return 1

  local copied_count=0

  # Process each include pattern (avoid pipeline subshell)
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue

    # Find files matching the pattern (avoid pipeline subshell)
    while IFS= read -r file; do
      # Remove leading ./
      file="${file#./}"

      # Check if file matches any exclude pattern
      local excluded=0
      if [ -n "$excludes" ]; then
        while IFS= read -r exclude_pattern; do
          [ -z "$exclude_pattern" ] && continue
          case "$file" in
            $exclude_pattern)
              excluded=1
              break
              ;;
          esac
        done <<EOF
$excludes
EOF
      fi

      # Skip if excluded
      [ "$excluded" -eq 1 ] && continue

      # Determine destination path
      local dest_file
      if [ "$preserve_paths" = "true" ]; then
        dest_file="$dst_root/$file"
      else
        dest_file="$dst_root/$(basename "$file")"
      fi

      # Create destination directory
      local dest_dir
      dest_dir=$(dirname "$dest_file")
      mkdir -p "$dest_dir"

      # Copy the file
      if cp "$file" "$dest_file" 2>/dev/null; then
        log_info "Copied $file"
        copied_count=$((copied_count + 1))
      else
        log_warn "Failed to copy $file"
      fi
    done <<EOF
$(find . -path "./$pattern" -type f 2>/dev/null)
EOF
  done <<EOF
$includes
EOF

  cd "$old_pwd" || return 1

  if [ "$copied_count" -gt 0 ]; then
    log_info "Copied $copied_count file(s)"
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
