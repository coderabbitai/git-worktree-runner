# Contributing to gtr

Thank you for considering contributing to `git gtr`! This document provides guidelines and instructions for contributing.

## How to Contribute

### Reporting Issues

Before creating an issue, please:

1. **Search existing issues** to avoid duplicates
2. **Provide a clear description** of the problem
3. **Include your environment details**:
   - OS and version (macOS, Linux distro, Windows Git Bash)
   - Git version
   - Shell (bash, zsh, fish)
4. **Steps to reproduce** the issue
5. **Expected vs actual behavior**

### Suggesting Features

We welcome feature suggestions! Please:

1. **Check existing issues** for similar requests
2. **Describe the use case** - why is this needed?
3. **Propose a solution** if you have one in mind
4. **Consider backwards compatibility** and cross-platform support

## Development

### Architecture Overview

```
git-worktree-runner/
├── bin/gtr              # Main executable (~105 lines: sources libs, dispatches commands)
├── lib/                 # Core functionality
│   ├── ui.sh           # User interface (logging, prompts)
│   ├── config.sh       # Configuration (git-config wrapper)
│   ├── platform.sh     # OS-specific utilities
│   ├── core.sh         # Git worktree operations
│   ├── copy.sh         # File copying logic
│   ├── hooks.sh        # Hook execution
│   ├── provider.sh     # GitHub/GitLab provider detection
│   ├── adapters.sh     # Adapter registries, builders, and loaders
│   └── commands/       # Command handlers (one file per command)
│       ├── create.sh   # cmd_create + helpers
│       ├── remove.sh   # cmd_remove
│       ├── rename.sh   # cmd_rename
│       ├── ...         # (16 files total, one per command)
│       └── help.sh     # cmd_help
├── adapters/           # Custom adapter overrides (non-registry)
│   ├── editor/nano.sh  # nano (custom terminal behavior)
│   └── ai/             # claude.sh, cursor.sh (custom logic)
├── completions/        # Shell completions (bash, zsh, fish)
└── templates/          # Example configs and scripts
```

### Coding Standards

#### Shell Script Best Practices

- **Bash requirement**: All scripts use Bash (use `#!/usr/bin/env bash`)
- **Set strict mode**: Use `set -e` to exit on errors
- **Quote variables**: Always quote variables: `"$var"`
- **Use local variables**: Declare function-local vars with `local`
- **Error handling**: Check return codes and provide clear error messages
- **Target Bash 3.2+**: Code runs on Bash 3.2+ (macOS default), but Bash 4.0+ features (like globstar) are allowed where appropriate

#### Code Style

- **Function names**: Use `snake_case` for functions
- **Variable names**: Use `snake_case` for variables
- **Constants**: Use `UPPER_CASE` for constants/env vars
- **Indentation**: 2 spaces (no tabs)
- **Line length**: Keep lines under 100 characters when possible
- **Comments**: Add comments for complex logic

#### Example:

```bash
#!/usr/bin/env bash
# Brief description of what this file does

# Function description
do_something() {
  local input="$1"
  local result

  if [ -z "$input" ]; then
    log_error "Input required"
    return 1
  fi

  result=$(some_command "$input")
  printf "%s" "$result"
}
```

### Adding New Features

#### Adding an Editor Adapter

Most editors follow a standard pattern and can be added as a **registry entry** in `lib/adapters.sh` (no separate file needed).

**Option A: Registry entry** (preferred for standard editors)

Add a line to `_EDITOR_REGISTRY` in `lib/adapters.sh`:

```
yourname|yourcmd|standard|YourEditor not found. Install from https://...|flags
```

Format: `name|cmd|type|err_msg|flags` where:
- `type`: `standard` (GUI app) or `terminal` (runs in current terminal)
- `flags`: comma-separated — `workspace` (supports .code-workspace files), `background` (run in background)

**Option B: Custom adapter file** (for editors with non-standard behavior)

Create `adapters/editor/yourname.sh` implementing `editor_can_open()` and `editor_open()`. See `adapters/editor/nano.sh` for an example.

**Also update**: README.md, all three completion files, help text in `lib/commands/help.sh`.

#### Adding an AI Tool Adapter

**Option A: Registry entry** (preferred for standard CLI tools)

Add a line to `_AI_REGISTRY` in `lib/adapters.sh`:

```
yourname|yourcmd|YourTool not found. Install with: ...|Extra info line 1;Extra info line 2
```

Format: `name|cmd|err_msg|info_lines` (info lines are semicolon-separated).

**Option B: Custom adapter file** (for tools with non-standard behavior)

Create `adapters/ai/yourname.sh` implementing `ai_can_start()` and `ai_start()`. See `adapters/ai/claude.sh` for an example.

**Also update**: README.md, completions, help text.

#### Adding Core Features

For changes to core functionality (`lib/*.sh`):

1. **Discuss first**: Open an issue to discuss the change
2. **Maintain compatibility**: Avoid breaking existing configs
3. **Add tests**: Provide test cases or manual testing instructions
4. **Update docs**: Update README.md and help text
5. **Consider edge cases**: Think about error conditions

### Testing

Currently, testing is manual. Please test your changes on:

1. **macOS** (if available)
2. **Linux** (Ubuntu, Fedora, or Arch recommended)
3. **Windows Git Bash** (if available)

#### Manual Testing Checklist

- [ ] Create worktree with branch name
- [ ] Create worktree with branch containing slashes (e.g., feature/auth)
- [ ] Create from remote branch
- [ ] Create from local branch
- [ ] Create new branch
- [ ] Open in editor (if testing adapters)
- [ ] Run AI tool (if testing adapters)
- [ ] Remove worktree by branch name
- [ ] List worktrees
- [ ] Test configuration commands
- [ ] Test completions (tab completion works)
- [ ] Test `git gtr go 1` for main repo
- [ ] Test `git gtr go <branch>` for worktrees

### Pull Request Process

1. **Fork the repository**
2. **Create a feature branch**: `git checkout -b feature/my-feature`
3. **Make your changes**
4. **Test thoroughly** (see checklist above)
5. **Update documentation** (README.md, help text, etc.)
6. **Commit with clear messages**:
   - Use present tense: "Add feature" not "Added feature"
   - Be descriptive: "Add VS Code adapter" not "Add adapter"
7. **Push to your fork**
8. **Open a Pull Request** with:
   - Clear description of changes
   - Link to related issues
   - Testing performed
   - Screenshots/examples if applicable

### Commit Message Format

```
<type>: <short description>

<optional longer description>

<optional footer>
```

**Types:**

- `feat`: New feature
- `fix`: Bug fix
- `docs`: Documentation changes
- `refactor`: Code refactoring (no functional changes)
- `test`: Adding or updating tests
- `chore`: Maintenance tasks

**Examples:**

```
feat: add JetBrains IDE adapter

Add support for opening worktrees in IntelliJ, PyCharm, and other
JetBrains IDEs via the 'idea' command.

Closes #42
```

```
fix: handle spaces in worktree paths

Properly quote paths in all commands to support directories with spaces.
```

## Design Principles

When contributing, please keep these principles in mind:

1. **Cross-platform first** - Code should work on macOS, Linux, and Windows
2. **No external dependencies** - Avoid requiring tools beyond git and basic shell
3. **Config over code** - Prefer configuration over hardcoding behavior
4. **Fail safely** - Validate inputs and provide clear error messages
5. **Stay modular** - Keep functions small and focused
6. **User-friendly** - Prioritize good UX and clear documentation

## Community

- **Be respectful** and constructive
- **Help others** who are learning
- **Share knowledge** and best practices
- **Have fun!** This is a community project

## Questions?

- Open an issue for questions
- Check existing issues and docs first
- Be patient - maintainers are volunteers

Thank you for contributing! 🎉
