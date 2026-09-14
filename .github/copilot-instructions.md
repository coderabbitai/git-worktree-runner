# Copilot Instructions

Condensed guide for AI agents working in this repository. `AGENTS.md` and `CLAUDE.md` are the long-form versions; keep all three consistent.

## What This Is

`git gtr` (Git Worktree Runner) is a Bash CLI that wraps `git worktree` with editor and AI-tool launching, file copying, hooks, and pull-request checkout. It is installed as a git subcommand. User-facing docs always say `git gtr`, never `./bin/gtr`.

## Layout

- `bin/git-gtr` - entry point. Sets `set -e`, defines `GTR_VERSION`, sources every library, and dispatches in `main()` with a `case` on the first argument.
- `bin/gtr` - development wrapper that `exec`s `bin/git-gtr`.
- `lib/*.sh` - sourced in this order: `ui.sh` (logging, prompts), `args.sh` (flag parser that fills `_arg_*` vars), `config.sh` (`cfg_get`, `cfg_default`, `cfg_get_all`), `platform.sh` (OS detection), `core.sh` (worktree CRUD, `resolve_target`, `resolve_base_dir`, `sanitize_branch_name`), `copy.sh`, `hooks.sh` (`run_hooks_in`), `provider.sh` (GitHub/GitLab detection for `clean`), `adapters.sh` (adapter registries and loaders), `launch.sh` (editor/AI launch orchestration).
- `lib/commands/*.sh` - one file per subcommand defining `cmd_<name>()` (18 files, including `pr.sh` and `trust.sh`). Help text lives in `lib/commands/help.sh` as `_help_<command>()` functions; `cmd_help` finds them by name, with a small `case` mapping aliases such as `ls` to `list`.
- `adapters/editor/nano.sh`, `adapters/ai/claude.sh`, `adapters/ai/cursor.sh` - the only file-based adapters. Every other editor and AI tool is a registry line in `lib/adapters.sh`.
- `completions/` - generated output. Never edit by hand (see Common Changes).
- `tests/*.bats` - BATS suite (29 files) with shared fixtures in `tests/test_helper.bash`.

## Commands

`new`, `pr`, `rm`, `mv|rename`, `go`, `run`, `editor`, `ai`, `copy`, `ls|list`, `clean`, `doctor`, `adapter|adapters`, `config`, `completion`, `init`, `trust`, `version`, `help`. There is no `open` command; the editor command is `editor`. `cd` has no `cmd_*` handler: the dispatcher prints setup instructions because `gtr cd` is a shell function emitted by `init`.

Dispatch names that differ from the command: `new`→`cmd_create`, `rm`→`cmd_remove`, `mv|rename`→`cmd_rename`, `ls|list`→`cmd_list`, `adapter|adapters`→`cmd_adapter`. Everything else is `cmd_<command>`.

## Key Concepts

- Special ID `1` means the main repository in `go`, `editor`, `ai`, `run`, and other commands that take a worktree target.
- Folder name = sanitized branch (`feature/auth` → `feature-auth`); `--folder` replaces it, `--name` adds a suffix.
- `resolve_base_dir`: `gtr.worktrees.dir` → `GTR_WORKTREES_DIR` → `<repo>-worktrees` sibling. Relative paths resolve from the repo root, tilde expands, and it warns when the directory sits inside the repo without a `.gitignore` entry.
- `resolve_target`: ID `1` → current branch → sanitized path match → full scan. Returns TSV `is_main\tpath\tbranch`.
- Config precedence (`cfg_default`): local git config → `.gtrconfig` → global/system git config → `GTR_*` env var → default. Multi-value keys (`gtr.copy.*`, `gtr.hook.*`) merge and dedupe through `cfg_get_all`.
- `.gtrconfig` settings that execute code (hooks, editor/AI defaults) are ignored until `git gtr trust` approves them.
- `new --porcelain` prints exactly three `key<TAB>value` records (`path`, `branch`, `hook_status`) on stdout and everything else on stderr. Keep that contract stable; it is documented in `docs/agent-usage.md`.
- `new` inherits sparse-checkout from the base worktree on Git 2.36+ (`gtr.sparse.inherit`, `--sparse`, `--no-sparse`).

## Adapter Contract

Editor adapters define `editor_can_open` and `editor_open <path>`. AI adapters define `ai_can_start` and `ai_start <path> [args...]`, and run the tool in a subshell: `(cd "$path" && ...)`. Probe with `command -v`, report a missing tool with `log_error` plus an install hint, never fail silently, and keep side effects inside the target directory.

Standard tools are registry lines, not files. `_EDITOR_REGISTRY` entries are `name|cmd|type|err_msg|flags`; `_AI_REGISTRY` entries are `name|cmd|err_msg|info_lines`. Write an adapter file only for behavior the registry builders cannot express. A file override wins over a registry entry of the same name.

## Common Changes

**Add a command**: create `lib/commands/<name>.sh` with `cmd_<name>()`; add a `case` entry to `main()` in `bin/git-gtr`; add `_help_<name>()` to `lib/commands/help.sh` (found by name; add a `case` alias in `cmd_help` only if the command has aliases); add the command and its flags to the `generate_bash`, `generate_zsh`, and `generate_fish` templates in `scripts/generate-completions.sh`; run `./scripts/generate-completions.sh`; add `tests/cmd_<name>.bats`; document it in README.

**Add an adapter**: add a registry line in `lib/adapters.sh`; run `./scripts/generate-completions.sh`; update the adapter tables in README and `docs/configuration.md` and the tool list in `lib/commands/help.sh`.

**Change a flag**: update the command's `parse_args` spec, its `_help_<name>()`, the three completion templates, the regenerated completions, README, and the matching BATS file.

**Modify `lib/*.sh`**: keep existing configs working, quote every path, add fallbacks for Git older than 2.22 (see `get_current_branch` in `lib/core.sh`), and stay Bash 3.2 compatible.

## Validation

```bash
bats tests/                                   # full suite; bats tests/cmd_list.bats for one file
shellcheck bin/gtr bin/git-gtr lib/*.sh lib/commands/*.sh adapters/editor/*.sh adapters/ai/*.sh
./scripts/generate-completions.sh --check     # committed completions match the generator
```

CI (`.github/workflows/lint.yml`) runs exactly these three jobs on every pull request. Smoke-test by hand in a throwaway repo: `./bin/gtr new x`, `./bin/gtr list`, `./bin/gtr go x`, `./bin/gtr rm x`.

## Patterns & Gotchas

- `set -e` is global. Guard anything allowed to fail: `result=$(fn) || true`, or test it inside `if`.
- Quote every path and branch; both may contain spaces or slashes.
- Multi-value config keys need `git config --add`; a plain `set` overwrites the list.
- Call `sanitize_branch_name`; do not reimplement it.
- Never hand-edit `completions/*`. CI rejects files that differ from the generator output.

## Debugging

`bash -x ./bin/gtr <cmd>` gives a full trace. `GTR_DEBUG=1 ./bin/gtr <cmd>` prints `file:line:function` when a command fails under `set -e`. `declare -f resolve_target` confirms a function is loaded. `./bin/gtr doctor` and `./bin/gtr adapter` check the environment.

## Releasing

Bump `GTR_VERSION` in `bin/git-gtr`, add a dated `CHANGELOG.md` entry, and publish a GitHub release. `.github/workflows/homebrew.yml` then updates the Homebrew tap formula.

## Documentation Map

- `AGENTS.md` / `CLAUDE.md` - long-form architecture and workflow guide
- `.github/instructions/*.instructions.md` - file-pattern guidance: `testing`, `sh`, `lib`, `editor`, `ai`, `completions`
- `README.md` - user docs, with `docs/configuration.md`, `docs/advanced-usage.md`, `docs/agent-usage.md`, `docs/troubleshooting.md`
- `CONTRIBUTING.md` - contribution process and manual test checklist
