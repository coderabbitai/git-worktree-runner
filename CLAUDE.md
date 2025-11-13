# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`gtr` (Git Worktree Runner) is a cross-platform CLI tool written in Bash that simplifies git worktree management. It wraps `git worktree` with quality-of-life features like editor integration, AI tool support, file copying, and hooks.

## Development Commands

### Testing Changes Locally

Since this is a Bash script project without a traditional build system, test changes by running the script directly:

```bash
# Run gtr from the repo (no installation needed)
./bin/gtr <command>

# Or use the full path
/path/to/git-worktree-runner/bin/gtr <command>

# Test in a different git repository
cd ~/some-test-repo
/path/to/git-worktree-runner/bin/gtr new test-branch
```

### CRITICAL: No Automated Tests

**This project has NO automated test suite.** All testing is manual. When making changes:

1. You MUST manually test all affected functionality
2. Follow the manual testing checklist below
3. Test on multiple platforms if possible (macOS, Linux, Windows Git Bash)
4. There are no unit tests to run - do not look for test files

### Manual Testing Workflow

Test changes using this comprehensive checklist (from CONTRIBUTING.md):

```bash
# Create worktree with simple branch name
./bin/gtr new test-feature
# Expected: Creates folder "test-feature"

# Create worktree with branch containing slashes
./bin/gtr new feature/auth
# Expected: Creates folder "feature-auth" (sanitized)

# Create worktree from remote branch (if exists)
./bin/gtr new existing-remote-branch
# Expected: Checks out remote tracking branch

# Create worktree from local branch (if exists)
./bin/gtr new existing-local-branch
# Expected: Creates worktree from local branch

# Create worktree with new branch
./bin/gtr new brand-new-feature
# Expected: Creates new branch and worktree

# Test --force and --name flags together
./bin/gtr new test-feature --force --name backend
# Expected: Creates folder "test-feature-backend" on same branch

# Open in editor (if testing adapters)
./bin/gtr config set gtr.editor.default cursor
./bin/gtr open test-feature
# Expected: Opens Cursor at worktree path

# Run AI tool (if testing adapters)
./bin/gtr config set gtr.ai.default claude
./bin/gtr ai test-feature
# Expected: Starts Claude Code in worktree directory

# Remove worktree by branch name
./bin/gtr rm test-feature
# Expected: Removes worktree folder

# List worktrees
./bin/gtr list
# Expected: Table format with branches and paths
./bin/gtr list --porcelain
# Expected: Machine-readable tab-separated output

# Test configuration commands
./bin/gtr config set gtr.editor.default cursor
./bin/gtr config get gtr.editor.default
# Expected: Returns "cursor"
./bin/gtr config set gtr.editor.default vscode --global
./bin/gtr config unset gtr.editor.default

# Test shell completions with tab completion
gtr new <TAB>
gtr open <TAB>
# Expected: Shows available branches/worktrees

# Test gtr go for main repo and worktrees
cd "$(./bin/gtr go 1)"
# Expected: Navigates to repo root
cd "$(./bin/gtr go test-feature)"
# Expected: Navigates to worktree

# Test copy patterns with include/exclude
git config --add gtr.copy.include "**/.env.example"
git config --add gtr.copy.exclude "**/.env"
./bin/gtr new test-copy
# Expected: Copies .env.example but not .env

# Test post-create and post-remove hooks
git config --add gtr.hook.postCreate "echo 'Created!' > /tmp/gtr-test"
./bin/gtr new test-hooks
# Expected: Creates /tmp/gtr-test file
git config --add gtr.hook.postRemove "echo 'Removed!' > /tmp/gtr-removed"
./bin/gtr rm test-hooks
# Expected: Creates /tmp/gtr-removed file
```

### Debugging Bash Scripts

When debugging issues:

```bash
# Enable tracing to see each command executed
bash -x ./bin/gtr <command>

# Or add 'set -x' temporarily to specific functions
# In lib/core.sh or other files:
set -x  # Enable tracing
# ... code to debug ...
set +x  # Disable tracing

# Check if functions are defined
declare -f function_name

# Check variable values
echo "Debug: var=$var" >&2
```

### Verifying Installation

```bash
# Verify git is available
git --version

# Check gtr setup
./bin/gtr doctor

# List available adapters
./bin/gtr adapter
```

## Architecture

### Module Structure

- **`bin/gtr`**: Main executable and command dispatcher. Sources all lib files and routes commands to appropriate handlers.
- **`lib/core.sh`**: Git worktree operations (create, remove, list). Contains core business logic for worktree management.
- **`lib/config.sh`**: Configuration management via `git config` wrapper functions. Supports local/global/system scopes.
- **`lib/platform.sh`**: OS-specific utilities for macOS/Linux/Windows.
- **`lib/ui.sh`**: User interface helpers (logging, prompts, formatting).
- **`lib/copy.sh`**: File copying logic with glob pattern support.
- **`lib/hooks.sh`**: Hook execution system for post-create/post-remove actions.
- **`adapters/editor/*.sh`**: Editor adapters (must implement `editor_can_open` and `editor_open`).
- **`adapters/ai/*.sh`**: AI tool adapters (must implement `ai_can_start` and `ai_start`).
- **`completions/`**: Shell completions for Bash, Zsh, and Fish.
- **`templates/`**: Example configuration scripts (setup-example.sh, run_services.example.sh) for users to customize.

### Key Design Patterns

**Repository Scoping**: Each git repository manages its own independent worktrees. Commands must be run from within a git repo. Worktree locations are resolved relative to the repository root.

**Branch Name Mapping**: Branch names are sanitized to valid folder names (slashes and special chars → hyphens). For example, `feature/user-auth` becomes folder `feature-user-auth`.

**Special ID '1'**: The main repository is always accessible via ID `1` in commands (e.g., `gtr go 1`, `gtr open 1`).

**Configuration Storage**: All configuration is stored via `git config` (local, global, or system). No custom config files. This makes settings portable and follows git conventions.

**Adapter Pattern**: Editor and AI tool integrations follow a simple adapter pattern with two required functions per adapter type:

- Editor adapters: `editor_can_open()` (check availability) and `editor_open(path)` (open editor)
- AI adapters: `ai_can_start()` (check availability) and `ai_start(path, args...)` (start tool)
- Return code 0 indicates success/availability; non-zero indicates failure
- See "Adapter Contract" in Important Implementation Details for full specifications

### Command Flow

Understanding how commands are dispatched through the system:

1. **Entry Point** (`bin/gtr:32-79`): Main dispatcher receives command and routes to appropriate handler
2. **Command Handlers** (`bin/gtr`): Each `cmd_*` function handles a specific command (e.g., `cmd_create`, `cmd_open`, `cmd_ai`)
3. **Library Functions** (`lib/*.sh`): Command handlers call reusable functions from library modules
4. **Adapters** (`adapters/*`): Dynamically loaded when needed via `load_editor_adapter` or `load_ai_adapter`

**Example flow for `gtr new my-feature`:**

```
bin/gtr main()
  → cmd_create()
  → resolve_base_dir() [lib/core.sh]
  → create_worktree() [lib/core.sh]
  → copy_patterns() [lib/copy.sh]
  → run_hooks_in() [lib/hooks.sh]
```

**Example flow for `gtr open my-feature`:**

```
bin/gtr main()
  → cmd_open()
  → resolve_target() [lib/core.sh]
  → load_editor_adapter()
  → editor_open() [adapters/editor/*.sh]
```

## Design Principles

When making changes, follow these core principles (from CONTRIBUTING.md):

1. **Cross-platform first** - Code must work on macOS, Linux, and Windows Git Bash
2. **No external dependencies** - Only require git and basic POSIX shell utilities
3. **Configuration over flags** - Users set defaults once, then use simple commands
4. **Fail safely** - Validate inputs, check return codes, provide clear error messages
5. **Stay modular** - Keep functions small, focused, and reusable
6. **User-friendly** - Prioritize good UX with clear output and helpful error messages

## Common Development Tasks

### Updating the Version Number

When releasing a new version, update the version constant in `bin/gtr`:

```bash
# bin/gtr line 8
GTR_VERSION="1.0.0"  # Update this
```

The version is displayed with `gtr version` and `gtr --version`.

### Adding a New Editor Adapter

Create `adapters/editor/<name>.sh` with these two functions:

```bash
#!/usr/bin/env bash
# EditorName adapter

editor_can_open() {
  command -v editor-cli >/dev/null 2>&1
}

editor_open() {
  local path="$1"

  if ! editor_can_open; then
    log_error "EditorName not found. Install from https://..."
    return 1
  fi

  editor-cli "$path"
}
```

Also update:

- README.md with installation/setup instructions
- Completions in `completions/` to include the new editor name (all three: bash, zsh, fish)
- The help text in `bin/gtr` - search for "Available editors:" in the `cmd_help` function and `load_editor_adapter` function

### Adding a New AI Tool Adapter

Create `adapters/ai/<name>.sh` with these two functions:

```bash
#!/usr/bin/env bash
# ToolName AI adapter

ai_can_start() {
  command -v tool-cli >/dev/null 2>&1
}

ai_start() {
  local path="$1"
  shift

  if ! ai_can_start; then
    log_error "ToolName not found. Install with: ..."
    return 1
  fi

  (cd "$path" && tool-cli "$@")
}
```

Also update:

- README.md with installation instructions and use cases
- Completions to include the new AI tool name (all three: bash, zsh, fish)
- The help text in `bin/gtr` - search for "Available AI tools:" in the `cmd_help` function and `load_ai_adapter` function

### Modifying Core Functionality

When changing `lib/*.sh` files:

- Maintain backwards compatibility with existing configurations
- Follow POSIX-compatible Bash patterns (target Bash 3.2+)
- Use `set -e` for error handling
- Quote all variables: `"$var"`
- Use `local` for function-scoped variables
- Provide clear error messages via `log_error` and `log_info` from `lib/ui.sh`
- Test on multiple platforms (macOS, Linux, Windows Git Bash)

### Shell Completion Updates

When adding new commands or flags, update all three completion files:

- `completions/gtr.bash` (Bash)
- `completions/_gtr` (Zsh)
- `completions/gtr.fish` (Fish)

### Git Version Compatibility

The codebase includes fallbacks for different Git versions:

- **Git 2.22+**: Uses modern commands like `git branch --show-current`
- **Git 2.5-2.21**: Falls back to `git rev-parse --abbrev-ref HEAD`
- **Minimum**: Git 2.5+ (for basic `git worktree` support)

When using Git commands, check if fallbacks exist (e.g., in `lib/core.sh:97-100`) or add them for new features.

## Code Style

- **Shebang**: `#!/usr/bin/env bash` (not `/bin/bash` or `/bin/sh`)
- **Functions**: `snake_case` naming
- **Variables**: `snake_case` for local vars, `UPPER_CASE` for constants/env vars
- **Indentation**: 2 spaces (no tabs)
- **Quotes**: Always quote variables and paths
- **Error handling**: Check return codes, use `|| exit 1` or `|| return 1`

## Configuration Reference

All config keys use `gtr.*` prefix and are managed via `git config`:

- `gtr.worktrees.dir`: Base directory for worktrees (default: `<repo-name>-worktrees`)
- `gtr.worktrees.prefix`: Folder prefix for worktrees (default: `""`)
- `gtr.defaultBranch`: Default branch name (default: auto-detect)
- `gtr.editor.default`: Default editor (cursor, vscode, zed, etc.)
- `gtr.ai.default`: Default AI tool (aider, claude, codex, etc.)
- `gtr.copy.include`: Multi-valued glob patterns for files to copy
- `gtr.copy.exclude`: Multi-valued glob patterns for files to exclude
- `gtr.hook.postCreate`: Multi-valued commands to run after creating worktree
- `gtr.hook.postRemove`: Multi-valued commands to run after removing worktree

## Important Implementation Details

**Worktree Path Resolution**: The `resolve_target` function in `lib/core.sh:193-242` handles both branch names and the special ID '1'. It checks in order: special ID, current branch in main repo, sanitized path match, full directory scan. Returns tab-separated format: `is_main\tpath\tbranch`.

**Base Directory Resolution** (v1.1.0+): The `resolve_base_dir` function in `lib/core.sh:30-76` determines where worktrees are stored. Behavior:

- Empty config → `<repo>-worktrees` (sibling directory)
- Relative paths → resolved from **repo root** (e.g., `.worktrees` → `<repo>/.worktrees`)
- Absolute paths → used as-is (e.g., `/tmp/worktrees`)
- Tilde expansion → `~/worktrees` → `$HOME/worktrees`
- Auto-warns if worktrees inside repo without `.gitignore` entry

**Track Mode**: The auto-detect mode in `lib/core.sh:244-350` (`create_worktree` function) intelligently chooses between remote tracking, local branch, or new branch creation based on what exists. It tries remote first, then local, then creates new.

**Configuration Precedence**: The `cfg_default` function in `lib/config.sh:128-146` checks git config first (local > global > system), then environment variables, then fallback values. Use `cfg_get_all` (lib/config.sh:28-51) for multi-valued configs.

**Multi-Value Configuration Pattern**: Some configs support multiple values (`gtr.copy.include`, `gtr.copy.exclude`, `gtr.hook.postCreate`, `gtr.hook.postRemove`). The `cfg_get_all` function merges values from local + global + system and deduplicates. Set with: `git config --add gtr.copy.include "pattern"`.

**Adapter Loading**: Adapters are sourced dynamically when needed (see `load_editor_adapter` at bin/gtr:794-806 and `load_ai_adapter` at bin/gtr:808-820). They must exist in `adapters/editor/` or `adapters/ai/` and define the required functions.

**Adapter Contract**:

- **Editor adapters**: Must implement `editor_can_open()` (returns 0 if available) and `editor_open(path)` (opens editor at path)
- **AI adapters**: Must implement `ai_can_start()` (returns 0 if available) and `ai_start(path, args...)` (starts tool at path with optional args)
- Both should use `log_error` from `lib/ui.sh` for user-facing error messages

## Troubleshooting Development Issues

### Permission Denied Errors

```bash
# If you get "Permission denied" when running ./bin/gtr
chmod +x ./bin/gtr
```

### Symlink Issues

```bash
# If symlink doesn't work, check if /usr/local/bin exists
ls -la /usr/local/bin

# Create it if needed (macOS/Linux)
sudo mkdir -p /usr/local/bin

# Verify symlink
ls -la /usr/local/bin/gtr
```

### Adapter Not Found

```bash
# Check if adapter file exists
ls -la adapters/editor/
ls -la adapters/ai/

# Verify adapter is being sourced correctly
bash -x ./bin/gtr adapter  # Shows which files are being loaded

# Test specific adapter function availability
bash -c 'source adapters/editor/cursor.sh && editor_can_open && echo "Available" || echo "Not found"'
bash -c 'source adapters/ai/claude.sh && ai_can_start && echo "Available" || echo "Not found"'

# Debug adapter loading with trace
bash -x ./bin/gtr open test-feature --editor cursor
# Shows full execution trace including adapter loading
```

### Testing in Other Repos

```bash
# When testing, use a separate test repo to avoid breaking your work
mkdir -p ~/gtr-test-repo
cd ~/gtr-test-repo
git init
git commit --allow-empty -m "Initial commit"

# Now test gtr commands
/path/to/git-worktree-runner/bin/gtr new test-feature
```
