# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com), and this project adheres to [Semantic Versioning](https://semver.org).

## [Unreleased]

### Added

### Changed

### Deprecated

### Removed

### Fixed

### Security

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

[Unreleased]: https://github.com/coderabbitai/git-worktree-runner/compare/v2.0.0...HEAD
[2.0.0]: https://github.com/coderabbitai/git-worktree-runner/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/coderabbitai/git-worktree-runner/releases/tag/v1.0.0
