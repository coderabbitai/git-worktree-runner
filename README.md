# gtr - Git Worktree Runner

> A portable, cross-platform CLI for managing git worktrees with ease

`gtr` makes it simple to create, manage, and work with [git worktrees](https://git-scm.com/docs/git-worktree), enabling you to work on multiple branches simultaneously without stashing or switching contexts.

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
| Open in editor     | `cd ../repo-feature && cursor .`           | `gtr open 2`             |
| Start AI tool      | `cd ../repo-feature && aider`              | `gtr ai 2`                |
| Copy config files  | Manual copy/paste                          | Auto-copy via `gtr.copy.include`   |
| Run build steps    | Manual `npm install && npm run build`      | Auto-run via `gtr.hook.postCreate` |
| List worktrees     | `git worktree list` (shows paths)          | `gtr list` (shows IDs + status)    |
| Switch to worktree | `cd ../repo-feature`                       | `cd "$(gtr go 2)"`                 |
| Clean up           | `git worktree remove ../repo-feature`      | `gtr rm 2`                         |

**TL;DR:** `gtr` wraps `git worktree` with quality-of-life features for modern development workflows (AI tools, editors, automation).

## Features

- 🚀 **Simple commands** - Create and manage worktrees with intuitive CLI
- 🔧 **Configurable** - Git-config based settings, no YAML/TOML parsers needed
- 🎨 **Editor integration** - Open worktrees in Cursor, VS Code, or Zed
- 🤖 **AI tool support** - Launch Aider or other AI coding tools
- 📋 **Smart file copying** - Selectively copy configs/env files to new worktrees
- 🪝 **Hooks system** - Run custom commands after create/remove
- 🌍 **Cross-platform** - Works on macOS, Linux, and Windows (Git Bash)
- 🎯 **Shell completions** - Tab completion for Bash, Zsh, and Fish

## Installation

### Quick Install (macOS/Linux)

```bash
# Clone the repository
git clone https://github.com/anthropics/git-worktree-runner.git
cd git-worktree-runner

# Add to PATH (choose one)
# Option 1: Symlink to /usr/local/bin
sudo ln -s "$(pwd)/bin/gtr" /usr/local/bin/gtr

# Option 2: Add to your shell profile
echo 'export PATH="$PATH:'$(pwd)'/bin"' >> ~/.zshrc  # or ~/.bashrc
source ~/.zshrc
```

### Shell Completions (Optional)

**Bash:**

```bash
echo 'source /path/to/git-worktree-runner/completions/gtr.bash' >> ~/.bashrc
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

**Basic workflow (no flags needed):**
```bash
# One-time setup
gtr config set gtr.editor.default cursor
gtr config set gtr.ai.default aider

# Daily use - simple, no flags
gtr new my-feature          # Create worktree (auto-assigns ID)
gtr list                    # See all worktrees
gtr open my-feature         # Open in cursor (from config)
gtr ai my-feature           # Start aider (from config)
cd "$(gtr go my-feature)"   # Navigate to worktree
gtr rm 2                    # Remove when done
```

**Advanced examples:**
```bash
# Override defaults
gtr open 2 --editor vscode
gtr new hotfix --from v1.2.3 --id 99

# Destructive operations
gtr rm 2 --delete-branch --force
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
  --editor <name>      Override default editor
  --ai <tool>          Override default AI tool
  --no-copy            Skip file copying
  --no-fetch           Skip git fetch
  --yes                Non-interactive mode
```

**Examples:**

```bash
# Create worktree (auto-assigns ID)
gtr new my-feature

# Specific ID and branch
gtr new feature-x --id 2

# Create from specific ref
gtr new hotfix --from v1.2.3

# Create and open in Cursor
gtr new ui --editor cursor

# Create and start Aider
gtr new refactor --ai aider
```

### `gtr open`

Open a worktree in an editor or file browser. Accepts either ID or branch name.

```bash
gtr open <id|branch> [options]

Options:
  --editor <name>  Editor: cursor, vscode, zed
```

**Examples:**

```bash
# Open by ID (uses default editor from config)
gtr open 2

# Open by branch name with specific editor
gtr open my-feature --editor cursor

# Override default editor
gtr open 2 --editor zed
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

Start an AI coding tool in a worktree. Accepts either ID or branch name.

```bash
gtr ai <id|branch> [options] [-- args...]

Options:
  --tool <name>  AI tool: aider, claudecode, etc.
  --             Pass remaining args to tool
```

**Examples:**

```bash
# Start default AI tool by ID (uses gtr.ai.default)
gtr ai 2

# Start by branch name with specific tool
gtr ai my-feature --tool aider

# Start Aider with specific model
gtr ai 2 --tool aider -- --model gpt-5
```

### `gtr rm`

Remove worktree(s).

```bash
gtr rm <id> [<id>...] [options]

Options:
  --delete-branch  Also delete the branch
  --force          Force removal even with uncommitted changes
  --yes            Non-interactive mode
```

**Examples:**

```bash
# Remove single worktree
gtr rm 2

# Remove and delete branch
gtr rm 2 --delete-branch

# Remove multiple worktrees
gtr rm 2 3 4 --yes

# Force remove with uncommitted changes
gtr rm 2 --force
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
# Default AI tool: none (or aider, claudecode, codex, cursor, continue)
gtr.ai.default = none
```

**Supported AI Tools:**

| Tool                                              | Install                                           | Use Case                             | Command Example                        |
| ------------------------------------------------- | ------------------------------------------------- | ------------------------------------ | -------------------------------------- |
| **[Aider](https://aider.chat)**                   | `pip install aider-chat`                          | Pair programming, edit files with AI | `gtr ai 2 --tool aider`                |
| **[Claude Code](https://claude.com/claude-code)** | Install from claude.com                           | Terminal-native coding agent         | `gtr ai 2 --tool claudecode`           |
| **[Codex CLI](https://github.com/openai/codex)**  | `npm install -g @openai/codex`                    | OpenAI coding assistant              | `gtr ai 2 --tool codex -- "add tests"` |
| **[Cursor](https://cursor.com)**                  | Install from cursor.com                           | AI-powered editor with CLI agent     | `gtr ai 2 --tool cursor`               |
| **[Continue](https://continue.dev)**              | See [docs](https://docs.continue.dev/cli/install) | Open-source coding agent             | `gtr ai 2 --tool continue`             |

**Examples:**

```bash
# Set default AI tool globally
gtr config set gtr.ai.default aider --global

# Use specific tools per worktree
gtr ai 2 --tool claudecode -- --plan "refactor auth"
gtr ai 3 --tool aider -- --model gpt-5
gtr ai 4 --tool continue -- --headless
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
git config --global gtr.ai.default aider
git config --global gtr.worktrees.startId 2
```

## Advanced Usage

### Working with Multiple Branches

```bash
# Terminal 1: Work on feature
gtr new feature-a --id 2 --editor cursor

# Terminal 2: Review PR
gtr new pr/123 --id 3 --editor cursor

# Terminal 3: Navigate to main branch (repo root)
cd "$(gtr go 1)"  # ID 1 is always the repo root
```

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

# Try opening manually
gtr open 2 --editor cursor
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

For questions or issues, please [open an issue](https://github.com/anthropics/git-worktree-runner/issues).
