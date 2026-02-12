#!/usr/bin/env bash

# Adapter command (list available adapters)
cmd_adapter() {
  echo "Available Adapters"
  echo ""

  # Editor adapters
  echo "Editor Adapters:"
  echo ""
  printf "%-15s %-15s %s\n" "NAME" "STATUS" "NOTES"
  printf "%-15s %-15s %s\n" "---------------" "---------------" "-----"

  # Registry-defined editor adapters
  local listed_editors=" " line adapter_name
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    adapter_name="${line%%|*}"
    listed_editors="$listed_editors$adapter_name "
    _load_from_editor_registry "$line"
    if editor_can_open 2>/dev/null; then
      printf "%-15s %-15s %s\n" "$adapter_name" "[ready]" ""
    else
      printf "%-15s %-15s %s\n" "$adapter_name" "[missing]" "Not found in PATH"
    fi
  done <<EOF
$_EDITOR_REGISTRY
EOF

  # File-only editor adapters (custom ones not in registry)
  local adapter_file
  for adapter_file in "$GTR_DIR"/adapters/editor/*.sh; do
    [ -f "$adapter_file" ] || continue
    adapter_name=$(basename "$adapter_file" .sh)
    case "$listed_editors" in *" $adapter_name "*) continue ;; esac
    # shellcheck disable=SC1090
    . "$adapter_file"
    if editor_can_open 2>/dev/null; then
      printf "%-15s %-15s %s\n" "$adapter_name" "[ready]" ""
    else
      printf "%-15s %-15s %s\n" "$adapter_name" "[missing]" "Not found in PATH"
    fi
  done

  echo ""
  echo ""
  echo "AI Tool Adapters:"
  echo ""
  printf "%-15s %-15s %s\n" "NAME" "STATUS" "NOTES"
  printf "%-15s %-15s %s\n" "---------------" "---------------" "-----"

  # Registry-defined AI adapters
  local listed_ais=" "
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    adapter_name="${line%%|*}"
    listed_ais="$listed_ais$adapter_name "
    _load_from_ai_registry "$line"
    if ai_can_start 2>/dev/null; then
      printf "%-15s %-15s %s\n" "$adapter_name" "[ready]" ""
    else
      printf "%-15s %-15s %s\n" "$adapter_name" "[missing]" "Not found in PATH"
    fi
  done <<EOF
$_AI_REGISTRY
EOF

  # File-only AI adapters (custom ones not in registry)
  for adapter_file in "$GTR_DIR"/adapters/ai/*.sh; do
    [ -f "$adapter_file" ] || continue
    adapter_name=$(basename "$adapter_file" .sh)
    case "$listed_ais" in *" $adapter_name "*) continue ;; esac
    # shellcheck disable=SC1090
    . "$adapter_file"
    if ai_can_start 2>/dev/null; then
      printf "%-15s %-15s %s\n" "$adapter_name" "[ready]" ""
    else
      printf "%-15s %-15s %s\n" "$adapter_name" "[missing]" "Not found in PATH"
    fi
  done

  echo ""
  echo ""
  echo "Tip: Set defaults with:"
  echo "   git gtr config set gtr.editor.default <name>"
  echo "   git gtr config set gtr.ai.default <name>"
}