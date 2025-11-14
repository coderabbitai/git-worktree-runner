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

[Unreleased]: https://github.com/coderabbitai/git-worktree-runner/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/coderabbitai/git-worktree-runner/releases/tag/v1.0.0
