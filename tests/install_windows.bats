#!/usr/bin/env bats
# Exercise the printed Git Bash instructions without touching a real installation.
# uname is stubbed for installer dispatch; these are not native Windows tests.
# Each BATS test has its own setup and subshell.
# shellcheck disable=SC2030,SC2031

load test_helper

setup() {
  INSTALL_FIXTURE=$(cd "$(mktemp -d)" && pwd -P)
  INSTALL_CHECKOUT="$INSTALL_FIXTURE/checkout"
  mkdir -p "$INSTALL_FIXTURE/mock-bin"
  cat > "$INSTALL_FIXTURE/mock-bin/uname" <<'SCRIPT'
#!/usr/bin/env bash
printf '%s\n' "$INSTALL_TEST_PLATFORM"
SCRIPT
  chmod +x "$INSTALL_FIXTURE/mock-bin/uname"
  export PATH="$INSTALL_FIXTURE/mock-bin:$PATH"
  export INSTALL_TEST_PLATFORM=MINGW64_NT-10.0
  export GIT_CONFIG_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$INSTALL_FIXTURE/global.gitconfig"
  : > "$GIT_CONFIG_GLOBAL"
  unset GTR_DIR
  cd "$INSTALL_FIXTURE" || return 1
}

teardown() {
  cd "$PROJECT_ROOT" || return 1
  rm -rf "$INSTALL_FIXTURE"
}

copy_installation() {
  mkdir -p "$INSTALL_CHECKOUT"
  cp "$PROJECT_ROOT/install.sh" "$INSTALL_CHECKOUT/"
  cp -R "$PROJECT_ROOT/bin" "$PROJECT_ROOT/lib" "$PROJECT_ROOT/adapters" \
    "$PROJECT_ROOT/completions" "$PROJECT_ROOT/templates" "$INSTALL_CHECKOUT/"
}

read_path_instruction() {
  run bash "$INSTALL_CHECKOUT/install.sh"
  [ "$status" -eq 0 ]
  PATH_INSTRUCTION=$(printf '%s\n' "$output" | sed -n 's/^    \(export PATH=.*\)/\1/p')
  [ -n "$PATH_INSTRUCTION" ]
}

assert_installed_command() {
  run bash -c '
    set -e
    unset GTR_DIR
    eval "$1"
    [ "$(command -v git-gtr)" = "$2/bin/git-gtr" ]
    git gtr version
    git gtr help
  ' -- "$PATH_INSTRUCTION" "$INSTALL_CHECKOUT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"git gtr version "* ]]
  [[ "$output" == *"QUICK START"* ]]
}

@test "Windows installer recommends a working full checkout for Git Bash, MSYS and Cygwin" {
  copy_installation
  local platform
  for platform in MINGW64_NT-10.0 MSYS_NT-10.0 CYGWIN_NT-10.0; do
    export INSTALL_TEST_PLATFORM="$platform"
    read_path_instruction
    [[ "$output" != *'cp '* ]] || return 1
    [[ "$output" != *'Copy the script directly'* ]] || return 1
    assert_installed_command
  done
}

@test "Windows PATH instruction preserves spaces and shell metacharacters literally" {
  INSTALL_CHECKOUT="$INSTALL_FIXTURE/"$'checkout with spaces \' " $dollar $(touch injected) `touch injected` & ; (x)'
  copy_installation
  read_path_instruction
  assert_installed_command
  [ ! -e "$INSTALL_FIXTURE/injected" ]
}

@test "Windows PATH installation preserves command arguments and exit status" {
  copy_installation
  read_path_instruction
  git init --quiet "$INSTALL_FIXTURE/repo"
  git -C "$INSTALL_FIXTURE/repo" -c user.name=Test -c user.email=test@example.com \
    commit --allow-empty --quiet -m init
  cd "$INSTALL_FIXTURE/repo"
  # shellcheck disable=SC2016 # These arguments must stay literal.
  local -a args=('' 'two words' '*' '$literal' '$(touch injected)' 'a;b' '"quoted"' "it's literal" '--flag')
  local expected
  expected=$(printf '<%s>\n' "${args[@]}")
  run bash -c '
    set -e
    unset GTR_DIR
    eval "$1"
    shift
    git gtr run 1 -- printf "<%s>\n" "$@" 2>run.stderr
  ' -- "$PATH_INSTRUCTION" "${args[@]}"
  [ "$status" -eq 0 ]
  [ "$output" = "$expected" ]
  [ ! -e injected ]

  run bash -c '
    unset GTR_DIR
    eval "$1"
    git gtr run 1 -- bash -c "exit 23" 2>run.stderr
  ' -- "$PATH_INSTRUCTION"
  [ "$status" -eq 23 ]
}

@test "Windows installer verifies a checkout already on PATH" {
  copy_installation
  run env PATH="$INSTALL_CHECKOUT/bin:$PATH" bash "$INSTALL_CHECKOUT/install.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already in your PATH!"* ]]
  [[ "$output" == *"Installation verified: git gtr version "* ]]
}

@test "Windows installer makes the checkout entrypoint executable" {
  copy_installation
  chmod -x "$INSTALL_CHECKOUT/bin/git-gtr"
  read_path_instruction
  [ -x "$INSTALL_CHECKOUT/bin/git-gtr" ]
  assert_installed_command
}
