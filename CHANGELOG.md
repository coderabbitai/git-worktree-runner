# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2025-01-XX

### Added

- **Repository-scoped worktrees** - Each git repo has independent worktrees and IDs
- **Auto-ID allocation** - Worktrees auto-assigned starting from configurable `gtr.worktrees.startId` (default: 2)
- **Branch-name-first UX** - All commands accept either numeric IDs or branch names (`gtr open my-feature`)
- **Auto-open/Auto-AI on create** - When `gtr.editor.default` or `gtr.ai.default` are configured, `gtr new` automatically opens the editor and/or starts AI tool
- **Editor adapters** - Support for Cursor, VS Code, and Zed
- **AI tool adapters** - Support for Aider, Claude Code, Continue, Codex, and Cursor AI
- **Smart file copying** - Selectively copy files to new worktrees via `gtr.copy.include` and `gtr.copy.exclude` globs
- **Hooks system** - Run custom commands after worktree creation (`gtr.hook.postCreate`) and removal (`gtr.hook.postRemove`)
- **Shell completions** - Tab completion for Bash, Zsh, and Fish
- **Cross-platform support** - Works on macOS, Linux, and Windows (Git Bash/WSL)
- **Utility commands**:
  - `gtr new <branch>` - Create worktree with smart branch tracking
  - `gtr go <id|branch>` - Navigate to worktree (shell integration)
  - `gtr open <id|branch>` - Open in editor
  - `gtr ai <id|branch>` - Start AI coding tool
  - `gtr rm <id|branch>` - Remove worktree(s)
  - `gtr list` - List all worktrees with human/machine-readable output
  - `gtr clean` - Remove stale worktrees
  - `gtr doctor` - Health check for git, editors, and AI tools
  - `gtr adapter` - List available editor/AI adapters
  - `gtr config` - Manage git-config based settings

### Technical

- **POSIX-sh compliance** - Pure shell script with zero external dependencies beyond git
- **Modular architecture** - Clean separation of core, config, platform, UI, copy, and hooks logic
- **Adapter pattern** - Pluggable editor and AI tool integrations
- **Stream separation** - Data to stdout, messages to stderr for composability

[1.0.0]: https://github.com/anthropics/git-worktree-runner/releases/tag/v1.0.0
