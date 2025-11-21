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
    case "$pattern" in
      /*|*/../*|../*|*/..|..)
        log_warn "Skipping unsafe pattern (absolute path or '..' path segment): $pattern"
        continue
        ;;
    esac

    # Detect if pattern uses ** (requires globstar)
    if [ "$have_globstar" -eq 0 ] && echo "$pattern" | grep -q '\*\*'; then
      # Fallback to find for ** patterns on Bash 3.2
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
    else
      # Use native Bash glob expansion (supports ** if available)
      for file in $pattern; do
        # Skip if not a file
        [ -f "$file" ] || continue

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
      done
    fi
  done <<EOF
$includes
EOF

  # Restore previous shell options
  eval "$shopt_save" 2>/dev/null || true

  cd "$old_pwd" || return 1

  if [ "$copied_count" -gt 0 ]; then
    log_info "Copied $copied_count file(s)"
  fi

  return 0
}

# Copy directories matching patterns (typically git-ignored directories like node_modules)
# Usage: copy_directories src_root dst_root dir_patterns excludes
# dir_patterns: newline-separated directory names to copy (e.g., "node_modules", ".venv")
# excludes: newline-separated directory names to exclude
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
    case "$pattern" in
      /*|*/../*|../*|*/..|..)
        log_warn "Skipping unsafe pattern: $pattern"
        continue
        ;;
    esac

    # Find directories matching the pattern name
    while IFS= read -r dir_path; do
      [ -z "$dir_path" ] && continue

      # Remove leading ./
      dir_path="${dir_path#./}"

      # Check if directory matches any exclude pattern
      local excluded=0
      if [ -n "$excludes" ]; then
        while IFS= read -r exclude_pattern; do
          [ -z "$exclude_pattern" ] && continue
          local dir_basename
          dir_basename=$(basename "$dir_path")
          if [ "$dir_basename" = "$exclude_pattern" ]; then
            excluded=1
            break
          fi
        done <<EOF
$excludes
EOF
      fi

      # Skip if excluded
      [ "$excluded" -eq 1 ] && continue

      # Ensure source directory exists
      [ ! -d "$dir_path" ] && continue

      # Determine destination
      local dest_dir="$dst_root/$dir_path"
      local dest_parent
      dest_parent=$(dirname "$dest_dir")

      # Create parent directory
      mkdir -p "$dest_parent"

      # Copy directory (cp -r copies the directory itself into dest_parent)
      if cp -r "$dir_path" "$dest_parent/" 2>/dev/null; then
        log_info "Copied directory $dir_path"
        copied_count=$((copied_count + 1))
      else
        log_warn "Failed to copy directory $dir_path"
      fi
    done <<EOF
$(find . -type d -name "$pattern" 2>/dev/null)
EOF
  done <<EOF
$dir_patterns
EOF

  cd "$old_pwd" || return 1

  if [ "$copied_count" -gt 0 ]; then
    log_info "Copied $copied_count director(ies)"
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
