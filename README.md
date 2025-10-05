# gtr - Git Worktree Runner

> A portable, cross-platform CLI for managing git worktrees with ease

`gtr` makes it simple to create, manage, and work with [git worktrees](https://git-scm.com/docs/git-worktree), enabling you to work on multiple branches simultaneously without stashing or switching contexts.

## How It Works

**gtr is repository-scoped** - each git repository has its own independent set of worktrees:

- Run `gtr` commands from within any git repository
- Each repo has separate worktree IDs (starting at 2, ID 1 is the main repo)
- IDs are local to each repo - no conflicts across projects
- Switch repos with `cd`, then run `gtr` commands for that repo

**Example - Working across multiple repos:**
```bash
cd ~/GitHub/frontend
gtr new auth-feature      # Creates frontend worktree (ID 2)
gtr list                  # Shows only frontend worktrees

cd ~/GitHub/backend
gtr new auth-api          # Creates backend worktree (also ID 2 - different repo!)
gtr list                  # Shows only backend worktrees
```

## Why Git Worktrees?

Git worktrees let you check out multiple branches at once in separate directories. This is invaluable when you need to:

- Review a PR while working on a feature
- Run tests on `main` while developing
- Quickly switch between branches without stashing
- Compare implementations side-by-side
- Run multiple development servers simultaneously

## Why not just `git worktree`?

While `git worktree` is powerful, it requires remembering paths and manually setting up each worktree. `gtr` adds:

| Task               | With `git worktree`                        | With `gtr`                         |
| ------------------ | ------------------------------------------ | ---------------------------------- |
| Create worktree    | `git worktree add ../repo-feature feature` | `gtr new feature`                  |
| Open in editor     | `cd ../repo-feature && cursor .`           | `gtr open feature`             |
| Start AI tool      | `cd ../repo-feature && aider`              | `gtr ai feature`                |
| Copy config files  | Manual copy/paste                          | Auto-copy via `gtr.copy.include`   |
| Run build steps    | Manual `npm install && npm run build`      | Auto-run via `gtr.hook.postCreate` |
| List worktrees     | `git worktree list` (shows paths)          | `gtr list` (shows IDs + status)    |
| Switch to worktree | `cd ../repo-feature`                       | `cd "$(gtr go feature)"`                 |
| Clean up           | `git worktree remove ../repo-feature`      | `gtr rm feature`                         |

**TL;DR:** `gtr` wraps `git worktree` with quality-of-life features for modern development workflows (AI tools, editors, automation).

## Features

- 🚀 **Simple commands** - Create and manage worktrees with intuitive CLI
- 📁 **Repository-scoped** - Each repo has independent worktrees and IDs
- 🔧 **Configurable** - Git-config based settings, no YAML/TOML parsers needed
- 🎨 **Editor integration** - Open worktrees in Cursor, VS Code, or Zed
- 🤖 **AI tool support** - Launch Aider or other AI coding tools
- 📋 **Smart file copying** - Selectively copy configs/env files to new worktrees
- 🪝 **Hooks system** - Run custom commands after create/remove
- 🌍 **Cross-platform** - Works on macOS, Linux, and Windows (Git Bash)
- 🎯 **Shell completions** - Tab completion for Bash, Zsh, and Fish

## Requirements

- **Git** 2.5+ (for `git worktree` support)
- **Bash** 3.2+ (macOS ships 3.2; 4.0+ recommended for advanced features)

## Installation

### Quick Install (macOS/Linux)

```bash
# Clone the repository
git clone https://github.com/coderabbitai/git-worktree-runner.git
cd git-worktree-runner

# Add to PATH (choose one)
# Option 1: Symlink to /usr/local/bin
sudo ln -s "$(pwd)/bin/gtr" /usr/local/bin/gtr

# Option 2: Add to your shell profile
echo 'export PATH="$PATH:'$(pwd)'/bin"' >> ~/.zshrc  # or ~/.bashrc
source ~/.zshrc
```

### Shell Completions (Optional)

**Bash** (requires `bash-completion` v2):

```bash
# Install bash-completion first (if not already installed)
# macOS:
brew install bash-completion@2

# Ubuntu/Debian:
sudo apt install bash-completion

# Then enable gtr completions:
echo 'source /path/to/git-worktree-runner/completions/gtr.bash' >> ~/.bashrc
source ~/.bashrc
```

**Zsh:**

```bash
echo 'source /path/to/git-worktree-runner/completions/_gtr' >> ~/.zshrc
```

**Fish:**

```bash
ln -s /path/to/git-worktree-runner/completions/gtr.fish ~/.config/fish/completions/
```

## Quick Start

**Prerequisites:** `cd` into a git repository first.

**Basic workflow:**
```bash
# Navigate to your git repo
cd ~/GitHub/my-project

# One-time setup (per repository)
gtr config set gtr.editor.default cursor
gtr config set gtr.ai.default claude

# Daily workflow - explicit commands
gtr new my-feature          # Create worktree
gtr open my-feature         # Open in cursor (from config)
gtr ai my-feature           # Start claude (from config)

# Or chain them together
gtr new my-feature && gtr open my-feature && gtr ai my-feature

# Navigate to worktree
cd "$(gtr go my-feature)"

# List all worktrees
gtr list

# Remove when done
gtr rm my-feature
```

**Advanced:**
```bash
# Create from specific ref
gtr new hotfix --from v1.2.3 --id 99

# Remove with branch deletion
gtr rm my-feature --delete-branch --force
```

## Commands

### `gtr new`

Create a new git worktree. IDs are auto-assigned by default.

```bash
gtr new <branch> [options]

Options (all optional):
  --id <n>             Specific worktree ID (rarely needed)
  --from <ref>         Create from specific ref (default: main/master)
  --track <mode>       Track mode: auto|remote|local|none
  --no-copy            Skip file copying
  --no-fetch           Skip git fetch
  --yes                Non-interactive mode
```

**Examples:**

```bash
# Create worktree (auto-assigns ID)
gtr new my-feature

# Create from specific ref
gtr new hotfix --from v1.2.3

# Then open and start AI
gtr open hotfix
gtr ai hotfix
```

### `gtr open`

Open a worktree in an editor. Uses `gtr.editor.default` from config.

```bash
gtr open <id|branch>
```

**Examples:**

```bash
# Open by ID (uses gtr.editor.default)
gtr open 2

# Open by branch name
gtr open my-feature
```

### `gtr go`

Navigate to a worktree directory. Prints path to stdout for shell integration.

```bash
gtr go <id|branch>
```

**Examples:**

```bash
# Change to worktree by ID
cd "$(gtr go 2)"

# Change to worktree by branch name
cd "$(gtr go my-feature)"
```

### `gtr ai`

Start an AI coding tool in a worktree. Uses `gtr.ai.default` from config.

```bash
gtr ai <id|branch> [-- args...]
```

**Examples:**

```bash
# Start AI tool by ID (uses gtr.ai.default)
gtr ai 2

# Start by branch name
gtr ai my-feature

# Pass arguments to the AI tool
gtr ai my-feature -- --model gpt-4
```

### `gtr rm`

Remove worktree(s). Accepts either ID or branch name.

```bash
gtr rm <id|branch> [<id|branch>...] [options]

Options:
  --delete-branch  Also delete the branch
  --force          Force removal even with uncommitted changes
  --yes            Non-interactive mode
```

**Examples:**

```bash
# Remove by branch name
gtr rm my-feature

# Remove by ID
gtr rm 2

# Remove and delete branch
gtr rm my-feature --delete-branch

# Remove multiple worktrees
gtr rm feature-a feature-b hotfix --yes

# Force remove with uncommitted changes
gtr rm my-feature --force
```

### `gtr list`

List all git worktrees.

```bash
gtr list [--porcelain|--ids]

Options:
  --porcelain  Machine-readable output (tab-separated)
  --ids        Output only worktree IDs (for scripting)
```

### `gtr config`

Manage gtr configuration via git config.

```bash
gtr config get <key> [--global]
gtr config set <key> <value> [--global]
gtr config unset <key> [--global]
```

**Examples:**

```bash
# Set default editor locally
gtr config set gtr.editor.default cursor

# Set global worktree prefix
gtr config set gtr.worktrees.prefix "wt-" --global

# Get current value
gtr config get gtr.editor.default
```

## Configuration

All configuration is stored via `git config`, making it easy to manage per-repository or globally.

### Worktree Settings

```bash
# Base directory (default: <repo-name>-worktrees)
gtr.worktrees.dir = /path/to/worktrees

# Name prefix (default: wt-)
gtr.worktrees.prefix = dev-

# Starting ID (default: 2)
gtr.worktrees.startId = 1

# Default branch (default: auto-detect)
gtr.defaultBranch = main
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
# Default AI tool: none (or aider, claude, codex, cursor, continue)
gtr.ai.default = none
```

**Supported AI Tools:**

| Tool                                              | Install                                           | Use Case                             | Set as Default                        |
| ------------------------------------------------- | ------------------------------------------------- | ------------------------------------ | ------------------------------------- |
| **[Aider](https://aider.chat)**                   | `pip install aider-chat`                          | Pair programming, edit files with AI | `gtr config set gtr.ai.default aider` |
| **[Claude Code](https://claude.com/claude-code)** | Install from claude.com                           | Terminal-native coding agent         | `gtr config set gtr.ai.default claude` |
| **[Codex CLI](https://github.com/openai/codex)**  | `npm install -g @openai/codex`                    | OpenAI coding assistant              | `gtr config set gtr.ai.default codex` |
| **[Cursor](https://cursor.com)**                  | Install from cursor.com                           | AI-powered editor with CLI agent     | `gtr config set gtr.ai.default cursor` |
| **[Continue](https://continue.dev)**              | See [docs](https://docs.continue.dev/cli/install) | Open-source coding agent             | `gtr config set gtr.ai.default continue` |

**Examples:**

```bash
# Set default AI tool for this repo
gtr config set gtr.ai.default claude

# Or set globally for all repos
gtr config set gtr.ai.default claude --global

# Then just use gtr ai
gtr ai my-feature

# Pass arguments to the tool
gtr ai my-feature -- --plan "refactor auth"
```

### File Copying

Copy files to new worktrees using glob patterns:

```bash
# Add patterns to copy (multi-valued)
git config --add gtr.copy.include "**/.env.example"
git config --add gtr.copy.include "**/CLAUDE.md"
git config --add gtr.copy.include "*.config.js"

# Exclude patterns (multi-valued)
git config --add gtr.copy.exclude "**/.env"
git config --add gtr.copy.exclude "**/secrets.*"
```

**⚠️ Security Note:** Be careful not to copy sensitive files. Use `.env.example` instead of `.env`.

### Hooks

Run custom commands after worktree operations:

```bash
# Post-create hooks (multi-valued, run in order)
git config --add gtr.hook.postCreate "npm install"
git config --add gtr.hook.postCreate "npm run build"

# Post-remove hooks
git config --add gtr.hook.postRemove "echo 'Cleaned up!'"
```

**Environment variables available in hooks:**

- `REPO_ROOT` - Repository root path
- `WORKTREE_PATH` - New worktree path
- `BRANCH` - Branch name

**Examples for different build tools:**

```bash
# Node.js (npm)
git config --add gtr.hook.postCreate "npm install"

# Node.js (pnpm)
git config --add gtr.hook.postCreate "pnpm install"

# Python
git config --add gtr.hook.postCreate "pip install -r requirements.txt"

# Ruby
git config --add gtr.hook.postCreate "bundle install"

# Rust
git config --add gtr.hook.postCreate "cargo build"
```

## Configuration Examples

### Minimal Setup (Just Basics)

```bash
git config --local gtr.worktrees.prefix "wt-"
git config --local gtr.defaultBranch "main"
```

### Full-Featured Setup (Node.js Project)

```bash
# Worktree settings
git config --local gtr.worktrees.prefix "wt-"
git config --local gtr.worktrees.startId 2

# Editor
git config --local gtr.editor.default cursor

# Copy environment templates
git config --local --add gtr.copy.include "**/.env.example"
git config --local --add gtr.copy.include "**/.env.development"
git config --local --add gtr.copy.exclude "**/.env.local"

# Build hooks
git config --local --add gtr.hook.postCreate "pnpm install"
git config --local --add gtr.hook.postCreate "pnpm run build"
```

### Global Defaults

```bash
# Set global preferences
git config --global gtr.editor.default cursor
git config --global gtr.ai.default claude
git config --global gtr.worktrees.startId 2
```

## Advanced Usage

### Working with Multiple Branches

```bash
# Terminal 1: Work on feature
gtr new feature-a --id 2
gtr open feature-a

# Terminal 2: Review PR
gtr new pr/123 --id 3
gtr open pr/123

# Terminal 3: Navigate to main branch (repo root)
cd "$(gtr go 1)"  # ID 1 is always the repo root
```

### Working with Multiple Repositories

Each repository has its own independent set of worktrees and IDs. Switch repos with `cd`:

```bash
# Frontend repo
cd ~/GitHub/frontend
gtr list
# ID  BRANCH          PATH
# 1   main            ~/GitHub/frontend
# 2   auth-feature    ~/GitHub/frontend-worktrees/wt-2
# 3   nav-redesign    ~/GitHub/frontend-worktrees/wt-3

gtr open auth-feature        # Open frontend auth work
gtr ai nav-redesign          # AI on frontend nav work

# Backend repo (separate worktrees, separate IDs)
cd ~/GitHub/backend
gtr list
# ID  BRANCH          PATH
# 1   main            ~/GitHub/backend
# 2   api-auth        ~/GitHub/backend-worktrees/wt-2  # Different ID 2!
# 5   websockets      ~/GitHub/backend-worktrees/wt-5

gtr open api-auth            # Open backend auth work
gtr ai websockets            # AI on backend websockets

# Switch back to frontend
cd ~/GitHub/frontend
gtr open auth-feature        # Opens frontend auth (use branch names!)
```

**Key point:** IDs are per-repository, not global. ID 2 in frontend ≠ ID 2 in backend.

### Custom Workflows with Hooks

Create a `.gtr-setup.sh` in your repo:

```bash
#!/bin/sh
# .gtr-setup.sh - Project-specific gtr configuration

git config --local gtr.worktrees.prefix "dev-"
git config --local gtr.editor.default cursor

# Copy configs
git config --local --add gtr.copy.include ".env.example"
git config --local --add gtr.copy.include "docker-compose.yml"

# Setup hooks
git config --local --add gtr.hook.postCreate "docker-compose up -d db"
git config --local --add gtr.hook.postCreate "npm install"
git config --local --add gtr.hook.postCreate "npm run db:migrate"
```

Then run: `sh .gtr-setup.sh`

### Non-Interactive Automation

Perfect for CI/CD or scripts:

```bash
# Create worktree without prompts
gtr new ci-test --id 99 --yes --no-copy

# Remove without confirmation
gtr rm 99 --yes --delete-branch
```

## Troubleshooting

### Worktree Creation Fails

```bash
# Ensure you've fetched latest refs
git fetch origin

# Check if branch already exists
git branch -a | grep your-branch

# Manually specify tracking mode
gtr new test --track remote
```

### Editor Not Opening

```bash
# Verify editor command is available
command -v cursor  # or: code, zed

# Check configuration
gtr config get gtr.editor.default

# Try opening again
gtr open 2
```

### File Copying Issues

```bash
# Check your patterns
git config --get-all gtr.copy.include

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

```
git-worktree-runner/
├── bin/gtr              # Main executable
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

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

Built to streamline parallel development workflows with git worktrees. Inspired by the need for simple, configurable worktree management across different development environments.

---

**Happy coding with worktrees! 🚀**

For questions or issues, please [open an issue](https://github.com/coderabbitai/git-worktree-runner/issues).
