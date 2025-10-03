# Contributing to gtr

Thank you for considering contributing to `gtr`! This document provides guidelines and instructions for contributing.

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
├── bin/gtr              # Main executable dispatcher
├── lib/                 # Core functionality
│   ├── core.sh         # Git worktree operations
│   ├── config.sh       # Configuration (git-config wrapper)
│   ├── platform.sh     # OS-specific utilities
│   ├── ui.sh           # User interface (logging, prompts)
│   ├── copy.sh         # File copying logic
│   └── hooks.sh        # Hook execution
├── adapters/           # Pluggable integrations
│   ├── editor/         # Editor adapters (cursor, vscode, zed)
│   └── ai/             # AI tool adapters (aider)
├── completions/        # Shell completions (bash, zsh, fish)
└── templates/          # Example configs and scripts
```

### Coding Standards

#### Shell Script Best Practices

- **POSIX compliance**: Write POSIX-compatible shell code (use `#!/bin/sh`)
- **Set strict mode**: Use `set -e` to exit on errors
- **Quote variables**: Always quote variables: `"$var"`
- **Use local variables**: Declare function-local vars with `local`
- **Error handling**: Check return codes and provide clear error messages
- **No bashisms**: Avoid bash-specific features unless absolutely necessary

#### Code Style

- **Function names**: Use `snake_case` for functions
- **Variable names**: Use `snake_case` for variables
- **Constants**: Use `UPPER_CASE` for constants/env vars
- **Indentation**: 2 spaces (no tabs)
- **Line length**: Keep lines under 100 characters when possible
- **Comments**: Add comments for complex logic

#### Example:

```sh
#!/bin/sh
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

1. Create `adapters/editor/yourname.sh`:

```sh
#!/bin/sh
# YourEditor adapter

editor_can_open() {
  command -v yourcommand >/dev/null 2>&1
}

editor_open() {
  local path="$1"

  if ! editor_can_open; then
    log_error "YourEditor not found. Install from https://..."
    return 1
  fi

  yourcommand "$path"
}
```

2. Update README.md with setup instructions
3. Update completions to include new editor
4. Test on macOS, Linux, and Windows if possible

#### Adding an AI Tool Adapter

1. Create `adapters/ai/yourtool.sh`:

```sh
#!/bin/sh
# YourTool AI adapter

ai_can_start() {
  command -v yourtool >/dev/null 2>&1
}

ai_start() {
  local path="$1"
  shift

  if ! ai_can_start; then
    log_error "YourTool not found. Install with: ..."
    return 1
  fi

  (cd "$path" && yourtool "$@")
}
```

2. Update README.md
3. Update completions
4. Add example usage

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

- [ ] Create worktree with auto ID
- [ ] Create worktree with specific ID
- [ ] Create from remote branch
- [ ] Create from local branch
- [ ] Create new branch
- [ ] Open in editor (if testing adapters)
- [ ] Run AI tool (if testing adapters)
- [ ] Remove worktree
- [ ] List worktrees
- [ ] Test configuration commands
- [ ] Test completions (tab completion works)

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
