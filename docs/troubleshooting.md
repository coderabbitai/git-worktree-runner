# Troubleshooting Guide

> Solutions for common issues with git-worktree-runner

[Back to README](../README.md) | [Configuration](configuration.md) | [Advanced Usage](advanced-usage.md)

---

## Table of Contents

- [Installation Issues](#installation-issues)
- [Worktree Creation Issues](#worktree-creation-issues)
- [Editor Issues](#editor-issues)
- [File Copying Issues](#file-copying-issues)
- [Platform Support](#platform-support)
- [Architecture Overview](#architecture-overview)
- [Reliability & Testing Status](#reliability--testing-status)

---

## Installation Issues

### "git: 'gtr' is not a git command"

This error means `git-gtr` is not in your PATH. Verify installation:

```bash
# Check if symlink exists (if neither exists, re-run ./install.sh)
ls -la /usr/local/bin/git-gtr 2>/dev/null || ls -la ~/bin/git-gtr 2>/dev/null

# Check if git-gtr is findable
which git-gtr

# Check your PATH includes the install location
echo $PATH | tr ':' '\n' | grep -E "(local/bin|/bin$)"
```

**Fix:** Re-run `./install.sh` or manually add the symlink location to your PATH:

```bash
# Add to ~/.zshrc or ~/.bashrc:
export PATH="/usr/local/bin:$PATH"
# Or if using ~/bin:
export PATH="$HOME/bin:$PATH"
```

Then restart your terminal.

---

## Worktree Creation Issues

### Worktree Creation Fails

```bash
# Ensure you've fetched latest refs
git fetch origin

# Check if branch already exists
git branch -a | grep your-branch

# Manually specify tracking mode
git gtr new test --track remote
```

### Branch Already Checked Out

If you get an error about a branch already being checked out, the branch exists in another worktree. Options:

1. Use a different branch name
2. Remove the existing worktree first: `git gtr rm <branch>`
3. Use `--force --name <suffix>` to create a second worktree on the same branch (advanced)

---

## Editor Issues

### Editor Not Opening

```bash
# Verify editor command is available
command -v cursor  # or: code, zed

# Check configuration
git gtr config get gtr.editor.default

# Try opening again
git gtr editor my-feature
```

### Wrong Editor Opens

Check your configuration precedence:

```bash
# Check local config
git config --local gtr.editor.default

# Check global config
git config --global gtr.editor.default

# Check .gtrconfig file
cat .gtrconfig 2>/dev/null | grep editor
```

---

## File Copying Issues

### Files Not Being Copied

```bash
# Check your patterns
git gtr config get gtr.copy.include

# Test patterns with find
cd /path/to/repo
find . -path "**/.env.example"

# Check if patterns are being excluded
git gtr config get gtr.copy.exclude
```

### Pattern Syntax Issues

- Use `**` for recursive matching: `**/.env.example`
- Use `*` for single-level wildcard: `*.config.js`
- Patterns are relative to repository root

---

## Platform Support

| Platform    | Status              | Notes                           |
| ----------- | ------------------- | ------------------------------- |
| **macOS**   | Full support        | Ventura+                        |
| **Linux**   | Full support        | Ubuntu, Fedora, Arch, etc.      |
| **Windows** | Via Git Bash or WSL | Native PowerShell not supported |

### Platform-Specific Notes

**macOS:**

- GUI opening uses `open`
- Terminal spawning uses iTerm2/Terminal.app
- Bash 3.2 ships by default (works, but 4.0+ recommended)

**Linux:**

- GUI opening uses `xdg-open`
- Terminal spawning uses gnome-terminal/konsole
- Most distros have Bash 4.0+

**Windows:**

- GUI opening uses `start`
- Requires Git Bash or WSL
- PowerShell is not supported (use Git Bash instead)

---

## Architecture Overview

```
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

---

## Reliability & Testing Status

**Current Status:** Production-ready for daily use

### Tested Platforms

| Platform    | Versions                                                     |
| ----------- | ------------------------------------------------------------ |
| **macOS**   | Ventura (13.x), Sonoma (14.x), Sequoia (15.x)                |
| **Linux**   | Ubuntu 22.04/24.04, Fedora 39+, Arch Linux                   |
| **Windows** | Git Bash (tested), WSL2 (tested), PowerShell (not supported) |

### Git Versions

| Version       | Support Level                         |
| ------------- | ------------------------------------- |
| Git 2.25+     | Recommended                           |
| Git 2.22+     | Full support                          |
| Git 2.17-2.21 | Basic support (some features limited) |
| Git < 2.17    | Not supported                         |

### Known Limitations

- Shell completions require bash-completion v2+ for Bash
- Some AI adapters require recent tool versions (see adapter docs)
- Windows native (non-WSL) support is experimental

### Testing Approach

- Core functionality tested across macOS, Linux, WSL2
- Manual testing with Cursor, VS Code, Aider, Claude Code
- Used in production for parallel agent workflows
- Community testing appreciated - please report issues!

### Experimental Features

| Feature                                  | Status                              |
| ---------------------------------------- | ----------------------------------- |
| `--force` flag for same-branch worktrees | Use with caution                    |
| Windows PowerShell support               | Not supported (use Git Bash or WSL) |

---

## Getting Help

If you're still having issues:

1. Run `git gtr doctor` to check your setup
2. Enable debug mode: `bash -x git gtr <command>`
3. [Open an issue](https://github.com/coderabbitai/git-worktree-runner/issues) with:
   - Your OS and version
   - Git version (`git --version`)
   - Bash version (`bash --version`)
   - The command you ran
   - The error message

---

[Back to README](../README.md) | [Configuration](configuration.md) | [Advanced Usage](advanced-usage.md)
