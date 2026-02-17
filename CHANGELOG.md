# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [Unreleased]

## [2.3.1] - 2026-02-17

### Added

- Google Antigravity adapter ([#121](https://github.com/coderabbitai/git-worktree-runner/pull/121))

### Changed

- Copy-on-write (CoW) cloning for directory copies on supported filesystems ([#122](https://github.com/coderabbitai/git-worktree-runner/pull/122))

### Fixed

- `gtr`/coreutils naming conflict resolved and `cd` completions added ([#125](https://github.com/coderabbitai/git-worktree-runner/pull/125))
- Main repo root resolved correctly from inside worktrees ([#126](https://github.com/coderabbitai/git-worktree-runner/pull/126))
- `resolve_target` fallback via `git worktree list` for external worktrees ([#128](https://github.com/coderabbitai/git-worktree-runner/pull/128))

## [2.3.0] - 2026-02-12

### Added

- Color output with `NO_COLOR`/`GTR_COLOR`/`gtr.ui.color` config support ([#120](https://github.com/coderabbitai/git-worktree-runner/pull/120))
- Per-command help system with `_help_<command>()` functions ([#120](https://github.com/coderabbitai/git-worktree-runner/pull/120))
- BATS test suite with 174 automated tests ([#119](https://github.com/coderabbitai/git-worktree-runner/pull/119))

### Changed

- Modularized monolithic `bin/gtr` into `lib/*.sh` libraries and `lib/commands/*.sh` ([#119](https://github.com/coderabbitai/git-worktree-runner/pull/119))
- Unified adapter loading for editors and AI tools ([#116](https://github.com/coderabbitai/git-worktree-runner/pull/116))
- Unified bidirectional config key mapping ([#115](https://github.com/coderabbitai/git-worktree-runner/pull/115))

### Fixed

- Removed ghost completion flag and added missing completions ([#111](https://github.com/coderabbitai/git-worktree-runner/pull/111))

## [2.2.0] - 2026-02-10

### Added

- `mv`/`rename` command for worktree renaming ([#95](https://github.com/coderabbitai/git-worktree-runner/pull/95))
- Shell integration via `git gtr init` with `gtr cd` navigation ([#104](https://github.com/coderabbitai/git-worktree-runner/pull/104))
- `postCd` hook for shell integration ([#109](https://github.com/coderabbitai/git-worktree-runner/pull/109))
- GitLab support for `clean --merged` ([#105](https://github.com/coderabbitai/git-worktree-runner/pull/105))
- `--folder` flag for custom worktree folder names ([#82](https://github.com/coderabbitai/git-worktree-runner/pull/82))
- `--no-hooks` flag to skip post-create hooks ([#91](https://github.com/coderabbitai/git-worktree-runner/pull/91))
- Auggie CLI adapter ([#84](https://github.com/coderabbitai/git-worktree-runner/pull/84))
- `$HOME/.local/bin` as install path option ([#100](https://github.com/coderabbitai/git-worktree-runner/pull/100))

### Fixed

- Base directory excluded from worktree list output ([#86](https://github.com/coderabbitai/git-worktree-runner/pull/86))
- Zsh completion timing issue resolved with `git gtr completion` command ([#87](https://github.com/coderabbitai/git-worktree-runner/pull/87))
- `.gtrconfig` file key auto-mapping in `cfg_default` ([#88](https://github.com/coderabbitai/git-worktree-runner/pull/88))
- Paths with slashes in `includeDirs` now handled correctly ([#103](https://github.com/coderabbitai/git-worktree-runner/pull/103))

## [2.1.0] - 2026-01-14

### Added

- `.code-workspace` file support for VS Code/Cursor editors ([#78](https://github.com/coderabbitai/git-worktree-runner/pull/78))
- `--editor` and `--ai` flags to `new` command for immediate editor/AI tool launch ([#72](https://github.com/coderabbitai/git-worktree-runner/pull/72))
- `config list` action with improved scope handling ([#68](https://github.com/coderabbitai/git-worktree-runner/pull/68))
- `--merged` flag to `clean` command for squash-merged PR detection ([#64](https://github.com/coderabbitai/git-worktree-runner/pull/64))
- GitHub Copilot CLI adapter ([#56](https://github.com/coderabbitai/git-worktree-runner/pull/56))
- `preRemove` hooks to run commands before worktree removal, with abort on failure unless `--force` ([#48](https://github.com/coderabbitai/git-worktree-runner/pull/48))
- `copy` command for syncing files to existing worktrees with `--all` and `--dry-run` options ([#39](https://github.com/coderabbitai/git-worktree-runner/pull/39))
- `.gtrconfig` file support for declarative team configuration using gitconfig syntax ([#38](https://github.com/coderabbitai/git-worktree-runner/pull/38))
- `.worktreeinclude` file support for pattern-based file copying ([#28](https://github.com/coderabbitai/git-worktree-runner/pull/28))
- Install script with platform detection ([#63](https://github.com/coderabbitai/git-worktree-runner/pull/63))

### Fixed

- Fish completion renamed to `git-gtr.fish` for proper git subcommand detection ([#71](https://github.com/coderabbitai/git-worktree-runner/pull/71))
- Git error messages now surfaced on worktree removal failure ([#55](https://github.com/coderabbitai/git-worktree-runner/pull/55))
- `rm` command now displays folder name instead of branch name for clarity ([#53](https://github.com/coderabbitai/git-worktree-runner/pull/53))
- Branch names with `#` now sanitized to prevent shebang issues in folder names ([#44](https://github.com/coderabbitai/git-worktree-runner/pull/44))
- Symlinks preserved when copying directories ([#46](https://github.com/coderabbitai/git-worktree-runner/pull/46))
- `config get/unset` now handle multi-value keys correctly ([#37](https://github.com/coderabbitai/git-worktree-runner/pull/37))
- Branch track output silenced in auto mode ([#33](https://github.com/coderabbitai/git-worktree-runner/pull/33))

## [2.0.0] - 2025-11-24

### Added

- `run` command to execute commands in worktrees without navigation (e.g., `git gtr run <branch> npm test`)
- `--from-current` flag for `git gtr new` command to create worktrees from the current branch instead of the default branch (useful for creating parallel variant worktrees)
- Directory copying support via `gtr.copy.includeDirs` and `gtr.copy.excludeDirs` to copy entire directories (e.g., `node_modules`, `.venv`, `vendor`) when creating worktrees, avoiding dependency reinstallation
- OpenCode AI adapter
- Pull request template (`.github/PULL_REQUEST_TEMPLATE.md`)
- Path canonicalization to properly resolve symlinks and compare paths

### Changed

- **BREAKING:** Migrated primary command from `gtr` to `git gtr` subcommand to resolve coreutils conflict with `gtr` command
- `git-gtr` wrapper now properly resolves symlinks and delegates to main `gtr` script
- Version output now displays as "git gtr version X.X.X" instead of "gtr version X.X.X"
- Help messages and error output now reference `git gtr` instead of `gtr`
- Base directory resolution now canonicalizes paths before comparison to handle symlinks correctly
- README extensively reorganized and expanded with clearer examples and better structure

### Fixed

- Claude AI adapter now supports shell function definitions (e.g., `eval "$(ssh-agent -s)"`) in shell initialization files
- Path comparison logic now canonicalizes paths before checking if worktrees are inside repository
- `.gitignore` warnings now work correctly with symlinked paths
- Zsh completion: Fixed word array normalization to correctly handle `gtr` and `git-gtr` direct invocations (not just `git gtr`)
- Zsh completion: Fixed `new` command options to complete at any position, not just after the first argument
- Zsh completion: Added `--editor` completion for `editor` command with list of available editors
- Zsh completion: Added `--ai` completion for `ai` command with list of available AI tools
- Zsh completion: Added `--porcelain` completion for `list`/`ls` commands
- Zsh completion: Added `--global` completion for `config` command

## [1.0.0] - 2025-11-14

### Added

- Initial release of `gtr` (Git Worktree Runner)
- Core commands: `new`, `rm`, `go`, `open`, `ai`, `list`, `clean`, `doctor`, `config`, `adapter`, `help`, `version`
- Worktree creation with branch sanitization, remote/local/auto tracking, and `--force --name` multi-worktree support
- Base directory resolution with support for `.` (repo root) and `./path` (inside repo) plus legacy sibling behavior
- Configuration system via `git config` (local→global→system precedence) and multi-value merging (`copy.include`, `hook.postCreate`, etc.)
- Editor adapter framework (cursor, vscode, zed, idea, pycharm, webstorm, vim, nvim, emacs, sublime, nano, atom)
- AI tool adapter framework (aider, claude, codex, cursor, continue)
- Hooks system: `postCreate`, `postRemove` with environment variables (`REPO_ROOT`, `WORKTREE_PATH`, `BRANCH`)
- Smart file copying (include/exclude glob patterns) with security guidance (`.env.example` vs `.env`)
- Shell completions for Bash, Zsh, and Fish
- Diagnostic commands: `doctor` (environment check) and `adapter` (adapter availability)
- Debian packaging assets (`build-deb.sh`, `Makefile`, `debian/` directory)
- Contributor & AI assistant guidance: `.github/instructions/*.instructions.md`, `.github/copilot-instructions.md`, `CLAUDE.md`
- Support for storing worktrees inside the repository via `gtr.worktrees.dir=./<path>`

### Changed

- Improved base directory resolution logic to distinguish `.` (repo root), `./path` (repo-internal) from other relative values (sibling directories)

[Unreleased]: https://github.com/coderabbitai/git-worktree-runner/compare/v2.3.1...HEAD
[2.3.1]: https://github.com/coderabbitai/git-worktree-runner/compare/v2.3.0...v2.3.1
[2.3.0]: https://github.com/coderabbitai/git-worktree-runner/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/coderabbitai/git-worktree-runner/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/coderabbitai/git-worktree-runner/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/coderabbitai/git-worktree-runner/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/coderabbitai/git-worktree-runner/releases/tag/v1.0.0
