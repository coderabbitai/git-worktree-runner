# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`git gtr` (Git Worktree Runner) is a cross-platform CLI tool written in Bash that simplifies git worktree management. It wraps `git worktree` with quality-of-life features like editor integration, AI tool support, file copying, and hooks. Installed as a git subcommand: `git gtr <command>`.

## Invocation

- **Production**: `git gtr <command>` (git subcommand via `bin/git-gtr` wrapper)
- **Development/testing**: `./bin/gtr <command>` (direct execution)
- **User-facing docs**: Always reference `git gtr`, never `./bin/gtr`

## CRITICAL: No Automated Tests

This project has **no test suite**. All testing is manual. After any change, run the relevant smoke tests:

```bash
./bin/gtr new test-feature          # Create worktree
./bin/gtr new feature/auth          # Slash branch → folder "feature-auth"
./bin/gtr list                      # Table output
./bin/gtr go test-feature           # Print path
./bin/gtr run test-feature git status
./bin/gtr rm test-feature           # Clean up
```

For exhaustive testing (hooks, copy patterns, adapters, `--force`, `--from-current`, etc.), see the full checklist in CONTRIBUTING.md or `.github/instructions/testing.instructions.md`.

**Tip**: Use a disposable repo for testing to avoid polluting your working tree:

```bash
mkdir -p /tmp/gtr-test && cd /tmp/gtr-test && git init && git commit --allow-empty -m "init"
/path/to/git-worktree-runner/bin/gtr new test-feature
```

## Architecture

### Binary Structure

- `bin/git-gtr` — Thin wrapper enabling `git gtr` subcommand invocation
- `bin/gtr` — Entry point (~105 lines): sources libraries and commands, contains `main()` dispatcher

### Module Structure

| File               | Purpose                                                                                                     |
| ------------------ | ----------------------------------------------------------------------------------------------------------- |
| `lib/core.sh`      | Worktree CRUD: `create_worktree`, `remove_worktree`, `list_worktrees`, `resolve_target`, `resolve_base_dir` |
| `lib/config.sh`    | Git config wrapper with precedence: `cfg_get`, `cfg_default`, `cfg_get_all`                                 |
| `lib/copy.sh`      | File/directory copying with glob patterns: `copy_patterns`, `copy_directories`                              |
| `lib/hooks.sh`     | Hook execution: `run_hooks_in` for postCreate/preRemove/postRemove                                          |
| `lib/ui.sh`        | Logging (`log_error`, `log_info`, `log_warn`), prompts, formatting                                          |
| `lib/platform.sh`  | OS detection, GUI helpers                                                                                   |
| `lib/adapters.sh`  | Adapter registry, builder functions, generic fallbacks, loader functions                                    |
| `lib/commands/*.sh` | One file per subcommand: `cmd_create`, `cmd_remove`, etc. (16 files)                                       |

### Adapters

Most adapters are defined declaratively in the **adapter registry** (`lib/adapters.sh`) using pipe-delimited entries. Custom adapters that need special logic remain as override files in `adapters/editor/` and `adapters/ai/`.

**Registry-defined adapters**: atom, cursor, emacs, idea, nvim, pycharm, sublime, vim, vscode, webstorm, zed (editors) and aider, auggie, codex, continue, copilot, gemini, opencode (AI).

**Custom adapter files**: `adapters/editor/nano.sh`, `adapters/ai/claude.sh`, `adapters/ai/cursor.sh` — these implement `editor_can_open()`/`editor_open()` or `ai_can_start()`/`ai_start()` directly.

**Loading order**: file override → registry → generic PATH fallback. `GTR_EDITOR_CMD` / `GTR_AI_CMD` env vars allow custom tools without adapters.

### Command Flow

```
bin/gtr main() → case statement → cmd_*() handler → lib/*.sh functions → adapters (if needed)
```

Key dispatch: `new`→`cmd_create`, `rm`→`cmd_remove`, `mv|rename`→`cmd_rename`, `go`→`cmd_go`, `run`→`cmd_run`, `editor`→`cmd_editor`, `ai`→`cmd_ai`, `copy`→`cmd_copy`, `ls|list`→`cmd_list`, `clean`→`cmd_clean`, `init`→`cmd_init`, `config`→`cmd_config`, `completion`→`cmd_completion`, `doctor`→`cmd_doctor`, `adapter`→`cmd_adapter`.

**Example: `git gtr new my-feature`**

```
cmd_create() → resolve_base_dir() → create_worktree() → copy_patterns() → copy_directories() → run_hooks_in()
```

**Example: `git gtr editor my-feature`**

```
cmd_editor() → resolve_target() → load_editor_adapter() → editor_open()
```

## Key Implementation Details

**Branch Name Sanitization**: Slashes and special chars become hyphens. `feature/user-auth` → folder `feature-user-auth`.

**Special ID `1`**: Always refers to the main repository in `go`, `editor`, `ai`, `run`, etc.

**`resolve_target()`** (lib/core.sh): Resolves branch names/IDs to worktree paths. Checks: special ID → current branch in main → sanitized path match → full scan. Returns TSV: `is_main\tpath\tbranch`.

**`resolve_base_dir()`** (lib/core.sh): Determines worktree storage location. Empty → `<repo>-worktrees` sibling; relative → from repo root; absolute → as-is; tilde → expanded.

**`create_worktree()`** (lib/core.sh): Intelligent track mode — tries remote first, then local branch, then creates new.

**Config Precedence** (`cfg_default` in lib/config.sh): local git config → `.gtrconfig` file → global/system git config → env vars → fallback. Multi-value keys (`gtr.copy.include`, hooks, etc.) are merged and deduplicated via `cfg_get_all()`.

**`.gtrconfig`**: Team-shared config using gitconfig syntax, parsed via `git config -f`. Keys map differently from git config (e.g., `gtr.copy.include` → `copy.include`, `gtr.hook.postCreate` → `hooks.postCreate`). See the .gtrconfig Key Mapping table in README or `docs/configuration.md`.

**`init` command**: Outputs shell functions for `gtr cd <branch>` navigation. Users add `eval "$(git gtr init bash)"` to their shell rc file.

**`clean --merged`**: Removes worktrees whose PRs/MRs are merged. Auto-detects GitHub (`gh`) or GitLab (`glab`) from the `origin` remote URL. Override with `gtr.provider` config for self-hosted instances.

## Common Development Tasks

### Adding a New Command

1. Create `lib/commands/<name>.sh` with `cmd_<name>()` function
2. Add case entry in `main()` dispatcher in `bin/gtr`
3. Add help text in `lib/commands/help.sh`
4. Update all three completion files: `completions/gtr.bash`, `completions/_git-gtr`, `completions/git-gtr.fish`
5. Update README.md

### Adding an Adapter

**Standard adapters** (just a command name + error message): Add an entry to `_EDITOR_REGISTRY` or `_AI_REGISTRY` in `lib/adapters.sh`. Then update: help text in `lib/commands/help.sh`, all three completions, README.md.

**Custom adapters** (special logic needed): Create `adapters/{editor,ai}/<name>.sh` implementing the two required functions (see `adapters/ai/claude.sh` for an example). File-based adapters take priority over registry entries.

### Updating the Version

Update `GTR_VERSION` in `bin/gtr` (line 8).

### Shell Completion Updates

When adding commands or flags, update all three files:

- `completions/gtr.bash` (Bash)
- `completions/_git-gtr` (Zsh)
- `completions/git-gtr.fish` (Fish)

## Code Style

- Shebang: `#!/usr/bin/env bash`
- `snake_case` functions/variables, `UPPER_CASE` constants
- 2-space indent, no tabs
- Always quote variables: `"$var"`
- `local` for function-scoped variables
- Target Bash 3.2+ (macOS default); Git 2.17+ minimum
- Git 2.22+ commands need fallbacks (e.g., `git branch --show-current` → `git rev-parse --abbrev-ref HEAD`)

## Configuration Reference

All config uses `gtr.*` prefix via `git config`. Key settings:

- `gtr.worktrees.dir` — Base directory (default: `<repo-name>-worktrees` sibling)
- `gtr.worktrees.prefix` — Folder prefix (default: `""`)
- `gtr.editor.default` / `gtr.ai.default` — Default editor/AI tool
- `gtr.copy.include` / `gtr.copy.exclude` — File glob patterns (multi-valued, use `--add`)
- `gtr.copy.includeDirs` / `gtr.copy.excludeDirs` — Directory patterns (multi-valued)
- `gtr.hook.postCreate` / `gtr.hook.preRemove` / `gtr.hook.postRemove` — Hook commands (multi-valued)

Hook env vars: `REPO_ROOT`, `WORKTREE_PATH`, `BRANCH`. preRemove hooks run with cwd in worktree; failure aborts removal unless `--force`.

## Debugging

```bash
bash -x ./bin/gtr <command>          # Full trace
declare -f function_name             # Check function definition
echo "Debug: var=$var" >&2           # Inspect variable
./bin/gtr doctor                     # Health check
./bin/gtr adapter                    # List available adapters
```

## Related Documentation

- `CONTRIBUTING.md` — Full contribution guidelines, coding standards, manual testing checklist
- `.github/copilot-instructions.md` — Condensed AI agent guide
- `.github/instructions/*.instructions.md` — File-pattern-specific guidance (testing, shell conventions, lib modifications, adapter contracts, completions)
- `docs/configuration.md` — Complete configuration reference
- `docs/advanced-usage.md` — Advanced workflows
