#!/usr/bin/env bash

# Help command
cmd_help() {
  cat <<'EOF'
git gtr - Git worktree runner

PHILOSOPHY: Configuration over flags. Set defaults once, then use simple commands.

────────────────────────────────────────────────────────────────────────────────

QUICK START:
  cd ~/your-repo                                   # Navigate to git repo first
  git gtr config set gtr.editor.default cursor     # One-time setup
  git gtr config set gtr.ai.default claude         # One-time setup
  git gtr new my-feature                           # Creates worktree in folder "my-feature"
  git gtr editor my-feature                        # Opens in cursor
  git gtr ai my-feature                            # Starts claude
  git gtr rm my-feature                            # Remove when done

────────────────────────────────────────────────────────────────────────────────

KEY CONCEPTS:
  • Worktree folders are named after the branch name
  • Main repo is accessible via special ID '1' (e.g., git gtr go 1, git gtr editor 1)
  • Commands accept branch names to identify worktrees
    Example: git gtr editor my-feature, git gtr go feature/user-auth

────────────────────────────────────────────────────────────────────────────────

CORE COMMANDS (daily workflow):

  new <branch> [options]
         Create a new worktree (folder named after branch)
         --from <ref>: create from specific ref
         --from-current: create from current branch (for parallel variants)
         --track <mode>: tracking mode (auto|remote|local|none)
         --no-copy: skip file copying
         --no-fetch: skip git fetch
         --no-hooks: skip post-create hooks
         --force: allow same branch in multiple worktrees (requires --name or --folder)
         --name <suffix>: custom folder name suffix (e.g., backend, frontend)
         --folder <name>: custom folder name (replaces default, useful for long branches)
         --yes: non-interactive mode
         -e, --editor: open in editor after creation
         -a, --ai: start AI tool after creation

  editor <branch> [--editor <name>]
         Open worktree in editor (uses gtr.editor.default or --editor)
         Special: use '1' to open repo root

  ai <branch> [--ai <name>] [-- args...]
         Start AI coding tool in worktree (uses gtr.ai.default or --ai)
         Special: use '1' to open repo root

  go <branch>
         Print worktree path (tip: use 'gtr cd <branch>' with shell integration)
         Special: use '1' for repo root

  run <branch> <command...>
         Execute command in worktree directory
         Special: use '1' to run in repo root

         Examples:
           git gtr run feature npm test
           git gtr run feature-auth git status
           git gtr run 1 npm run build

  list [--porcelain]
         List all worktrees
         Aliases: ls

  rm <branch> [<branch>...] [options]
         Remove worktree(s) by branch name
         --delete-branch: also delete the branch
         --force: force removal (dirty worktree)
         --yes: skip confirmation

  mv <old> <new> [--force] [--yes]
         Rename worktree and its branch
         Aliases: rename
         --force: force move (locked worktree)
         --yes: skip confirmation
         Note: Only renames local branch. Remote branch unchanged.

         Examples:
           git gtr mv feature-wip feature-auth
           git gtr rename old-name new-name

  copy <target>... [options] [-- <pattern>...]
         Copy files from main repo to worktree(s)
         -n, --dry-run: preview without copying
         -a, --all: copy to all worktrees
         --from <source>: copy from different worktree (default: main repo)
         Patterns after -- override gtr.copy.include config

         Examples:
           git gtr copy my-feature                       # Uses configured patterns
           git gtr copy my-feature -- ".env*"            # Explicit pattern
           git gtr copy my-feature -- ".env*" "*.json"   # Multiple patterns
           git gtr copy -a -- ".env*"                    # Update all worktrees
           git gtr copy my-feature -n -- "**/.env*"      # Dry-run preview

────────────────────────────────────────────────────────────────────────────────

SETUP & MAINTENANCE:

  config [list] [--local|--global|--system]
  config get <key> [--local|--global|--system]
  config {set|add|unset} <key> [value] [--local|--global]
         Manage configuration
         - list: show all gtr.* config values (default when no args)
         - get: read a config value (merged from all sources by default)
         - set: set a single value (replaces existing)
         - add: add a value (for multi-valued configs like hooks, copy patterns)
         - unset: remove a config value
         Without scope flag, list/get show merged config from all sources
         Use --local/--global to target a specific scope for write operations

  doctor
         Health check (verify git, editors, AI tools)

  adapter
         List available editor & AI tool adapters
         Note: Any command in your PATH can be used (e.g., code-insiders, bunx)

  clean [options]
         Remove stale/prunable worktrees and empty directories
         --merged: also remove worktrees with merged PRs/MRs
                   Auto-detects GitHub (gh) or GitLab (glab) from remote URL
                   Override: git gtr config set gtr.provider gitlab
         --yes, -y: skip confirmation prompts
         --dry-run, -n: show what would be removed without removing

  completion <shell>
         Generate shell completions (bash, zsh, fish)
         Usage: eval "$(git gtr completion zsh)"

  init <shell>
         Generate shell integration for cd support (bash, zsh, fish)
         Usage: eval "$(git gtr init bash)"

  version
         Show version

────────────────────────────────────────────────────────────────────────────────

WORKFLOW EXAMPLES:

  # One-time repo setup
  cd ~/GitHub/my-project
  git gtr config set gtr.editor.default cursor
  git gtr config set gtr.ai.default claude

  # Daily workflow
  git gtr new feature/user-auth               # Create worktree (folder: feature-user-auth)
  git gtr editor feature/user-auth            # Open in editor
  git gtr ai feature/user-auth                # Start AI tool

  # Run commands in worktree
  git gtr run feature/user-auth npm test      # Run tests
  git gtr run feature/user-auth npm run dev   # Start dev server

  # Navigate to worktree directory
  gtr cd feature/user-auth                  # With shell integration (git gtr init)
  cd "$(git gtr go feature/user-auth)"      # Without shell integration

  # Override defaults with flags
  git gtr editor feature/user-auth --editor vscode
  git gtr ai feature/user-auth --ai aider

  # Chain commands together
  git gtr new hotfix && git gtr editor hotfix && git gtr ai hotfix

  # Create variant worktrees from current branch (for parallel work)
  git checkout feature/user-auth
  git gtr new variant-1 --from-current        # Creates variant-1 from feature/user-auth
  git gtr new variant-2 --from-current        # Creates variant-2 from feature/user-auth

  # When finished
  git gtr rm feature/user-auth --delete-branch

  # Check setup and available tools
  git gtr doctor
  git gtr adapter

────────────────────────────────────────────────────────────────────────────────

CONFIGURATION OPTIONS:

  gtr.worktrees.dir        Worktrees base directory
  gtr.worktrees.prefix     Worktree folder prefix (default: "")
  gtr.defaultBranch        Default branch (default: auto)
  gtr.editor.default       Default editor
                           Options: cursor, vscode, zed, idea, pycharm,
                           webstorm, vim, nvim, emacs, sublime, nano,
                           atom, none
  gtr.editor.workspace     Workspace file for VS Code/Cursor
                           (relative path, auto-detects, or "none")
  gtr.ai.default           Default AI tool
                           Options: aider, auggie, claude, codex, continue,
                           copilot, cursor, gemini, opencode, none
  gtr.copy.include         Files to copy (multi-valued)
  gtr.copy.exclude         Files to exclude (multi-valued)
  gtr.copy.includeDirs     Directories to copy (multi-valued)
                           Example: node_modules, .venv, vendor
                           WARNING: May include sensitive files!
                           Use gtr.copy.excludeDirs to exclude them.
  gtr.copy.excludeDirs     Directories to exclude (multi-valued)
                           Supports glob patterns (e.g., "node_modules/.cache", "*/.npm")
  gtr.hook.postCreate      Post-create hooks (multi-valued)
  gtr.hook.preRemove       Pre-remove hooks (multi-valued, abort on failure)
  gtr.hook.postRemove      Post-remove hooks (multi-valued)
  gtr.hook.postCd          Post-cd hooks (multi-valued, shell integration only)

────────────────────────────────────────────────────────────────────────────────

MORE INFO: https://github.com/coderabbitai/git-worktree-runner
EOF
}