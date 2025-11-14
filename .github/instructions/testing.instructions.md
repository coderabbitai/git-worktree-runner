---
applyTo: bin/gtr, lib/**/*.sh, adapters/**/*.sh
---

# Testing Instructions

Run after core or adapter changes; all manual (no automated tests).

```bash
# Basic create/remove
./bin/gtr new test-feature           # folder test-feature
./bin/gtr rm test-feature            # removed

# Branch sanitization
./bin/gtr new feature/auth           # folder feature-auth

# Remote branch (if exists)
./bin/gtr new existing-remote-branch # checks out tracking branch

# Local existing branch
./bin/gtr new existing-local-branch  # reuses local branch

# New branch creation
./bin/gtr new brand-new-feature      # creates branch + worktree

# Force multiple worktrees same branch
./bin/gtr new test-feature --force --name backend   # test-feature-backend

# Editor + AI adapters
./bin/gtr config set gtr.editor.default cursor
./bin/gtr open test-feature
./bin/gtr config set gtr.ai.default claude
./bin/gtr ai test-feature

# Listing
./bin/gtr list                       # human table
./bin/gtr list --porcelain           # path\tbranch\tstatus

# Navigation
cd "$(./bin/gtr go 1)"               # repo root
cd "$(./bin/gtr go test-feature)"    # worktree path

# Config commands
./bin/gtr config set gtr.editor.default cursor
./bin/gtr config get gtr.editor.default
./bin/gtr config set gtr.editor.default vscode --global
./bin/gtr config unset gtr.editor.default

# Copy patterns
git config --add gtr.copy.include "**/.env.example"
git config --add gtr.copy.exclude "**/.env"
./bin/gtr new test-copy              # copies example, not real env

# Hooks
git config --add gtr.hook.postCreate "echo 'Created!' > /tmp/gtr-test"
./bin/gtr new test-hooks             # /tmp/gtr-test exists
git config --add gtr.hook.postRemove "echo 'Removed!' > /tmp/gtr-removed"
./bin/gtr rm test-hooks              # /tmp/gtr-removed exists
```

## Installation & Environment Verification

```bash
git --version
./bin/gtr doctor      # checks repo, adapters, platform
./bin/gtr adapter     # lists editors + AI tools
```

## Adapter Sourcing Checks

```bash
bash -c 'source adapters/editor/cursor.sh && editor_can_open && echo OK'
bash -c 'source adapters/ai/claude.sh && ai_can_start && echo OK'
```

## Debugging Toolkit

```bash
bash -x ./bin/gtr new test-feature   # global trace
set -x; create_worktree ...; set +x  # scoped trace inside function
declare -f resolve_target            # confirm function loaded
echo "DEBUG worktree_path=$worktree_path" >&2  # variable inspection
```

## Success Criteria

- All commands exit 0 (except intentional failures) and produce expected side-effects.
- No unquoted path errors; spaces handled.
- Hooks run only once per creation/removal.
- `list --porcelain` stable for scripting.

## When Adding Features

- Extend this matrix minimally (keep concise).
- Prefer adding under relevant section (e.g. new flag under create/remove).
