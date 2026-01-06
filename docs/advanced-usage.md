# Advanced Usage Guide

> Advanced workflows and patterns for git-worktree-runner

[Back to README](../README.md) | [Configuration](configuration.md) | [Troubleshooting](troubleshooting.md)

---

## Table of Contents

- [Repository Scoping](#repository-scoping)
- [Working with Multiple Branches](#working-with-multiple-branches)
- [Working with Multiple Repositories](#working-with-multiple-repositories)
- [Custom Workflow Scripts](#custom-workflow-scripts)
- [CI/CD Integration](#cicd-integration)
- [Multiple Worktrees Same Branch](#multiple-worktrees-same-branch)
- [Parallel AI Development](#parallel-ai-development)

---

## Repository Scoping

**gtr is repository-scoped** - each git repository has its own independent set of worktrees:

- Run `git gtr` commands from within any git repository
- Worktree folders are named after their branch names
- Each repo manages its own worktrees independently
- Switch repos with `cd`, then run `git gtr` commands for that repo

---

## Working with Multiple Branches

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

---

## Working with Multiple Repositories

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

---

## Custom Workflow Scripts

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

---

## CI/CD Integration

Perfect for CI/CD or scripts with non-interactive mode:

```bash
# Create worktree without prompts
git gtr new ci-test --yes --no-copy

# Remove without confirmation
git gtr rm ci-test --yes --delete-branch
```

**Flags for automation:**

| Flag              | Description                          |
| ----------------- | ------------------------------------ |
| `--yes`           | Skip all confirmation prompts        |
| `--no-copy`       | Skip file copying (faster)           |
| `--no-fetch`      | Skip git fetch (use existing refs)   |
| `--delete-branch` | Delete branch when removing worktree |

---

## Multiple Worktrees Same Branch

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

### Using `--force` with `--name` (required)

```bash
# Create multiple worktrees for same branch with descriptive names
git gtr new feature-auth                          # Main worktree: feature-auth/
git gtr new feature-auth --force --name backend   # Creates: feature-auth-backend/
git gtr new feature-auth --force --name frontend  # Creates: feature-auth-frontend/
git gtr new feature-auth --force --name tests     # Creates: feature-auth-tests/

# All worktrees are on the same 'feature-auth' branch
# The --name flag is required with --force to distinguish worktrees
```

### Best Practices

- Always provide a descriptive `--name` (backend, frontend, tests, ci, etc.)
- Only edit files in one worktree at a time
- Commit/stash changes before switching worktrees
- Ideal for parallel AI agents working on different parts of one feature
- Use `git gtr list` to see all worktrees and their branches

---

## Parallel AI Development

Run multiple AI agents on the same feature branch, each working on different parts:

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

**Workflow tips:**

1. **Divide by directory** - Have each agent focus on non-overlapping directories (e.g., `src/api/`, `src/components/`, `tests/`)
2. **Frequent commits** - Each agent should commit frequently to avoid conflicts
3. **Pull before push** - Have agents pull changes from others before pushing
4. **Use descriptive names** - Make it clear what each worktree is for

---

[Back to README](../README.md) | [Configuration](configuration.md) | [Troubleshooting](troubleshooting.md)
