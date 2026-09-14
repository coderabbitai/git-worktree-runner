# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`git gtr` (Git Worktree Runner) is a cross-platform CLI tool written in Bash that simplifies git worktree management. It wraps `git worktree` with quality-of-life features like editor integration, AI tool support, file copying, and hooks. Installed as a git subcommand: `git gtr <command>`.

## Invocation

- **Production**: `git gtr <command>` (git subcommand via `bin/git-gtr` wrapper)
- **Development/testing**: `./bin/gtr <command>` (direct execution)
- **User-facing docs**: Always reference `git gtr`, never `./bin/gtr`

## Testing

This project uses **BATS tests** for core functions and **manual smoke tests** for end-to-end workflows. CI runs ShellCheck + BATS automatically on PRs (`.github/workflows/lint.yml`).

1. Run automated tests: `bats tests/`
2. Run a single test file: `bats tests/config.bats`
3. Run a single test by name: `bats tests/config.bats --filter "cfg_map_to_file_key"`
4. Run relevant manual smoke tests:

```bash
./bin/gtr new test-feature          # Create worktree
./bin/gtr new feature/auth          # Slash branch → folder "feature-auth"
./bin/gtr list                      # Table output
./bin/gtr go test-feature           # Print path
./bin/gtr run test-feature git status
./bin/gtr rm test-feature           # Clean up
```

For exhaustive manual testing (hooks, copy patterns, adapters, `--force`, `--from-current`, etc.), see the full checklist in CONTRIBUTING.md or `.github/instructions/testing.instructions.md`.

**Test files** (all in `tests/`): one `cmd_*.bats` file per command (`cmd_clean`, `cmd_config`, `cmd_copy`, `cmd_create_integration`, `cmd_go`, `cmd_help`, `cmd_list`, `cmd_pr`, `cmd_remove`, `cmd_rename`, `cmd_run`, `cmd_trust`), library tests (`adapters`, `completion`, `config`, `copy_safety`, `core_create_worktree`, `core_resolve_target`, `hooks`, `init`, `launch`, `parse_args`, `platform`, `provider`, `resolve_base_dir`, `sanitize_branch_name`, `sparse`, `ui_color`), and `integration_lifecycle` for end-to-end flows. Shared fixtures in `tests/test_helper.bash`.

**Tip**: Use a disposable repo for testing to avoid polluting your working tree:

```bash
mkdir -p /tmp/gtr-test && cd /tmp/gtr-test && git init && git commit --allow-empty -m "init"
/path/to/git-worktree-runner/bin/gtr new test-feature
```

## Architecture

### Binary Structure

- `bin/git-gtr` — Main entry point: sources libraries and commands, contains `main()` dispatcher
- `bin/gtr` — Convenience wrapper for development (`exec bin/git-gtr`)

### Module Structure

| File                | Purpose                                                                                                                     |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `lib/ui.sh`         | Logging (`log_error`, `log_info`, `log_warn`), prompts, formatting                                                          |
| `lib/args.sh`       | Shared argument parser: flag specs (`--flag`, `--flag: val`, aliases), populates `_arg_*` vars                              |
| `lib/config.sh`     | Git config wrapper with precedence: `cfg_get`, `cfg_default`, `cfg_get_all`                                                 |
| `lib/platform.sh`   | OS detection, GUI helpers                                                                                                   |
| `lib/core.sh`       | Worktree CRUD: `create_worktree`, `remove_worktree`, `list_worktrees`, `resolve_target`, `resolve_base_dir`                 |
| `lib/copy.sh`       | File/directory copying with glob patterns: `copy_patterns`, `copy_directories`                                              |
| `lib/hooks.sh`      | Hook execution: `run_hooks_in`/`run_hooks` for postCreate, preRemove, postRemove; `run_hooks_export` for postCd (see below) |
| `lib/provider.sh`   | Remote hosting detection (GitHub/GitLab) and CLI integration for `clean --merged/--closed`                                  |
| `lib/adapters.sh`   | Adapter registry, builder functions, generic fallbacks, loader functions                                                    |
| `lib/launch.sh`     | Editor/AI launch orchestration: `_open_editor`, `_auto_launch_editor`, `_auto_launch_ai`                                    |
| `lib/commands/*.sh` | One file per subcommand: `cmd_create`, `cmd_remove`, `cmd_pr`, `cmd_trust`, etc. (18 files)                                 |

Libraries are sourced in the order listed above (ui → args → config → ... → launch → commands/\*.sh glob).

`postCd` hooks have two dispatch paths, neither of which is `run_hooks_in`: `run_hooks_export`, called inside a subshell from `lib/launch.sh` and `lib/commands/ai.sh` so that environment changes made by the hooks reach the AI tool launched in that same subshell (the editor paths run no postCd hooks), and the `gtr cd` shell functions generated by `init`, which read `gtr.hook.postCd` (plus `.gtrconfig` `hooks.postCd`) and `eval` each hook directly in the user's shell.

### Adapters

Most adapters are defined declaratively in the **adapter registry** (`lib/adapters.sh`) using pipe-delimited entries. Custom adapters that need special logic remain as override files in `adapters/editor/` and `adapters/ai/`.

**Registry-defined adapters**: antigravity, atom, cursor, emacs, idea, nvim, pycharm, sublime, vim, vscode, webstorm, zed (editors) and aider, auggie, codex, continue, copilot, gemini, opencode (AI).

**Custom adapter files**: `adapters/editor/nano.sh`, `adapters/ai/claude.sh`, `adapters/ai/cursor.sh` — these implement `editor_can_open()`/`editor_open()` or `ai_can_start()`/`ai_start()` directly.

**Loading order**: file override → registry → generic PATH fallback. `GTR_EDITOR_CMD` / `GTR_AI_CMD` env vars allow custom tools without adapters.

### Command Flow

```
bin/git-gtr main() → case statement → cmd_*() handler → lib/*.sh functions → adapters (if needed)
```

Key dispatch: `new`→`cmd_create`, `pr`→`cmd_pr`, `rm`→`cmd_remove`, `mv|rename`→`cmd_rename`, `go`→`cmd_go`, `run`→`cmd_run`, `editor`→`cmd_editor`, `ai`→`cmd_ai`, `copy`→`cmd_copy`, `ls|list`→`cmd_list`, `clean`→`cmd_clean`, `init`→`cmd_init`, `config`→`cmd_config`, `completion`→`cmd_completion`, `doctor`→`cmd_doctor`, `adapter|adapters`→`cmd_adapter`, `trust`→`cmd_trust`. `cd` has no `cmd_*` handler: the dispatcher prints shell-integration instructions because `gtr cd` is implemented by the shell function that `init` generates.

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

**`init` command**: Outputs shell functions for `gtr cd <branch>` navigation. Output is cached to `~/.cache/gtr/` and auto-invalidates on version change. Users source the cache file directly in their shell rc for fast startup (see `git gtr help init`).

**`clean --merged` / `clean --closed`**: Removes worktrees whose PRs/MRs are merged or closed and deletes their branches. Auto-detects GitHub (`gh`) or GitLab (`glab`) from the `origin` remote URL. Override with `gtr.provider` config for self-hosted instances. `clean` also unlocks and prunes locked registry entries whose directories no longer exist.

**`pr <number|url|branch>`** (lib/commands/pr.sh): Creates a worktree from a GitHub pull request via `gh`. Uses `gh pr checkout --worktree` when the installed `gh` supports it, otherwise fetches `refs/pull/<n>/head` through a compatibility path.

**`new --porcelain`**: Emits exactly three `key<TAB>value` records (`path`, `branch`, `hook_status`) on stdout with everything else on stderr. Contract documented in `docs/agent-usage.md`; keep it stable.

**Sparse-checkout inheritance** (`gtr.sparse.inherit`, default on): On Git 2.36+, `new` copies the base worktree's sparse-checkout patterns instead of materializing a full tree. `--sparse`/`--no-sparse` override per invocation.

## Common Development Tasks

### Adding a New Command

1. Create `lib/commands/<name>.sh` with `cmd_<name>()` function
2. Add case entry in `main()` dispatcher in `bin/git-gtr`
3. Add help text in `lib/commands/help.sh`
4. Add the command and its flags to the `generate_bash`, `generate_zsh`, and `generate_fish` templates in `scripts/generate-completions.sh`, then run `./scripts/generate-completions.sh` (the files under `completions/` are generated; CI runs `--check`)
5. Update README.md

### Adding an Adapter

**Standard adapters** (just a command name + error message): Add an entry to `_EDITOR_REGISTRY` or `_AI_REGISTRY` in `lib/adapters.sh`. Then update help text in `lib/commands/help.sh` and README.md, and run `./scripts/generate-completions.sh` (registry names feed the completions automatically).

**Custom adapters** (special logic needed): Create `adapters/{editor,ai}/<name>.sh` implementing the two required functions (see `adapters/ai/claude.sh` for an example). File-based adapters take priority over registry entries.

### Updating the Version

Update `GTR_VERSION` in `bin/git-gtr`.

### Shell Completion Updates

`completions/gtr.bash`, `completions/_git-gtr`, and `completions/git-gtr.fish` are generated by `scripts/generate-completions.sh` and carry a `DO NOT EDIT MANUALLY` header. Adapter names come from `_EDITOR_REGISTRY` / `_AI_REGISTRY`, config keys from `_CFG_KEY_MAP`, and commands and flags from the three `generate_*` templates inside the script. After changing any of those, run `./scripts/generate-completions.sh` and commit the result; CI fails when `--check` finds a difference.

## Critical Gotcha: `set -e`

`bin/git-gtr` runs with `set -e`. Any unguarded non-zero return silently exits the entire script. When calling functions that may `return 1`, guard with `|| true`:

```bash
result=$(my_func) || true           # Prevents silent exit
if my_func; then ...; fi            # Also safe (if guards the return)
```

This is the most common source of subtle bugs in this codebase.

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
- `gtr.defaultBranch` / `gtr.defaultRemote` — Base branch (default: auto-detect) and remote (default: `origin`) for new worktrees
- `gtr.sparse.inherit` — Inherit sparse-checkout from the base worktree on Git 2.36+ (default: `true`)
- `gtr.provider` — Force `github` or `gitlab` for `clean --merged/--closed` (default: detect from `origin` URL)
- `gtr.editor.default` / `gtr.ai.default` — Default editor/AI tool
- `gtr.copy.include` / `gtr.copy.exclude` — File glob patterns (multi-valued, use `--add`)
- `gtr.copy.includeDirs` / `gtr.copy.excludeDirs` — Directory patterns (multi-valued)
- `gtr.hook.postCreate` / `gtr.hook.preRemove` / `gtr.hook.postRemove` / `gtr.hook.postCd` — Hook commands (multi-valued; `postCd` runs in the current shell after `gtr cd`, `gtr new --cd`, or `gtr pr --cd`)

Every `cfg_default` key also has an environment-variable fallback (for example `GTR_WORKTREES_DIR`, `GTR_DEFAULT_BRANCH`); the full table is in `docs/configuration.md`.

Hook env vars: `REPO_ROOT`, `WORKTREE_PATH`, `BRANCH`. preRemove hooks run with cwd in worktree; failure aborts removal unless `--force`.

## Debugging

```bash
bash -x ./bin/gtr <command>          # Full trace
GTR_DEBUG=1 ./bin/gtr <command>      # Report file:line:function on an unguarded failure
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
- `docs/agent-usage.md` — `--porcelain` output contract and safety boundaries for coding agents
- `docs/troubleshooting.md` — Common failures and fixes
