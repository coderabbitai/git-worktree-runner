#!/usr/bin/env bats
# Tests for color support in lib/ui.sh

load test_helper

# Source ui.sh directly (not via test_helper which stubs log functions)
_source_ui() {
  . "$PROJECT_ROOT/lib/ui.sh"
}

# ── _ui_should_color ─────────────────────────────────────────────────────────

@test "_ui_should_color returns 1 when NO_COLOR is set" {
  _source_ui
  NO_COLOR=1 run _ui_should_color 2
  [ "$status" -ne 0 ]
}

@test "_ui_should_color returns 1 when NO_COLOR is empty string (unset wins)" {
  _source_ui
  unset NO_COLOR
  GTR_COLOR=never run _ui_should_color 2
  [ "$status" -ne 0 ]
}

@test "_ui_should_color returns 0 with GTR_COLOR=always" {
  _source_ui
  unset NO_COLOR
  GTR_COLOR=always run _ui_should_color 2
  [ "$status" -eq 0 ]
}

@test "_ui_should_color returns 1 with GTR_COLOR=never" {
  _source_ui
  unset NO_COLOR
  GTR_COLOR=never run _ui_should_color 2
  [ "$status" -ne 0 ]
}

# ── Color variable state ─────────────────────────────────────────────────────

@test "color variables are empty when NO_COLOR is set" {
  NO_COLOR=1 _source_ui
  [ -z "$_UI_GREEN" ]
  [ -z "$_UI_RED" ]
  [ -z "$_UI_YELLOW" ]
  [ -z "$_UI_CYAN" ]
  [ -z "$_UI_BOLD" ]
  [ -z "$_UI_RESET" ]
}

@test "color variables are set with GTR_COLOR=always" {
  unset NO_COLOR
  GTR_COLOR=always _source_ui
  [ -n "$_UI_GREEN" ]
  [ -n "$_UI_RED" ]
  [ -n "$_UI_RESET" ]
}

@test "_ui_disable_color clears all variables" {
  unset NO_COLOR
  GTR_COLOR=always _source_ui
  _ui_disable_color
  [ -z "$_UI_GREEN" ]
  [ -z "$_UI_RED" ]
  [ -z "$_UI_YELLOW" ]
  [ -z "$_UI_RESET" ]
  [ -z "$_UI_BOLD_STDOUT" ]
}

@test "_ui_enable_color sets all variables" {
  NO_COLOR=1 _source_ui
  [ -z "$_UI_GREEN" ]
  _ui_enable_color
  [ -n "$_UI_GREEN" ]
  [ -n "$_UI_RED" ]
  [ -n "$_UI_RESET" ]
  [ -n "$_UI_BOLD_STDOUT" ]
}

# ── Log output format ────────────────────────────────────────────────────────

@test "log_info output contains no ANSI when NO_COLOR is set" {
  NO_COLOR=1 _source_ui
  local output
  output=$(log_info "test message" 2>&1)
  [[ "$output" != *$'\033'* ]]
  [[ "$output" == *"[OK]"* ]]
  [[ "$output" == *"test message"* ]]
}

@test "log_error output contains no ANSI when NO_COLOR is set" {
  NO_COLOR=1 _source_ui
  local output
  output=$(log_error "bad thing" 2>&1)
  [[ "$output" != *$'\033'* ]]
  [[ "$output" == *"[x]"* ]]
  [[ "$output" == *"bad thing"* ]]
}

@test "log_warn output contains no ANSI when NO_COLOR is set" {
  NO_COLOR=1 _source_ui
  local output
  output=$(log_warn "caution" 2>&1)
  [[ "$output" != *$'\033'* ]]
  [[ "$output" == *"[!]"* ]]
}

@test "log_step output contains no ANSI when NO_COLOR is set" {
  NO_COLOR=1 _source_ui
  local output
  output=$(log_step "doing thing" 2>&1)
  [[ "$output" != *$'\033'* ]]
  [[ "$output" == *"==>"* ]]
}

@test "log_info output contains ANSI when GTR_COLOR=always" {
  unset NO_COLOR
  GTR_COLOR=always _source_ui
  local output
  output=$(log_info "test message" 2>&1)
  [[ "$output" == *$'\033['* ]]
  [[ "$output" == *"[OK]"* ]]
}
