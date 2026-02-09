# gtr - Git Worktree Runner

[![License](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE.txt)
[![Bash](https://img.shields.io/badge/Bash-3.2%2B-green.svg)](https://www.gnu.org/software/bash/)
[![Git](https://img.shields.io/badge/Git-2.17%2B-orange.svg)](https://git-scm.com/)
[![Platform](https://img.shields.io/badge/Platform-macOS%20%7C%20Linux%20%7C%20Windows-lightgrey.svg)](#platform-support)

> A portable, cross-platform CLI for managing git worktrees with ease

![4 AI agents working in parallel across different worktrees](docs/assets/demo-parallel.png)

## Table of Contents

- [What are git worktrees?](#what-are-git-worktrees)
- [Quick Start](#quick-start)
- [Why gtr?](#why-gtr)
- [Features](#features)
- [Requirements](#requirements)
- [Commands](#commands)
- [Configuration](#configuration)
- [Shell Completions](#shell-completions-optional)
- [Platform Support](#platform-support)
- [Contributing](#contributing)
- [License](#license)

---

## What are git worktrees?

**ELI5:** Normally, you can only work on one git branch at a time in a folder. Want to fix a bug while working on a feature? You have to stash changes, switch branches, then switch back. Git worktrees let you have multiple branches checked out at once in different folders - like having multiple copies of your project, each on a different branch.

**The Problem:** Everyone's using git worktrees wrong (or not at all):

- Constantly stashing/switching branches disrupts flow
- Running tests on main while working on features requires manual copying
- Reviewing PRs means stopping current work
- **Parallel AI agents on different branches?** Nearly impossible without worktrees

**Why people sleep on worktrees:** The DX is terrible. `git worktree add ../my-project-feature feature` is verbose, manual, and error-prone.

**Enter gtr:** Simple commands, AI tool integration, automatic setup, and built for modern parallel development workflows.

## Quick Start

**Install:**

```bash
git clone https://github.com/coderabbitai/git-worktree-runner.git
cd git-worktree-runner
./install.sh
```

<details>
<summary><b>Manual installation options</b></summary>

**macOS (Apple Silicon with Homebrew):**

```bash
ln -s "$(pwd)/bin/git-gtr" "$(brew --prefix)/bin/git-gtr"
```

**macOS (Intel) / Linux:**

```bash
sudo mkdir -p /usr/local/bin
sudo ln -s "$(pwd)/bin/git-gtr" /usr/local/bin/git-gtr
```

**User-local (no sudo required):**

```bash
mkdir -p ~/.local/bin
ln -s "$(pwd)/bin/git-gtr" ~/.local/bin/git-gtr
# Add to ~/.zshrc or ~/.bashrc if ~/.local/bin is not in PATH:
# export PATH="$HOME/.local/bin:$PATH"
```

</details>

**Usage:**

```bash
# Navigate to your git repo
cd ~/GitHub/my-project

# One-time setup (per repository)
git gtr config set gtr.editor.default cursor
git gtr config set gtr.ai.default claude

# Daily workflow
git gtr new my-feature          # Create worktree folder: my-feature
git gtr new my-feature --editor # Create and open in editor
git gtr new my-feature --ai     # Create and start AI tool
git gtr new my-feature -e -a    # Create, open editor, then start AI
git gtr editor my-feature       # Open in cursor
git gtr ai my-feature           # Start claude

# Run commands in worktree
git gtr run my-feature npm test # Run tests

# Navigate to worktree (alternative)
cd "$(git gtr go my-feature)"

# List all worktrees
git gtr list

# Remove when done
git gtr rm my-feature

# Or remove all worktrees with merged PRs (requires gh CLI)
git gtr clean --merged
```

## Why gtr?

While `git worktree` is powerful, it's verbose and manual. `git gtr` adds quality-of-life features for modern development:

| Task              | With `git worktree`                        | With `git gtr`                           |
| ----------------- | ------------------------------------------ | ---------------------------------------- |
| Create worktree   | `git worktree add ../repo-feature feature` | `git gtr new feature`                    |
| Create + open     | `git worktree add ... && cursor .`         | `git gtr new feature --editor`           |
| Open in editor    | `cd ../repo-feature && cursor .`           | `git gtr editor feature`                 |
| Start AI tool     | `cd ../repo-feature && claude`             | `git gtr ai feature`                     |
| Copy config files | Manual copy/paste                          | Auto-copy via `gtr.copy.include`         |
| Run build steps   | Manual `npm install && npm run build`      | Auto-run via `gtr.hook.postCreate`       |
| List worktrees    | `git worktree list` (shows paths)          | `git gtr list` (shows branches + status) |
| Clean up          | `git worktree remove ../repo-feature`      | `git gtr rm feature`                     |

**TL;DR:** `git gtr` wraps `git worktree` with quality-of-life features for modern development workflows (AI tools, editors, automation).

## Features

- **Simple commands** - Create and manage worktrees with intuitive CLI
- **Repository-scoped** - Each repo has independent worktrees
- **Configuration over flags** - Set defaults once, use simple commands
- **Editor integration** - Open worktrees in Cursor, VS Code, Zed, and more
- **AI tool support** - Launch Aider, Claude Code, or other AI coding tools
- **Smart file copying** - Selectively copy configs/env files to new worktrees
- **Hooks system** - Run custom commands after create/remove
- **Cross-platform** - Works on macOS, Linux, and Windows (Git Bash)
- **Shell completions** - Tab completion for Bash, Zsh, and Fish

## Requirements

- **Git** 2.17+ (for `git worktree move/remove` support)
- **Bash** 3.2+ (macOS ships 3.2; 4.0+ recommended for advanced features)

## Commands

Commands accept branch names to identify worktrees. Use `1` to reference the main repo.
Run `git gtr help` for full documentation.

### `git gtr new <branch> [options]`

Create a new git worktree. Folder is named after the branch.

```bash
git gtr new my-feature                                                                   # Creates folder: my-feature
git gtr new hotfix --from v1.2.3                                                         # Create from specific ref
git gtr new variant-1 --from-current                                                     # Create from current branch
git gtr new feature/auth                                                                 # Creates folder: feature-auth
git gtr new feature/implement-user-authentication-with-oauth2-integration --folder auth  # Custom folder name
git gtr new feature-auth --name backend --force                                          # Same branch, custom name
git gtr new my-feature --name descriptive-variant                                        # Optional: custom name without --force
```

**Options:**

- `--from <ref>`: Create from specific ref
- `--from-current`: Create from current branch (useful for parallel variant work)
- `--track <mode>`: Tracking mode (auto|remote|local|none)
- `--no-copy`: Skip file copying
- `--no-fetch`: Skip git fetch
- `--no-hooks`: Skip post-create hooks
- `--force`: Allow same branch in multiple worktrees (**requires --name or --folder**)
- `--name <suffix>`: Custom folder name suffix (optional, required with --force)
- `--folder <name>`: Custom folder name (replaces default, useful for long branch names)
- `--editor`, `-e`: Open in editor after creation
- `--ai`, `-a`: Start AI tool after creation
- `--yes`: Non-interactive mode

### `git gtr editor <branch> [--editor <name>]`

Open worktree in editor (uses `gtr.editor.default` or `--editor` flag).

```bash
git gtr editor my-feature                    # Uses configured editor
git gtr editor my-feature --editor vscode    # Override with vscode
```

### `git gtr ai <branch> [--ai <name>] [-- args...]`

Start AI coding tool (uses `gtr.ai.default` or `--ai` flag).

```bash
git gtr ai my-feature                      # Uses configured AI tool
git gtr ai my-feature --ai codex          # Override with different tool
git gtr ai my-feature -- --model gpt-4    # Pass arguments to tool
git gtr ai 1                              # Use AI in main repo
```

### `git gtr go <branch>`

Print worktree path for shell navigation.

```bash
cd "$(git gtr go my-feature)"    # Navigate by branch name
cd "$(git gtr go 1)"             # Navigate to main repo
```

### `git gtr run <branch> <command...>`

Execute command in worktree directory.

```bash
git gtr run my-feature npm test             # Run tests
git gtr run my-feature npm run dev          # Start dev server
git gtr run feature-auth git status         # Run git commands
git gtr run 1 npm run build                 # Run in main repo
```

### `git gtr rm <branch>... [options]`

Remove worktree(s) by branch name.

```bash
git gtr rm my-feature                              # Remove one
git gtr rm feature-a feature-b                     # Remove multiple
git gtr rm my-feature --delete-branch --force      # Delete branch and force
```

**Options:** `--delete-branch`, `--force`, `--yes`

### `git gtr mv <old> <new> [--force] [--yes]`

Rename worktree directory and branch together. Aliases: `rename`

```bash
git gtr mv feature-wip feature-auth      # Rename worktree and branch
git gtr mv old-name new-name --force     # Force rename locked worktree
git gtr mv old-name new-name --yes       # Skip confirmation
```

**Options:** `--force`, `--yes`

**Note:** Only renames the local branch. Remote branch remains unchanged.

### `git gtr copy <target>... [options] [-- <pattern>...]`

Copy files from main repo to existing worktree(s). Useful for syncing env files after worktree creation.

```bash
git gtr copy my-feature                       # Uses gtr.copy.include patterns
git gtr copy my-feature -- ".env*"            # Explicit pattern
git gtr copy my-feature -- ".env*" "*.json"   # Multiple patterns
git gtr copy -a -- ".env*"                    # Copy to all worktrees
git gtr copy my-feature -n -- "**/.env*"      # Dry-run preview
```

**Options:**

- `-n, --dry-run`: Preview without copying
- `-a, --all`: Copy to all worktrees
- `--from <source>`: Copy from different worktree (default: main repo)

### `git gtr list [--porcelain]`

List all worktrees. Use `--porcelain` for machine-readable output.

### `git gtr config {get|set|add|unset|list} <key> [value] [--global]`

Manage configuration via git config.

```bash
git gtr config set gtr.editor.default cursor       # Set locally
git gtr config set gtr.ai.default claude --global  # Set globally
git gtr config get gtr.editor.default              # Get value
git gtr config list                                # List all gtr config
```

### `git gtr clean [options]`

Remove worktrees: clean up empty directories, or remove those with merged GitHub PRs.

```bash
git gtr clean                                  # Remove empty worktree directories and prune
git gtr clean --merged                         # Remove worktrees for merged PRs (GitHub CLI required)
git gtr clean --merged --dry-run               # Preview which worktrees would be removed
git gtr clean --merged --yes                   # Remove without confirmation prompts
```

**Options:**

- `--merged`: Remove worktrees whose branches have merged PRs on GitHub (also deletes the branch)
- `--dry-run`, `-n`: Preview changes without removing
- `--yes`, `-y`: Non-interactive mode (skip confirmation prompts)

**Note:** The `--merged` mode requires the GitHub CLI (`gh`) to be installed and authenticated. It checks GitHub PRs (e.g., PRs merged into the default branch `main`) using the GitHub CLI to inspect merge state and removes their worktrees (and deletes the branches locally).

### Other Commands

- `git gtr doctor` - Health check (verify git, editors, AI tools)
- `git gtr adapter` - List available editor & AI adapters
- `git gtr version` - Show version

## Configuration

All configuration is stored via `git config`. For team settings, create a `.gtrconfig` file in your repository root.

### Quick Setup

```bash
# Set your editor (cursor, vscode, zed)
git gtr config set gtr.editor.default cursor

# Set your AI tool (aider, auggie, claude, codex, continue, copilot, cursor, gemini, opencode)
git gtr config set gtr.ai.default claude

# Copy env files to new worktrees
git gtr config add gtr.copy.include "**/.env.example"

# Run setup after creating worktrees
git gtr config add gtr.hook.postCreate "npm install"
```

### Team Configuration (.gtrconfig)

```gitconfig
# .gtrconfig - commit this to share settings
[copy]
    include = **/.env.example
    exclude = **/.env
    includeDirs = node_modules
    excludeDirs = node_modules/.cache

[hooks]
    postCreate = npm install

[defaults]
    editor = cursor
    ai = claude
```

**Configuration precedence** (highest to lowest):

1. `git config --local` (`.git/config`) - personal overrides
2. `.gtrconfig` (repo root) - team defaults
3. `git config --global` (`~/.gitconfig`) - user defaults

> For complete configuration reference including all settings, hooks, file copying patterns, and environment variables, see [docs/configuration.md](docs/configuration.md)

## Shell Completions (Optional)

```bash
# Bash (~/.bashrc)
source <(git gtr completion bash)

# Zsh (~/.zshrc) - must be before compinit
eval "$(git gtr completion zsh)"

# Fish
mkdir -p ~/.config/fish/completions
git gtr completion fish > ~/.config/fish/completions/git-gtr.fish
```

> For troubleshooting, see [docs/configuration.md#shell-completions](docs/configuration.md#shell-completions)

## Platform Support

| Platform    | Status          | Notes                           |
| ----------- | --------------- | ------------------------------- |
| **macOS**   | Full support    | Ventura+ recommended            |
| **Linux**   | Full support    | Ubuntu, Fedora, Arch, etc.      |
| **Windows** | Git Bash or WSL | Native PowerShell not supported |

Requires Git 2.17+ and Bash 3.2+.

> For troubleshooting, platform-specific notes, and architecture details, see [docs/troubleshooting.md](docs/troubleshooting.md)

## Advanced Usage

For advanced workflows including:

- **Multiple worktrees on same branch** (`--force` + `--name`)
- **Parallel AI agent development** patterns
- **Custom workflow scripts** (`.gtr-setup.sh`)
- **CI/CD automation** (non-interactive mode)
- **Working with multiple repositories**

See [docs/advanced-usage.md](docs/advanced-usage.md)

## Contributing

Contributions welcome! Areas where help is appreciated:

- **New editor adapters** - JetBrains IDEs, Neovim, etc.
- **New AI tool adapters** - Codeium, etc.
- **Bug reports** - Platform-specific issues
- **Documentation** - Tutorials, examples, use cases

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines and [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md) for community standards.

## License

This project is licensed under the [Apache License 2.0](LICENSE.txt).

---

Built to streamline parallel development workflows with git worktrees.

For questions or issues, [open an issue](https://github.com/coderabbitai/git-worktree-runner/issues).
