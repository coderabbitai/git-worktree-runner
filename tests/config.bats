#!/usr/bin/env bats
# Tests for lib/config.sh — key mapping, cfg_list helpers, formatting
load test_helper

setup() {
  source "$PROJECT_ROOT/lib/config.sh"
}

# ── Key mapping ──────────────────────────────────────────────────────────────

@test "cfg_map_to_file_key maps gtr.copy.include to copy.include" {
  result=$(cfg_map_to_file_key "gtr.copy.include")
  [ "$result" = "copy.include" ]
}

@test "cfg_map_to_file_key maps gtr.editor.default to defaults.editor" {
  result=$(cfg_map_to_file_key "gtr.editor.default")
  [ "$result" = "defaults.editor" ]
}

@test "cfg_map_to_file_key returns empty for unknown key" {
  result=$(cfg_map_to_file_key "gtr.nonexistent")
  [ -z "$result" ]
}

@test "cfg_map_from_file_key maps copy.include to gtr.copy.include" {
  result=$(cfg_map_from_file_key "copy.include")
  [ "$result" = "gtr.copy.include" ]
}

@test "cfg_map_from_file_key maps defaults.editor to gtr.editor.default" {
  result=$(cfg_map_from_file_key "defaults.editor")
  [ "$result" = "gtr.editor.default" ]
}

@test "cfg_map_from_file_key passes through gtr.* keys" {
  result=$(cfg_map_from_file_key "gtr.copy.include")
  [ "$result" = "gtr.copy.include" ]
}

@test "cfg_map_from_file_key returns empty for unknown non-gtr key" {
  result=$(cfg_map_from_file_key "totally.unknown")
  [ -z "$result" ]
}

@test "round-trip: all _CFG_KEY_MAP entries are bidirectional" {
  for pair in "${_CFG_KEY_MAP[@]}"; do
    local gtr_key="${pair%%|*}"
    local file_key="${pair#*|}"

    local mapped_file
    mapped_file=$(cfg_map_to_file_key "$gtr_key")
    [ "$mapped_file" = "$file_key" ]

    local mapped_gtr
    mapped_gtr=$(cfg_map_from_file_key "$file_key")
    [ "$mapped_gtr" = "$gtr_key" ]
  done
}

# ── Known key detection ──────────────────────────────────────────────────────

@test "_cfg_is_known_key returns 0 for gtr.copy.include" {
  _cfg_is_known_key "gtr.copy.include"
}

@test "_cfg_is_known_key returns 0 for gtr.hook.postCd" {
  _cfg_is_known_key "gtr.hook.postCd"
}

@test "_cfg_is_known_key returns 1 for unknown key" {
  ! _cfg_is_known_key "gtr.nonexistent"
}

# ── cfg_list deduplication ───────────────────────────────────────────────────

@test "_cfg_list_add_entry adds entry to result" {
  _cfg_list_seen=""
  _cfg_list_result=""
  _cfg_list_add_entry "local" "gtr.editor.default" "vscode"
  [[ "$_cfg_list_result" == *"gtr.editor.default"* ]]
  [[ "$_cfg_list_result" == *"vscode"* ]]
  [[ "$_cfg_list_result" == *"local"* ]]
}

@test "_cfg_list_add_entry deduplicates same key+value" {
  _cfg_list_seen=""
  _cfg_list_result=""
  _cfg_list_add_entry "local" "gtr.editor.default" "vscode"
  _cfg_list_add_entry "global" "gtr.editor.default" "vscode"
  # Should only appear once (local takes priority)
  local count
  count=$(printf '%s' "$_cfg_list_result" | grep -c "gtr.editor.default" || true)
  [ "$count" -eq 1 ]
}

@test "_cfg_list_add_entry allows same key with different values" {
  _cfg_list_seen=""
  _cfg_list_result=""
  _cfg_list_add_entry "local" "gtr.copy.include" ".env*"
  _cfg_list_add_entry "local" "gtr.copy.include" "*.config.js"
  local count
  count=$(printf '%s' "$_cfg_list_result" | grep -c "gtr.copy.include" || true)
  [ "$count" -eq 2 ]
}

# ── cfg_list formatting ─────────────────────────────────────────────────────

@test "_cfg_list_format shows message for empty output" {
  result=$(_cfg_list_format "")
  [ "$result" = "No gtr configuration found" ]
}

@test "_cfg_list_format formats scoped output (space-delimited)" {
  result=$(_cfg_list_format "gtr.editor.default vscode")
  [[ "$result" == *"gtr.editor.default"* ]]
  [[ "$result" == *"= vscode"* ]]
}

@test "_cfg_list_format formats auto output (unit-separator-delimited)" {
  local us=$'\x1f'
  local input="gtr.editor.default${us}vscode${us}local"
  result=$(_cfg_list_format "$input")
  [[ "$result" == *"gtr.editor.default"* ]]
  [[ "$result" == *"vscode"* ]]
  [[ "$result" == *"[local]"* ]]
}
