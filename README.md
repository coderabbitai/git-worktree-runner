# gtr - Git Worktree Runner

> A portable, cross-platform CLI for managing git worktrees with ease

![4 AI agents working in parallel across different worktrees](docs/assets/demo-parallel.png)

## What are git worktrees?

**ELI5:** Normally, you can only work on one git branch at a time in a folder. Want to fix a bug while working on a feature? You have to stash changes, switch branches, then switch back. Git worktrees let you have multiple branches checked out at once in different folders - like having multiple copies of your project, each on a different branch.

**The Problem:** Everyone's using git worktrees wrong (or not at all):

- 🔄 Constantly stashing/switching branches disrupts flow
- 🤹 Running tests on main while working on features requires manual copying
- 👥 Reviewing PRs means stopping current work
- 🤖 **Parallel AI agents on different branches?** Nearly impossible without worktrees

**Why people sleep on worktrees:** The DX is terrible. `git worktree add ../my-project-feature feature` is verbose, manual, and error-prone.

**Enter gtr:** Simple commands, AI tool integration, automatic setup, and built for modern parallel development workflows.

## Quick Start

**Install (30 seconds):**

```bash
git clone https://github.com/coderabbitai/git-worktree-runner.git
cd git-worktree-runner
sudo ln -s "$(pwd)/bin/git-gtr" /usr/local/bin/git-gtr
```

**Usage:**

```bash
# Navigate to your git repo
cd ~/GitHub/my-project

# One-time setup (per repository)
git gtr config set gtr.editor.default cursor
git gtr config set gtr.ai.default claude

# Daily workflow
git gtr new my-feature          # Create worktree folder: my-feature
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
```

## Why gtr?

While `git worktree` is powerful, it's verbose and manual. `git gtr` adds quality-of-life features for modern development:

| Task              | With `git worktree`                        | With `git gtr`                           |
| ----------------- | ------------------------------------------ | ---------------------------------------- |
| Create worktree   | `git worktree add ../repo-feature feature` | `git gtr new feature`                    |
| Open in editor    | `cd ../repo-feature && cursor .`           | `git gtr editor feature`                 |
| Start AI tool     | `cd ../repo-feature && aider`              | `git gtr ai feature`                     |
| Copy config files | Manual copy/paste                          | Auto-copy via `gtr.copy.include`         |
| Run build steps   | Manual `npm install && npm run build`      | Auto-run via `gtr.hook.postCreate`       |
| List worktrees    | `git worktree list` (shows paths)          | `git gtr list` (shows branches + status) |
| Clean up          | `git worktree remove ../repo-feature`      | `git gtr rm feature`                     |

**TL;DR:** `git gtr` wraps `git worktree` with quality-of-life features for modern development workflows (AI tools, editors, automation).

## Features

- 🚀 **Simple commands** - Create and manage worktrees with intuitive CLI
- 📁 **Repository-scoped** - Each repo has independent worktrees
- 🔧 **Configuration over flags** - Set defaults once, use simple commands
- 🎨 **Editor integration** - Open worktrees in Cursor, VS Code, Zed, and more
- 🤖 **AI tool support** - Launch Aider, Claude Code, or other AI coding tools
- 📋 **Smart file copying** - Selectively copy configs/env files to new worktrees
- 🪝 **Hooks system** - Run custom commands after create/remove
- 🌍 **Cross-platform** - Works on macOS, Linux, and Windows (Git Bash)
- 🎯 **Shell completions** - Tab completion for Bash, Zsh, and Fish

## Requirements

- **Git** 2.5+ (for `git worktree` support)
- **Bash** 3.2+ (macOS ships 3.2; 4.0+ recommended for advanced features)

## Shell Completions (Optional)

**Bash** (requires `bash-completion` v2 and git completions):

```bash
# Install bash-completion first (if not already installed)
# macOS:
brew install bash-completion@2

# Ubuntu/Debian:
sudo apt install bash-completion

# Ensure git's bash completion is enabled (usually installed with git)
# Then enable gtr completions:
echo 'source /path/to/git-worktree-runner/completions/gtr.bash' >> ~/.bashrc
source ~/.bashrc
```

**Zsh** (requires git's zsh completion):

```bash
# Add completion directory to fpath and enable
mkdir -p ~/.zsh/completions
cp /path/to/git-worktree-runner/completions/_git-gtr ~/.zsh/completions/

# Add to ~/.zshrc (if not already there):
cat >> ~/.zshrc <<'EOF'
# Enable completions
fpath=(~/.zsh/completions $fpath)
autoload -Uz compinit && compinit

# Load git-gtr completions (REQUIRED - must be sourced after compinit)
source ~/.zsh/completions/_git-gtr
EOF

# Clear completion cache and reload
rm -f ~/.zcompdump*
source ~/.zshrc
```

**Fish:**

```bash
ln -s /path/to/git-worktree-runner/completions/gtr.fish ~/.config/fish/completions/
```

## Commands

Commands accept branch names to identify worktrees. Use `1` to reference the main repo.
Run `git gtr help` for full documentation.

### `git gtr new <branch> [options]`

Create a new git worktree. Folder is named after the branch.

```bash
git gtr new my-feature                              # Creates folder: my-feature
git gtr new hotfix --from v1.2.3                    # Create from specific ref
git gtr new variant-1 --from-current                # Create from current branch
git gtr new feature/auth                            # Creates folder: feature-auth
git gtr new feature-auth --name backend --force     # Same branch, custom name
git gtr new my-feature --name descriptive-variant   # Optional: custom name without --force
```

**Options:**

- `--from <ref>`: Create from specific ref
- `--from-current`: Create from current branch (useful for parallel variant work)
- `--track <mode>`: Tracking mode (auto|remote|local|none)
- `--no-copy`: Skip file copying
- `--no-fetch`: Skip git fetch
- `--force`: Allow same branch in multiple worktrees (**requires --name**)
- `--name <suffix>`: Custom folder name suffix (optional, required with --force)
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
git gtr ai my-feature --ai aider          # Override with aider
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

### `git gtr config {get|set|add|unset} <key> [value] [--global]`

Manage configuration via git config.

```bash
git gtr config set gtr.editor.default cursor       # Set locally
git gtr config set gtr.ai.default claude --global  # Set globally
git gtr config get gtr.editor.default              # Get value
```

### Other Commands

- `git gtr doctor` - Health check (verify git, editors, AI tools)
- `git gtr adapter` - List available editor & AI adapters
- `git gtr clean` - Remove stale worktrees
- `git gtr version` - Show version

## Configuration

All configuration is stored via `git config`, making it easy to manage per-repository or globally. You can also use a `.gtrconfig` file for team-shared settings.

### Team Configuration with .gtrconfig

Create a `.gtrconfig` file in your repository root to share configuration across your team:

```gitconfig
# .gtrconfig - commit this file to share settings with your team

[copy]
    include = **/.env.example
    include = *.md
    exclude = **/.env

[copy]
    includeDirs = node_modules
    excludeDirs = node_modules/.cache

[hooks]
    postCreate = npm install
    postCreate = cp .env.example .env

[defaults]
    editor = cursor
    ai = claude
```

**Configuration precedence** (highest to lowest):

1. `git config --local` (`.git/config`) - personal overrides
2. `.gtrconfig` (repo root) - team defaults
3. `git config --global` (`~/.gitconfig`) - user defaults
4. `git config --system` (`/etc/gitconfig`) - system defaults
5. Environment variables
6. Default values

> [!TIP]
> See `templates/.gtrconfig.example` for a complete example with all available settings.

### Worktree Settings

```bash
# Base directory for worktrees
# Default: <repo-name>-worktrees (sibling to repo)
# Supports: absolute paths, repo-relative paths, tilde expansion
gtr.worktrees.dir = <path>

# Examples:
# Absolute path
gtr.worktrees.dir = /Users/you/all-worktrees/my-project

# Repo-relative (inside repository - requires .gitignore entry)
gtr.worktrees.dir = .worktrees

# Home directory (tilde expansion)
gtr.worktrees.dir = ~/worktrees/my-project

# Folder prefix (default: "")
gtr.worktrees.prefix = dev-

# Default branch (default: auto-detect)
gtr.defaultBranch = main
```

> [!IMPORTANT]
> If storing worktrees inside the repository, add the directory to `.gitignore`.

```bash
echo "/.worktrees/" >> .gitignore
```

### Editor Settings

```bash
# Default editor: cursor, vscode, zed, or none
gtr.editor.default = cursor
```

**Setup editors:**

- **Cursor**: Install from [cursor.com](https://cursor.com), enable shell command
- **VS Code**: Install from [code.visualstudio.com](https://code.visualstudio.com), enable `code` command
- **Zed**: Install from [zed.dev](https://zed.dev), `zed` command available automatically

### AI Tool Settings

```bash
# Default AI tool: none (or aider, claude, codex, continue, cursor, gemini, opencode)
gtr.ai.default = none
```

**Supported AI Tools:**

| Tool                                                      | Install                                           | Use Case                                                 | Set as Default                               |
| --------------------------------------------------------- | ------------------------------------------------- | -------------------------------------------------------- | -------------------------------------------- |
| **[Aider](https://aider.chat)**                           | `pip install aider-chat`                          | Pair programming, edit files with AI                     | `git gtr config set gtr.ai.default aider`    |
| **[Claude Code](https://claude.com/claude-code)**         | Install from claude.com                           | Terminal-native coding agent                             | `git gtr config set gtr.ai.default claude`   |
| **[Codex CLI](https://github.com/openai/codex)**          | `npm install -g @openai/codex`                    | OpenAI coding assistant                                  | `git gtr config set gtr.ai.default codex`    |
| **[Continue](https://continue.dev)**                      | See [docs](https://docs.continue.dev/cli/install) | Open-source coding agent                                 | `git gtr config set gtr.ai.default continue` |
| **[Cursor](https://cursor.com)**                          | Install from cursor.com                           | AI-powered editor with CLI agent                         | `git gtr config set gtr.ai.default cursor`   |
| **[Gemini](https://github.com/google-gemini/gemini-cli)** | `npm install -g @google/gemini-cli`               | Open-source AI coding assistant powered by Google Gemini | `git gtr config set gtr.ai.default gemini`   |
| **[OpenCode](https://opencode.ai)**                       | Install from opencode.ai                          | AI coding assistant                                      | `git gtr config set gtr.ai.default opencode` |

**Examples:**

```bash
# Set default AI tool for this repo
git gtr config set gtr.ai.default claude

# Or set globally for all repos
git gtr config set gtr.ai.default claude --global

# Then just use git gtr ai
git gtr ai my-feature

# Pass arguments to the tool
git gtr ai my-feature -- --plan "refactor auth"
```

### File Copying

Copy files to new worktrees using glob patterns:

```bash
# Add patterns to copy (multi-valued)
git gtr config add gtr.copy.include "**/.env.example"
git gtr config add gtr.copy.include "**/CLAUDE.md"
git gtr config add gtr.copy.include "*.config.js"

# Exclude patterns (multi-valued)
git gtr config add gtr.copy.exclude "**/.env"
git gtr config add gtr.copy.exclude "**/secrets.*"
```

#### Using .worktreeinclude file

Alternatively, create a `.worktreeinclude` file in your repository root:

```gitignore
# .worktreeinclude - files to copy to new worktrees
# Comments start with #

**/.env.example
**/CLAUDE.md
*.config.js
```

The file uses `.gitignore`-style syntax (one pattern per line, `#` for comments, empty lines ignored). Patterns from `.worktreeinclude` are merged with `gtr.copy.include` config settings - both sources are used together.

#### Security Best Practices

**The key distinction:** Development secrets (test API keys, local DB passwords) are **low risk** on personal machines. Production credentials are **high risk** everywhere.

```bash
# Personal dev: copy what you need to run dev servers
git gtr config add gtr.copy.include "**/.env.development"
git gtr config add gtr.copy.include "**/.env.local"
git gtr config add gtr.copy.exclude "**/.env.production"  # Never copy production
```

> [!TIP]
> The tool only prevents path traversal (`../`). Everything else is your choice - copy what you need for your worktrees to function.

#### Copying Directories

Copy entire directories (like `node_modules`, `.venv`, `vendor`) to avoid reinstalling dependencies:

```bash
# Copy dependency directories to speed up worktree creation
git gtr config add gtr.copy.includeDirs "node_modules"
git gtr config add gtr.copy.includeDirs ".venv"
git gtr config add gtr.copy.includeDirs "vendor"

# Exclude specific nested directories (supports glob patterns)
git gtr config add gtr.copy.excludeDirs "node_modules/.cache"  # Exclude exact path
git gtr config add gtr.copy.excludeDirs "node_modules/.npm"    # Exclude npm cache (may contain tokens)

# Exclude using wildcards
git gtr config add gtr.copy.excludeDirs "node_modules/.*"      # Exclude all hidden dirs in node_modules
git gtr config add gtr.copy.excludeDirs "*/.cache"             # Exclude .cache at any level
```

> [!WARNING]
> Dependency directories may contain sensitive files (credentials, tokens, cached secrets). Always use `gtr.copy.excludeDirs` to exclude sensitive subdirectories if needed.

**Use cases:**

- **JavaScript/TypeScript:** Copy `node_modules` to avoid `npm install` (can take minutes for large projects)
- **Python:** Copy `.venv` or `venv` to skip `pip install`
- **PHP:** Copy `vendor` to skip `composer install`
- **Go:** Copy build caches in `.cache` or `bin` directories

**How it works:** The tool uses `find` to locate directories by name and copies them with `cp -r`. This is much faster than reinstalling dependencies but uses more disk space.

### Hooks

Run custom commands during worktree operations:

```bash
# Post-create hooks (multi-valued, run in order)
git gtr config add gtr.hook.postCreate "npm install"
git gtr config add gtr.hook.postCreate "npm run build"

# Pre-remove hooks (run before deletion, abort on failure)
git gtr config add gtr.hook.preRemove "npm run cleanup"

# Post-remove hooks
git gtr config add gtr.hook.postRemove "echo 'Cleaned up!'"
```

**Hook execution order:**

| Hook | Timing | Use Case |
|------|--------|----------|
| `postCreate` | After worktree creation | Setup, install dependencies |
| `preRemove` | Before worktree deletion | Cleanup requiring directory access |
| `postRemove` | After worktree deletion | Notifications, logging |

> **Note:** Pre-remove hooks abort removal on failure. Use `--force` to skip failed hooks.

**Environment variables available in hooks:**

- `REPO_ROOT` - Repository root path
- `WORKTREE_PATH` - Worktree path
- `BRANCH` - Branch name

**Examples for different build tools:**

```bash
# Node.js (npm)
git gtr config add gtr.hook.postCreate "npm install"

# Node.js (pnpm)
git gtr config add gtr.hook.postCreate "pnpm install"

# Python
git gtr config add gtr.hook.postCreate "pip install -r requirements.txt"

# Ruby
git gtr config add gtr.hook.postCreate "bundle install"

# Rust
git gtr config add gtr.hook.postCreate "cargo build"
```

## Configuration Examples

### Minimal Setup (Just Basics)

```bash
git gtr config set gtr.worktrees.prefix "wt-"
git gtr config set gtr.defaultBranch "main"
```

### Full-Featured Setup (Node.js Project)

```bash
# Worktree settings
git gtr config set gtr.worktrees.prefix "wt-"

# Editor
git gtr config set gtr.editor.default cursor

# Copy environment templates
git gtr config add gtr.copy.include "**/.env.example"
git gtr config add gtr.copy.include "**/.env.development"
git gtr config add gtr.copy.exclude "**/.env.local"

# Build hooks
git gtr config add gtr.hook.postCreate "pnpm install"
git gtr config add gtr.hook.postCreate "pnpm run build"
```

### Global Defaults

```bash
# Set global preferences
git gtr config set gtr.editor.default cursor --global
git gtr config set gtr.ai.default claude --global
```

## Advanced Usage

### How It Works: Repository Scoping

**gtr is repository-scoped** - each git repository has its own independent set of worktrees:

- Run `git gtr` commands from within any git repository
- Worktree folders are named after their branch names
- Each repo manages its own worktrees independently
- Switch repos with `cd`, then run `git gtr` commands for that repo

### Working with Multiple Branches

```bash
# Terminal 1: Work on feature
git gtr new feature-a
git gtr editor feature-a

# Terminal 2: Review PR
git gtr new pr/123
git gtr editor pr/123

# Terminal 3: Navigate to main branch (repo root)
cd "$(git gtr go 1)"  # Special ID '1' = main repo
```

### Working with Multiple Repositories

Each repository has its own independent set of worktrees. Switch repos with `cd`:

```bash
# Frontend repo
cd ~/GitHub/frontend
git gtr list
# BRANCH          PATH
# main [main]     ~/GitHub/frontend
# auth-feature    ~/GitHub/frontend-worktrees/auth-feature
# nav-redesign    ~/GitHub/frontend-worktrees/nav-redesign

git gtr editor auth-feature      # Open frontend auth work
git gtr ai nav-redesign          # AI on frontend nav work

# Backend repo (separate worktrees)
cd ~/GitHub/backend
git gtr list
# BRANCH          PATH
# main [main]     ~/GitHub/backend
# api-auth        ~/GitHub/backend-worktrees/api-auth
# websockets      ~/GitHub/backend-worktrees/websockets

git gtr editor api-auth          # Open backend auth work
git gtr ai websockets            # AI on backend websockets

# Switch back to frontend
cd ~/GitHub/frontend
git gtr editor auth-feature      # Opens frontend auth
```

**Key point:** Each repository has its own worktrees. Use branch names to identify worktrees.

### Custom Workflows with Hooks

Create a `.gtr-setup.sh` in your repo:

```bash
#!/bin/sh
# .gtr-setup.sh - Project-specific git gtr configuration

git gtr config set gtr.worktrees.prefix "dev-"
git gtr config set gtr.editor.default cursor

# Copy configs
git gtr config add gtr.copy.include ".env.example"
git gtr config add gtr.copy.include "docker-compose.yml"

# Setup hooks
git gtr config add gtr.hook.postCreate "docker-compose up -d db"
git gtr config add gtr.hook.postCreate "npm install"
git gtr config add gtr.hook.postCreate "npm run db:migrate"
```

Then run: `sh .gtr-setup.sh`

### Non-Interactive Automation

Perfect for CI/CD or scripts:

```bash
# Create worktree without prompts
git gtr new ci-test --yes --no-copy

# Remove without confirmation
git gtr rm ci-test --yes --delete-branch
```

### Multiple Worktrees on Same Branch

> [!TIP]
> Git normally prevents checking out the same branch in multiple worktrees to avoid conflicts. `git gtr` supports bypassing this safety check with `--force` and `--name` flags.

**Use cases:**

- Splitting work across multiple AI agents on one feature
- Testing same branch in different environments/configs
- Running parallel CI/build processes
- Debugging without disrupting main worktree

**Risks:**

- Concurrent edits in multiple worktrees can cause conflicts
- Easy to lose work if not careful
- Git's safety check exists for good reason

**Using `--force` with `--name` (required):**

```bash
# Create multiple worktrees for same branch with descriptive names
git gtr new feature-auth                          # Main worktree: feature-auth/
git gtr new feature-auth --force --name backend   # Creates: feature-auth-backend/
git gtr new feature-auth --force --name frontend  # Creates: feature-auth-frontend/
git gtr new feature-auth --force --name tests     # Creates: feature-auth-tests/

# All worktrees are on the same 'feature-auth' branch
# The --name flag is required with --force to distinguish worktrees
```

**Example: Parallel AI development on one feature:**

```bash
# Terminal 1: Backend work
git gtr new feature-auth --force --name backend
git gtr ai feature-auth-backend -- --message "Implement API endpoints"

# Terminal 2: Frontend work
git gtr new feature-auth --force --name frontend
git gtr ai feature-auth-frontend -- --message "Build UI components"

# Terminal 3: Tests
git gtr new feature-auth --force --name tests
git gtr ai feature-auth-tests -- --message "Write integration tests"

# All agents commit to the same feature-auth branch
```

**Best practices when using --force:**

- Always provide a descriptive `--name` (backend, frontend, tests, ci, etc.)
- Only edit files in one worktree at a time
- Commit/stash changes before switching worktrees
- Ideal for parallel AI agents working on different parts of one feature
- Use `git gtr list` to see all worktrees and their branches

## Troubleshooting

### Worktree Creation Fails

```bash
# Ensure you've fetched latest refs
git fetch origin

# Check if branch already exists
git branch -a | grep your-branch

# Manually specify tracking mode
git gtr new test --track remote
```

### Editor Not Opening

```bash
# Verify editor command is available
command -v cursor  # or: code, zed

# Check configuration
git gtr config get gtr.editor.default

# Try opening again
git gtr editor 2
```

### File Copying Issues

```bash
# Check your patterns
git gtr config get gtr.copy.include

# Test patterns with find
cd /path/to/repo
find . -path "**/.env.example"
```

## Platform Support

- ✅ **macOS** - Full support (Ventura+)
- ✅ **Linux** - Full support (Ubuntu, Fedora, Arch, etc.)
- ✅ **Windows** - Via Git Bash or WSL

**Platform-specific notes:**

- **macOS**: GUI opening uses `open`, terminal spawning uses iTerm2/Terminal.app
- **Linux**: GUI opening uses `xdg-open`, terminal spawning uses gnome-terminal/konsole
- **Windows**: GUI opening uses `start`, requires Git Bash or WSL

## Architecture

```log
git-worktree-runner/
├── bin/
│   ├── git-gtr         # Git subcommand entry point (wrapper)
│   └── gtr             # Core implementation (1000+ lines)
├── lib/                 # Core libraries
│   ├── core.sh         # Git worktree operations
│   ├── config.sh       # Configuration management
│   ├── platform.sh     # OS-specific code
│   ├── ui.sh           # User interface
│   ├── copy.sh         # File copying
│   └── hooks.sh        # Hook execution
├── adapters/           # Editor & AI tool plugins
│   ├── editor/
│   └── ai/
├── completions/        # Shell completions
└── templates/          # Example configs
```

## Reliability & Testing Status

**Current Status:** Production-ready for daily use

**Tested Platforms:**

- ✅ **macOS** - Ventura (13.x), Sonoma (14.x), Sequoia (15.x)
- ✅ **Linux** - Ubuntu 22.04/24.04, Fedora 39+, Arch Linux
- ⚠️ **Windows** - Git Bash (tested), WSL2 (tested), PowerShell (not supported)

**Git Versions:**

- ✅ Git 2.25+ (recommended)
- ✅ Git 2.22+ (full support)
- ⚠️ Git 2.5-2.21 (basic support, some features limited)

**Known Limitations:**

- Shell completions require bash-completion v2+ for Bash
- Some AI adapters require recent tool versions (see adapter docs)
- Windows native (non-WSL) support is experimental

**Testing Approach:**

- Core functionality tested across macOS, Linux, WSL2
- Manual testing with Cursor, VS Code, Aider, Claude Code
- Used in production for parallel agent workflows
- Community testing appreciated - please report issues!

**Experimental Features:**

- `--force` flag for same-branch worktrees (use with caution)
- Windows PowerShell support (use Git Bash or WSL instead)

## Contributing

Contributions welcome! Areas where help is appreciated:

- 🎨 **New editor adapters** - JetBrains IDEs, Neovim, etc.
- 🤖 **New AI tool adapters** - Continue.dev, Codeium, etc.
- 🐛 **Bug reports** - Platform-specific issues
- 📚 **Documentation** - Tutorials, examples, use cases
- ✨ **Features** - Propose enhancements via issues

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Related Projects

- [git-worktree](https://git-scm.com/docs/git-worktree) - Official git documentation
- [Aider](https://aider.chat) - AI pair programming in your terminal
- [Cursor](https://cursor.com) - AI-powered code editor

## License

Copyright 2025 CodeRabbit

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

- <http://www.apache.org/licenses/LICENSE-2.0>

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

## Acknowledgments

Built to streamline parallel development workflows with git worktrees. Inspired by the need for simple, configurable worktree management across different development environments.

## Happy coding with worktrees! 🚀

For questions or issues, please [open an issue](https://github.com/coderabbitai/git-worktree-runner/issues).
