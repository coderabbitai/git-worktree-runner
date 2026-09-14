---
applyTo: bin/git-gtr, bin/gtr, lib/**/*.sh, adapters/**/*.sh, tests/**/*.bats
---

# Testing Instructions

Run the automated checks after any change, then the manual matrix for the areas you touched.

## Automated Checks (CI gates)

```bash
bats tests/                          # BATS suite, 29 files; fixtures in tests/test_helper.bash
bats tests/cmd_list.bats             # one file; add --filter "name" for one test
shellcheck bin/gtr bin/git-gtr lib/*.sh lib/commands/*.sh adapters/editor/*.sh adapters/ai/*.sh
./scripts/generate-completions.sh --check   # committed completions match the generator
```

These three jobs are exactly what `.github/workflows/lint.yml` runs on every pull request.

## Manual Matrix

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

# Machine-readable creation (stdout: path, branch, hook_status records)
./bin/gtr new agent-feature --from HEAD --no-fetch --porcelain

# Force multiple worktrees same branch
./bin/gtr new test-feature --force --name backend   # test-feature-backend

# Editor + AI adapters
./bin/gtr config set gtr.editor.default cursor
./bin/gtr editor test-feature
./bin/gtr config set gtr.ai.default claude
./bin/gtr ai test-feature

# Listing
./bin/gtr list                       # human table
./bin/gtr list --porcelain           # path\tbranch\tstatus

# Navigation
cd "$(./bin/gtr go 1)"               # repo root
cd "$(./bin/gtr go test-feature)"    # worktree path

# Pull request worktrees (needs gh) and PR-based cleanup
./bin/gtr pr 123                     # folder from the PR head branch
./bin/gtr clean --merged --dry-run   # preview, remove nothing

# .gtrconfig trust (hooks and defaults stay inert until approved)
./bin/gtr trust

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
bash -c 'source adapters/editor/nano.sh && editor_can_open && echo OK'
bash -c 'source adapters/ai/claude.sh && ai_can_start && echo OK'
```

## Debugging Toolkit

```bash
bash -x ./bin/gtr new test-feature   # global trace
GTR_DEBUG=1 ./bin/gtr new test-feature  # file:line:function on an unguarded failure
set -x; create_worktree ...; set +x  # scoped trace inside function
declare -f resolve_target            # confirm function loaded
echo "DEBUG worktree_path=$worktree_path" >&2  # variable inspection
```

## Success Criteria

- `bats tests/`, ShellCheck, and `./scripts/generate-completions.sh --check` pass.
- All commands exit 0 (except intentional failures) and produce expected side-effects.
- No unquoted path errors; spaces handled.
- Hooks run only once per creation/removal.
- `new --porcelain` emits only stable records on stdout; progress and hook output use stderr.
- `list --porcelain` stable for scripting.

## When Adding Features

- Add or extend the matching `tests/cmd_<name>.bats`; BATS covers behavior, this matrix covers what BATS cannot (editors, AI tools, shell integration).
- Extend this matrix minimally (keep concise).
- Prefer adding under relevant section (e.g. new flag under create/remove).
