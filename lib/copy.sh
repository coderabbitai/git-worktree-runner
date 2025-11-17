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

# Copy git-ignored files and directories from source to destination
# Usage: copy_ignored_files src_root dst_root patterns excludes
# patterns: newline-separated glob patterns to match ignored files/dirs (e.g., "node_modules", "vendor")
#           If empty or "*", copies all ignored files
# excludes: newline-separated glob patterns to exclude
copy_ignored_files() {
  local src_root="$1"
  local dst_root="$2"
  local patterns="$3"
  local excludes="$4"

  # Change to source directory
  local old_pwd
  old_pwd=$(pwd)
  cd "$src_root" || return 1

  # Check if we're in a git repository
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    log_warn "Not a git repository, skipping ignored files copy"
    cd "$old_pwd" || return 1
    return 0
  fi

  local copied_count=0

  # If patterns is empty or "*", copy all ignored files
  local copy_all=0
  if [ -z "$patterns" ] || [ "$patterns" = "*" ]; then
    copy_all=1
  fi

  # Collect paths to copy
  local paths_to_copy=""

  if [ "$copy_all" -eq 1 ]; then
    # Get all ignored files and directories
    # Use find to get both files and directories, then filter with git check-ignore
    while IFS= read -r path; do
      [ -z "$path" ] && continue
      # Check if this path is ignored by git
      if git check-ignore -q "$path" 2>/dev/null; then
        paths_to_copy="${paths_to_copy}${path}"$'\n'
      fi
    done <<EOF
$(find . -mindepth 1 -maxdepth 1 2>/dev/null | sed 's|^\./||' | sort)
EOF
  else
    # Process each pattern to find matching ignored files/directories
    while IFS= read -r pattern; do
      [ -z "$pattern" ] && continue

      # Security: reject absolute paths and parent directory traversal
      case "$pattern" in
        /*|*/../*|../*|*/..|..)
          log_warn "Skipping unsafe pattern (absolute path or '..' path segment): $pattern"
          continue
          ;;
      esac

      # Find files/directories matching the pattern
      # Use find to locate paths, then check if they're git-ignored
      local found_paths=""
      
      # First, check if the pattern exists as a direct path
      if [ -e "$pattern" ]; then
        found_paths="$pattern"$'\n'
      fi
      
      # Also search for directories/files matching the pattern name anywhere in the repo
      # This handles cases like "node_modules" or "vendor" that might be in subdirectories
      local pattern_name
      pattern_name=$(basename "$pattern")
      
      # Find all paths matching the pattern name (not just at root)
      local additional_paths
      additional_paths=$(find . \( -name "$pattern_name" -type d -o -name "$pattern_name" -type f \) 2>/dev/null | sed 's|^\./||' | head -100)
      
      if [ -n "$additional_paths" ]; then
        found_paths="${found_paths}${additional_paths}"$'\n'
      fi
      
      # Also try exact path matching (for patterns like "subdir/node_modules")
      if [ "$pattern" != "$pattern_name" ]; then
        local exact_paths
        exact_paths=$(find . -path "./$pattern" 2>/dev/null | sed 's|^\./||')
        if [ -n "$exact_paths" ]; then
          found_paths="${found_paths}${exact_paths}"$'\n'
        fi
      fi

      # Check each found path to see if it's git-ignored
      while IFS= read -r path; do
        [ -z "$path" ] && continue
        # Check if this path is ignored by git
        if git check-ignore -q "$path" 2>/dev/null; then
          # Check if already in list (avoid duplicates)
          if ! echo "$paths_to_copy" | grep -Fxq "$path"; then
            paths_to_copy="${paths_to_copy}${path}"$'\n'
          fi
        fi
      done <<EOF
$found_paths
EOF
    done <<EOF
$patterns
EOF
  fi

  if [ -z "$paths_to_copy" ]; then
    cd "$old_pwd" || return 1
    return 0
  fi

  # Process each path to copy
  while IFS= read -r ignored_path; do
    [ -z "$ignored_path" ] && continue

    # Remove leading ./
    ignored_path="${ignored_path#./}"

    # Skip if path doesn't exist
    [ ! -e "$ignored_path" ] && continue

    # Check if file matches any exclude pattern
    local excluded=0
    if [ -n "$excludes" ]; then
      while IFS= read -r exclude_pattern; do
        [ -z "$exclude_pattern" ] && continue
        case "$ignored_path" in
          $exclude_pattern|$exclude_pattern/*|*/$exclude_pattern|*/$exclude_pattern/*)
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
    local dest_path="$dst_root/$ignored_path"

    # Create destination directory
    local dest_dir
    if [ -d "$ignored_path" ]; then
      dest_dir="$dest_path"
    else
      dest_dir=$(dirname "$dest_path")
    fi
    mkdir -p "$dest_dir"

    # Copy the file or directory
    if [ -d "$ignored_path" ]; then
      # Use rsync if available for better directory copying, otherwise use cp -r
      if command -v rsync >/dev/null 2>&1; then
        if rsync -a --quiet "$ignored_path/" "$dest_path/" 2>/dev/null; then
          log_info "Copied directory $ignored_path/"
          copied_count=$((copied_count + 1))
        else
          log_warn "Failed to copy directory $ignored_path/"
        fi
      else
        if cp -r "$ignored_path" "$dest_path" 2>/dev/null; then
          log_info "Copied directory $ignored_path/"
          copied_count=$((copied_count + 1))
        else
          log_warn "Failed to copy directory $ignored_path/"
        fi
      fi
    else
      if cp "$ignored_path" "$dest_path" 2>/dev/null; then
        log_info "Copied $ignored_path"
        copied_count=$((copied_count + 1))
      else
        log_warn "Failed to copy $ignored_path"
      fi
    fi
  done <<EOF
$paths_to_copy
EOF

  cd "$old_pwd" || return 1

  if [ "$copied_count" -gt 0 ]; then
    log_info "Copied $copied_count ignored file(s)/directorie(s)"
  fi

  return 0
}
