# Configuration Reference

> Complete configuration guide for git-worktree-runner

[Back to README](../README.md) | [Advanced Usage](advanced-usage.md) | [Troubleshooting](troubleshooting.md)

---

## Table of Contents

- [Configuration Sources](#configuration-sources)
- [Team Configuration (.gtrconfig)](#team-configuration-gtrconfig)
- [Worktree Settings](#worktree-settings)
- [Editor Settings](#editor-settings)
- [AI Tool Settings](#ai-tool-settings)
- [File Copying](#file-copying)
- [Directory Copying](#directory-copying)
- [Hooks](#hooks)
- [Shell Completions](#shell-completions)
- [Configuration Examples](#configuration-examples)
- [Environment Variables](#environment-variables)

---

## Configuration Sources

All configuration is stored via `git config`, making it easy to manage per-repository or globally. You can also use a `.gtrconfig` file for team-shared settings.

**Configuration precedence** (highest to lowest):

1. `git config --local` (`.git/config`) - personal overrides
2. `.gtrconfig` (repo root) - team defaults
3. `git config --global` (`~/.gitconfig`) - user defaults
4. `git config --system` (`/etc/gitconfig`) - system defaults
5. Environment variables
6. Default values

---

## Team Configuration (.gtrconfig)

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

> [!TIP]
> See `templates/.gtrconfig.example` for a complete example with all available settings.

---

## Worktree Settings

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

---

## Editor Settings

```bash
# Default editor: cursor, vscode, zed, or none
gtr.editor.default = cursor

# Workspace file for VS Code/Cursor (relative path from worktree root)
# If set, opens the workspace file instead of the folder
# If not set, auto-detects *.code-workspace files in worktree root
# Set to "none" to disable workspace lookup entirely
gtr.editor.workspace = project.code-workspace
```

**Setup editors:**

- **Cursor**: Install from [cursor.com](https://cursor.com), enable shell command
- **VS Code**: Install from [code.visualstudio.com](https://code.visualstudio.com), enable `code` command
- **Zed**: Install from [zed.dev](https://zed.dev), `zed` command available automatically

**Workspace files:**

VS Code and Cursor support `.code-workspace` files for multi-root workspaces, custom settings, and recommended extensions. When opening a worktree:

1. If `gtr.editor.workspace` is set to a path, opens that file (relative to worktree root)
2. If set to `none`, disables workspace lookup (always opens folder)
3. Otherwise, auto-detects any `*.code-workspace` file in the worktree root
4. Falls back to opening the folder if no workspace file is found

---

## AI Tool Settings

```bash
# Default AI tool: none (or aider, claude, codex, continue, copilot, cursor, gemini, opencode)
gtr.ai.default = none
```

**Supported AI Tools:**

| Tool                                                                  | Install                                           | Use Case                                                 | Set as Default                               |
| --------------------------------------------------------------------- | ------------------------------------------------- | -------------------------------------------------------- | -------------------------------------------- |
| **[Aider](https://aider.chat)**                                       | `pip install aider-chat`                          | Pair programming, edit files with AI                     | `git gtr config set gtr.ai.default aider`    |
| **[Claude Code](https://claude.com/claude-code)**                     | Install from claude.com                           | Terminal-native coding agent                             | `git gtr config set gtr.ai.default claude`   |
| **[Codex CLI](https://github.com/openai/codex)**                      | `npm install -g @openai/codex`                    | OpenAI coding assistant                                  | `git gtr config set gtr.ai.default codex`    |
| **[Continue](https://continue.dev)**                                  | See [docs](https://docs.continue.dev/cli/install) | Open-source coding agent                                 | `git gtr config set gtr.ai.default continue` |
| **[GitHub Copilot CLI](https://githubnext.com/projects/copilot-cli)** | `npm install -g @githubnext/copilot-cli`          | AI-powered CLI assistant by GitHub                       | `git gtr config set gtr.ai.default copilot`  |
| **[Cursor](https://cursor.com)**                                      | Install from cursor.com                           | AI-powered editor with CLI agent                         | `git gtr config set gtr.ai.default cursor`   |
| **[Gemini](https://github.com/google-gemini/gemini-cli)**             | `npm install -g @google/gemini-cli`               | Open-source AI coding assistant powered by Google Gemini | `git gtr config set gtr.ai.default gemini`   |
| **[OpenCode](https://opencode.ai)**                                   | Install from opencode.ai                          | AI coding assistant                                      | `git gtr config set gtr.ai.default opencode` |

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

---

## File Copying

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

### Using .worktreeinclude file

Alternatively, create a `.worktreeinclude` file in your repository root:

```gitignore
# .worktreeinclude - files to copy to new worktrees
# Comments start with #

**/.env.example
**/CLAUDE.md
*.config.js
```

The file uses `.gitignore`-style syntax (one pattern per line, `#` for comments, empty lines ignored). Patterns from `.worktreeinclude` are merged with `gtr.copy.include` config settings - both sources are used together.

### Security Best Practices

**The key distinction:** Development secrets (test API keys, local DB passwords) are **low risk** on personal machines. Production credentials are **high risk** everywhere.

```bash
# Personal dev: copy what you need to run dev servers
git gtr config add gtr.copy.include "**/.env.development"
git gtr config add gtr.copy.include "**/.env.local"
git gtr config add gtr.copy.exclude "**/.env.production"  # Never copy production
```

> [!TIP]
> The tool only prevents path traversal (`../`). Everything else is your choice - copy what you need for your worktrees to function.

---

## Directory Copying

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

---

## Hooks

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

| Hook         | Timing                   | Use Case                           |
| ------------ | ------------------------ | ---------------------------------- |
| `postCreate` | After worktree creation  | Setup, install dependencies        |
| `preRemove`  | Before worktree deletion | Cleanup requiring directory access |
| `postRemove` | After worktree deletion  | Notifications, logging             |

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

---

## Shell Completions

Enable tab completion for Bash, Zsh, or Fish.

### Bash

Requires `bash-completion` v2 and git completions:

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

### Zsh

Requires git's zsh completion:

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

### Fish

```bash
ln -s /path/to/git-worktree-runner/completions/git-gtr.fish ~/.config/fish/completions/
```

---

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

---

## Environment Variables

| Variable              | Description                                            | Default                    |
| --------------------- | ------------------------------------------------------ | -------------------------- |
| `GTR_DIR`             | Override script directory location                     | Auto-detected              |
| `GTR_WORKTREES_DIR`   | Override base worktrees directory                      | `gtr.worktrees.dir` config |
| `GTR_EDITOR_CMD`      | Custom editor command (e.g., `emacs`)                  | None                       |
| `GTR_EDITOR_CMD_NAME` | First word of `GTR_EDITOR_CMD` for availability checks | None                       |
| `GTR_AI_CMD`          | Custom AI tool command (e.g., `copilot`)               | None                       |
| `GTR_AI_CMD_NAME`     | First word of `GTR_AI_CMD` for availability checks     | None                       |

**Hook environment variables** (available in hook scripts):

| Variable        | Description          |
| --------------- | -------------------- |
| `REPO_ROOT`     | Repository root path |
| `WORKTREE_PATH` | Worktree path        |
| `BRANCH`        | Branch name          |

---

[Back to README](../README.md) | [Advanced Usage](advanced-usage.md) | [Troubleshooting](troubleshooting.md)
