# Copilot Instructions

## Architecture & Flow

`bin/gtr` (961 lines) dispatches to `cmd_*` functions (case block lines 36‑77). Libraries sourced at startup:

- `lib/core.sh` - create/list/remove/resolve worktrees
- `lib/config.sh` - git config wrapper with precedence
- `lib/ui.sh` - log_error/log_info/prompts
- `lib/copy.sh` - glob pattern file copying
- `lib/hooks.sh` - postCreate/postRemove execution
- `lib/platform.sh` - OS detection + GUI helpers

Adapters in `adapters/{editor,ai}` each implement two functions with strict contracts (see below).

## Key Concepts

- Special ID `1` = main repo (usable in `open`, `go`, `ai`).
- Folder naming = sanitized branch (`feature/auth` → `feature-auth`).
- Base dir resolution (`resolve_base_dir`): config `gtr.worktrees.dir` → env → default `<repo>-worktrees`; relative paths resolved from repo root; tilde expanded; warns if inside repo unignored.
- Target resolution (`resolve_target`): ID `1` → current → sanitized path → scan directories; returns TSV: `is_main\tpath\tbranch`.
- Config precedence (`cfg_default`): git config (local→global→system) → env → fallback. Multi-value keys merged & deduped (`cfg_get_all`).

## Adapter Contract

Editor: `editor_can_open`, `editor_open <path>`; AI: `ai_can_start`, `ai_start <path> [args...]`. Must check tool availability (`command -v`), emit errors via `log_error`, never silently fail, and avoid side effects outside the target directory (AI uses subshell `(cd ...)`). Update README, help (`cmd_help`), completions.

## Manual Testing (Essential Subset)

```bash
./bin/gtr new feature/x      # creates folder feature-x
./bin/gtr open feature/x     # loads configured editor
./bin/gtr ai feature/x       # starts configured AI tool
./bin/gtr list               # lists main + worktrees
./bin/gtr rm feature/x       # removes worktree
./bin/gtr go feature/x       # prints path (use in cd)
```

Advanced: `--force --name backend` (same branch multi-worktree); `git config --add gtr.copy.include "**/.env.example"`; hooks: `git config --add gtr.hook.postCreate "npm install"`.
Full matrix: see `.github/instructions/testing.instructions.md`.

## Common Changes

**Add command**: new `cmd_<name>()` function in `bin/gtr` + case entry (lines 36‑77) + help text in `cmd_help` + all three completions (bash/zsh/fish) + README docs.

**Add adapter**: two functions (see contract below), `log_error` with install instructions, quote all paths, check `command -v`. Update: README, help text (`cmd_help`), completions (all three).

**Modify core (`lib/*.sh`)**: keep backwards compatibility, always quote variables `"$var"`, support Git <2.22 fallback (`branch --show-current` → `rev-parse --abbrev-ref HEAD`), test manually across macOS/Linux.

## Patterns & Gotchas

- Always quote paths (spaces). Avoid unguarded globbing.
- `set -e` active: ensure non-critical failures are guarded (`command || true`).
- Multi-value config keys require `git config --add` (do not overwrite entire list unintentionally).
- If placing worktrees inside repo (relative path), add directory to `.gitignore` to prevent accidental commits.

## Debugging

Trace: `bash -x ./bin/gtr new test`; scoped: `set -x` / `set +x`; list function: `declare -f resolve_target`; inspect var: `echo "DEBUG=$var" >&2`; adapter sourcing: `bash -c 'source adapters/ai/claude.sh && ai_can_start && echo OK'`.

## Troubleshooting Quick

Permission: `chmod +x bin/gtr`. Missing adapter: `gtr adapter`. Install check: `./bin/gtr doctor`. Config issues: `git config --list | grep gtr`. Worktree confusion: inspect `resolve_target` logic & naming. Symlink problems: ensure `/usr/local/bin` exists then `ln -s "$(pwd)/bin/gtr" /usr/local/bin/gtr`.

## Version

Update `GTR_VERSION` (line 8 `bin/gtr`) when releasing; affects `gtr version` / `--version`.

## Documentation Structure

- **`.github/copilot-instructions.md`** (this file) - High-level guide for AI agents
- **`.github/instructions/*.instructions.md`** - Specific guidance by file pattern:
  - `testing.instructions.md` - Manual testing checklist (applies to: `bin/gtr`, `lib/**/*.sh`, `adapters/**/*.sh`)
  - `sh.instructions.md` - Shell scripting conventions (applies to: `**/*.sh`, `**/*.bash`, `**/*.fish`)
  - `lib.instructions.md` - Core library modification guidelines (applies to: `lib/**/*.sh`)
  - `editor.instructions.md` - Editor adapter contract (applies to: `adapters/editor/**/*.sh`)
  - `ai.instructions.md` - AI tool adapter contract (applies to: `adapters/ai/**/*.sh`)
  - `completions.instructions.md` - Shell completion updates (applies to: `completions/*`)
- **`README.md`** - User-facing documentation
- **`CONTRIBUTING.md`** - Contribution guidelines
- **`CLAUDE.md`** - Extended development guide for Claude Code

Feedback: Ask if more detail needed on copy patterns, hooks, or multi-worktree `--force` safety.
