#!/usr/bin/env bash

# Adapter command (list available adapters)

# Print adapter listing for a given type
# Usage: _print_adapter_list <label> <registry> <subdir> <can_func> <load_func>
_print_adapter_list() {
  local label="$1" registry="$2" subdir="$3" can_func="$4" load_func="$5"

  echo "$label:"
  echo ""
  printf "%-15s %-15s %s\n" "NAME" "STATUS" "NOTES"
  printf "%-15s %-15s %s\n" "---------------" "---------------" "-----"

  # Registry-defined adapters
  local listed=" " line adapter_name
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    adapter_name="${line%%|*}"
    listed="$listed$adapter_name "
    "$load_func" "$line"
    if $can_func 2>/dev/null; then
      printf "%-15s %-15s %s\n" "$adapter_name" "[ready]" ""
    else
      printf "%-15s %-15s %s\n" "$adapter_name" "[missing]" "Not found in PATH"
    fi
  done <<EOF
$registry
EOF

  # File-only adapters (custom ones not in registry)
  local adapter_file
  for adapter_file in "$GTR_DIR/adapters/$subdir"/*.sh; do
    [ -f "$adapter_file" ] || continue
    adapter_name=$(basename "$adapter_file" .sh)
    case "$listed" in *" $adapter_name "*) continue ;; esac
    # shellcheck disable=SC1090
    . "$adapter_file"
    if $can_func 2>/dev/null; then
      printf "%-15s %-15s %s\n" "$adapter_name" "[ready]" ""
    else
      printf "%-15s %-15s %s\n" "$adapter_name" "[missing]" "Not found in PATH"
    fi
  done
}

cmd_adapter() {
  parse_args "" "$@"

  echo "Available Adapters"
  echo ""

  _print_adapter_list "Editor Adapters" "$_EDITOR_REGISTRY" "editor" "editor_can_open" "_load_from_editor_registry"

  echo ""
  echo ""

  _print_adapter_list "AI Tool Adapters" "$_AI_REGISTRY" "ai" "ai_can_start" "_load_from_ai_registry"

  echo ""
  echo ""
  echo "Tip: Set defaults with:"
  echo "   git gtr config set gtr.editor.default <name>"
  echo "   git gtr config set gtr.ai.default <name>"
}
