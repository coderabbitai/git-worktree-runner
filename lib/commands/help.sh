#!/usr/bin/env bash

# ── Per-command help functions ───────────────────────────────────────────────
# Each _help_<command>() provides detailed help for a single command.
# Dispatched by cmd_help when a command argument is provided.

_help_new() {
  cat <<'EOF'
git gtr new - Create a new worktree

Usage: git gtr new <branch> [options]

Creates a new git worktree with the given branch name. The worktree folder
is named after the branch (slashes and special chars become hyphens, e.g.,
feature/user-auth becomes folder "feature-user-auth").

Options:
  --from <ref>        Create from a specific ref (default: default branch)
  --from-current      Create from the current branch (for parallel variants)
  --track <mode>      Branch tracking mode: auto|remote|local|none (default: auto)
                      auto: tries remote first, then local, then creates new
  --no-copy           Skip file copying (gtr.copy.include patterns)
  --no-fetch          Skip git fetch before creating
  --no-hooks          Skip post-create hooks
  --force             Allow same branch in multiple worktrees
                      (requires --name or --folder to distinguish them)
  --name <suffix>     Custom folder name suffix (appended after branch name)
  --folder <name>     Custom folder name (replaces default entirely)
  --yes               Non-interactive mode (skip prompts)
  -e, --editor        Open in editor after creation
  -a, --ai            Start AI tool after creation

Examples:
  git gtr new feature/user-auth                 # Folder: feature-user-auth
  git gtr new hotfix --from v2.0.0              # Branch from tag
  git gtr new my-feature --from-current         # Branch from current HEAD
  git gtr new feature -e -a                     # Create, open editor + AI
  git gtr new feature --force --name backend    # Second worktree for same branch
  git gtr new feature --folder my-dir           # Custom folder name
EOF
}

_help_editor() {
  cat <<'EOF'
git gtr editor - Open worktree in editor

Usage: git gtr editor <branch> [--editor <name>]

Opens the specified worktree in your configured editor. Uses the default
editor from gtr.editor.default config, or the --editor flag to override.

Options:
  --editor <name>     Override the default editor for this invocation

Special:
  Use '1' to open the main repo root: git gtr editor 1

Available editors:
  antigravity, atom, cursor, emacs, idea, nano, nvim, pycharm, sublime, vim,
  vscode, webstorm, zed, none (or any command in your PATH)

Examples:
  git gtr editor my-feature                     # Uses default editor
  git gtr editor my-feature --editor vscode     # Override with vscode
  git gtr editor 1                              # Open main repo
EOF
}

_help_ai() {
  cat <<'EOF'
git gtr ai - Start AI coding tool in worktree

Usage: git gtr ai <branch> [--ai <name>] [-- args...]

Starts your configured AI coding tool in the specified worktree. Uses the
default AI tool from gtr.ai.default config, or the --ai flag to override.
Arguments after -- are passed through to the AI tool.

Options:
  --ai <name>         Override the default AI tool for this invocation

Special:
  Use '1' to start AI in the main repo root: git gtr ai 1

Available AI tools:
  aider, auggie, claude, codex, continue, copilot, cursor, gemini,
  opencode, none (or any command in your PATH)

Examples:
  git gtr ai my-feature                         # Uses default AI tool
  git gtr ai my-feature --ai aider              # Override with aider
  git gtr ai my-feature -- --verbose            # Pass args to AI tool
  git gtr ai 1                                  # AI in main repo
EOF
}

_help_go() {
  cat <<'EOF'
git gtr go - Print worktree path

Usage: git gtr go <branch>

Prints the absolute path to the specified worktree. Useful for navigation
with cd or for scripting. For direct cd support, use shell integration:
  eval "$(git gtr init bash)"    # then: gtr cd <branch>
  (output is cached automatically for fast startup)

Special:
  Use '1' for the main repo root: git gtr go 1

Examples:
  git gtr go my-feature                         # Print path
  cd "$(git gtr go my-feature)"                 # Navigate to worktree
  gtr cd my-feature                             # With shell integration
EOF
}

_help_run() {
  cat <<'EOF'
git gtr run - Execute command in worktree

Usage: git gtr run <branch> <command...>

Runs the specified command in the worktree directory. The command and all
its arguments are executed with the worktree as the working directory.

Special:
  Use '1' to run in the main repo root: git gtr run 1 <command>

Examples:
  git gtr run my-feature npm test               # Run tests
  git gtr run my-feature git status             # Check git status
  git gtr run my-feature npm run dev            # Start dev server
  git gtr run 1 npm run build                   # Build in main repo
EOF
}

_help_list() {
  cat <<'EOF'
git gtr list - List all worktrees

Usage: git gtr list [--porcelain]
       git gtr ls [--porcelain]

Shows all git worktrees for the current repository in a formatted table.

Options:
  --porcelain         Machine-readable output (one worktree per line)

Examples:
  git gtr list                                  # Human-readable table
  git gtr ls --porcelain                        # Machine-readable output
EOF
}

_help_rm() {
  cat <<'EOF'
git gtr rm - Remove worktree(s)

Usage: git gtr rm <branch> [<branch>...] [options]

Removes one or more worktrees by branch name. Runs pre-remove and
post-remove hooks unless --force is used to override hook failures.

Options:
  --delete-branch     Also delete the git branch after removing the worktree
  --force             Force removal even if worktree has uncommitted changes
  --yes               Skip confirmation prompts

Examples:
  git gtr rm my-feature                         # Remove worktree
  git gtr rm my-feature --delete-branch         # Remove worktree + branch
  git gtr rm feat-1 feat-2 feat-3               # Remove multiple
  git gtr rm my-feature --force --yes           # Force, no prompts
EOF
}

_help_mv() {
  cat <<'EOF'
git gtr mv - Rename worktree and branch

Usage: git gtr mv <old> <new> [options]
       git gtr rename <old> <new> [options]

Renames both the worktree folder and its local branch. The remote branch
is not renamed (push the new branch and delete the old one manually).

Options:
  --force             Force move even if worktree is locked
  --yes               Skip confirmation prompts

Examples:
  git gtr mv feature-wip feature-auth           # Rename worktree + branch
  git gtr rename old-name new-name              # Alias for mv
  git gtr mv locked-wt new-name --force         # Force move if locked
EOF
}

_help_copy() {
  cat <<'EOF'
git gtr copy - Copy files between worktrees

Usage: git gtr copy <target>... [options] [-- <pattern>...]

Copies files from the main repo (or another worktree) to the specified
target worktree(s). Uses gtr.copy.include/exclude config patterns by
default. Patterns after -- override configured patterns.

Options:
  -n, --dry-run       Preview what would be copied without copying
  -a, --all           Copy to all worktrees
  --from <source>     Copy from a different worktree (default: main repo)

Patterns:
  Glob patterns like ".env*", "*.json", "**/.env*" are supported.
  Configure defaults: git gtr config add gtr.copy.include ".env*"

Examples:
  git gtr copy my-feature                       # Uses configured patterns
  git gtr copy my-feature -- ".env*"            # Explicit pattern
  git gtr copy my-feature -- ".env*" "*.json"   # Multiple patterns
  git gtr copy -a -- ".env*"                    # Update all worktrees
  git gtr copy my-feature -n -- "**/.env*"      # Dry-run preview
  git gtr copy feat --from other-feat           # Copy between worktrees
EOF
}

_help_config() {
  cat <<'EOF'
git gtr config - Manage configuration

Usage: git gtr config [list] [--local|--global|--system]
       git gtr config get <key> [--local|--global|--system]
       git gtr config set <key> <value> [--local|--global]
       git gtr config add <key> <value> [--local|--global]
       git gtr config unset <key> [--local|--global]

Manages gtr configuration stored in git config. Supports local (repo),
global (user), and system scopes. Team defaults can also be set in
.gtrconfig (gitconfig syntax, committed to repo).

Actions:
  list      Show all gtr.* config values (default when no args)
  get       Read a config value (merged from all sources by default)
  set       Set a single value (replaces existing)
  add       Add a value (for multi-valued keys like hooks, copy patterns)
  unset     Remove a config value

Scope flags:
  --local   Target local git config (.git/config)
  --global  Target global git config (~/.gitconfig)
  --system  Read-only for list/get (write requires root)

Examples:
  git gtr config                                # List all config
  git gtr config list --local                   # List local config only
  git gtr config set gtr.editor.default cursor  # Set default editor
  git gtr config add gtr.copy.include ".env*"   # Add copy pattern
  git gtr config get gtr.ai.default             # Get AI tool setting
  git gtr config unset gtr.worktrees.prefix     # Remove prefix setting
EOF
}

_help_doctor() {
  cat <<'EOF'
git gtr doctor - Health check

Usage: git gtr doctor

Verifies your setup: git installation, repo state, worktrees directory,
configured editor, configured AI tool, OS detection, and hosting provider.
Shows actionable guidance for any issues found.

Examples:
  git gtr doctor                                # Run health check
EOF
}

_help_adapter() {
  cat <<'EOF'
git gtr adapter - List available adapters

Usage: git gtr adapter

Lists all built-in editor and AI tool adapters, along with their availability
on the current system. Any command in your PATH can also be used as an
editor or AI tool without a built-in adapter.

Examples:
  git gtr adapter                               # Show all adapters
EOF
}

_help_clean() {
  cat <<'EOF'
git gtr clean - Remove stale worktrees

Usage: git gtr clean [options]

Removes empty worktree directories and optionally removes worktrees whose
PRs/MRs have been merged. Auto-detects GitHub (gh) or GitLab (glab) from
the remote URL.

Options:
  --merged            Also remove worktrees with merged PRs/MRs
  --yes, -y           Skip confirmation prompts
  --dry-run, -n       Show what would be removed without removing

Examples:
  git gtr clean                                 # Clean empty directories
  git gtr clean --merged                        # Also clean merged PRs
  git gtr clean --merged --dry-run              # Preview merged cleanup
  git gtr clean --merged --yes                  # Auto-confirm everything
EOF
}

_help_completion() {
  cat <<'EOF'
git gtr completion - Generate shell completions

Usage: git gtr completion <shell>

Generates shell completion script for the specified shell. Add to your
shell configuration for tab completion of git gtr commands and options.

Supported shells: bash, zsh, fish

Setup:
  # Bash (add to ~/.bashrc)
  eval "$(git gtr completion bash)"

  # Zsh (add to ~/.zshrc BEFORE compinit)
  eval "$(git gtr completion zsh)"

  # Fish (symlink to completions dir)
  ln -s /path/to/completions/git-gtr.fish ~/.config/fish/completions/
EOF
}

_help_init() {
  cat <<'EOF'
git gtr init - Generate shell integration

Usage: git gtr init <shell> [--as <name>]

Generates shell functions for enhanced features like 'gtr cd <branch>'
which changes directory to a worktree. Add to your shell configuration.

Output is cached to ~/.cache/gtr/ for fast shell startup (~1ms vs ~60ms).
The cache auto-invalidates when git-gtr is updated. To force-regenerate:
  rm -rf ~/.cache/gtr

Supported shells: bash, zsh, fish

Options:
  --as <name>   Set custom function name (default: gtr)
                Useful if 'gtr' conflicts with another command (e.g., GNU tr)

Setup (sources cached output directly for fast startup):
  # Bash (add to ~/.bashrc)
  _gtr_init="${XDG_CACHE_HOME:-$HOME/.cache}/gtr/init-gtr.bash"
  [[ -f "$_gtr_init" ]] || eval "$(git gtr init bash)"
  source "$_gtr_init" 2>/dev/null; unset _gtr_init

  # Zsh (add to ~/.zshrc)
  _gtr_init="${XDG_CACHE_HOME:-$HOME/.cache}/gtr/init-gtr.zsh"
  [[ -f "$_gtr_init" ]] || eval "$(git gtr init zsh)"
  source "$_gtr_init" 2>/dev/null; unset _gtr_init

  # Fish (add to ~/.config/fish/config.fish)
  git gtr init fish | source

  # Custom function name (avoids conflict with coreutils gtr)
  eval "$(git gtr init zsh --as gwtr)"

After setup:
  gtr cd my-feature                             # cd to worktree
  gtr cd 1                                      # cd to main repo
  gtr cd                                        # interactive picker (requires fzf)
  gtr <command>                                 # same as git gtr <command>

Command palette (gtr cd with no arguments, requires fzf):
  enter       cd into selected worktree
  ctrl-e      open in editor
  ctrl-a      start AI tool
  ctrl-d      delete worktree (with confirmation)
  ctrl-y      copy files to worktree
  ctrl-r      refresh list
  esc         cancel
EOF
}

_help_version() {
  cat <<'EOF'
git gtr version - Show version

Usage: git gtr version
EOF
}

# ── Main help command ────────────────────────────────────────────────────────

cmd_help() {
  local command="${1:-}"

  # No argument: show full help page
  if [ -z "$command" ]; then
    _help_full
    return 0
  fi

  # Map aliases to canonical names
  case "$command" in
    ls)       command="list" ;;
    rename)   command="mv" ;;
    adapters) command="adapter" ;;
  esac

  # Dispatch to per-command help function
  local help_func="_help_${command//-/_}"
  if type "$help_func" >/dev/null 2>&1; then
    "$help_func"
  else
    log_error "No help available for: $command"
    echo "Use 'git gtr help' for available commands" >&2
    return 1
  fi
}

# Full help page (shown when no command is specified)
_help_full() {
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
  • Run 'git gtr help <command>' for detailed help on any command

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

  init <shell> [--as <name>]
         Generate shell integration for cd support (bash, zsh, fish)
         --as <name>: custom function name (default: gtr)
         Output is cached for fast startup (auto-invalidates on update)
         See git gtr help init for recommended setup
         With fzf: 'gtr cd' opens a command palette (preview, editor, AI, delete)

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
  gtr cd                                    # Interactive picker (requires fzf)
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
                           Options: antigravity, atom, cursor, emacs,
                           idea, nano, nvim, pycharm, sublime, vim,
                           vscode, webstorm, zed, none
  gtr.editor.workspace     Workspace file for VS Code/Cursor/Antigravity
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
  gtr.ui.color             Color output mode (auto, always, never; default: auto)

────────────────────────────────────────────────────────────────────────────────

MORE INFO: https://github.com/coderabbitai/git-worktree-runner
EOF
}
