# Fish completion for gtr

# Commands
complete -c gtr -f -n "__fish_use_subcommand" -a "new" -d "Create a new worktree"
complete -c gtr -f -n "__fish_use_subcommand" -a "go" -d "Navigate to worktree"
complete -c gtr -f -n "__fish_use_subcommand" -a "rm" -d "Remove worktree(s)"
complete -c gtr -f -n "__fish_use_subcommand" -a "editor" -d "Open worktree in editor"
complete -c gtr -f -n "__fish_use_subcommand" -a "ai" -d "Start AI coding tool"
complete -c gtr -f -n "__fish_use_subcommand" -a "ls" -d "List all worktrees"
complete -c gtr -f -n "__fish_use_subcommand" -a "list" -d "List all worktrees"
complete -c gtr -f -n "__fish_use_subcommand" -a "clean" -d "Remove stale worktrees"
complete -c gtr -f -n "__fish_use_subcommand" -a "doctor" -d "Health check"
complete -c gtr -f -n "__fish_use_subcommand" -a "adapter" -d "List available adapters"
complete -c gtr -f -n "__fish_use_subcommand" -a "config" -d "Manage configuration"
complete -c gtr -f -n "__fish_use_subcommand" -a "version" -d "Show version"
complete -c gtr -f -n "__fish_use_subcommand" -a "help" -d "Show help"

# New command options
complete -c gtr -n "__fish_seen_subcommand_from new" -l from -d "Base ref" -r
complete -c gtr -n "__fish_seen_subcommand_from new" -l track -d "Track mode" -r -a "auto remote local none"
complete -c gtr -n "__fish_seen_subcommand_from new" -l no-copy -d "Skip file copying"
complete -c gtr -n "__fish_seen_subcommand_from new" -l no-fetch -d "Skip git fetch"
complete -c gtr -n "__fish_seen_subcommand_from new" -l force -d "Allow same branch in multiple worktrees"
complete -c gtr -n "__fish_seen_subcommand_from new" -l name -d "Custom folder name suffix" -r
complete -c gtr -n "__fish_seen_subcommand_from new" -l yes -d "Non-interactive mode"

# Remove command options
complete -c gtr -n "__fish_seen_subcommand_from rm" -l delete-branch -d "Delete branch"
complete -c gtr -n "__fish_seen_subcommand_from rm" -l force -d "Force removal even if dirty"
complete -c gtr -n "__fish_seen_subcommand_from rm" -l yes -d "Non-interactive mode"

# Config command
complete -c gtr -n "__fish_seen_subcommand_from config" -f -a "get set unset"
complete -c gtr -n "__fish_seen_subcommand_from config; and __fish_seen_subcommand_from get set unset" -f -a "\
  gtr.worktrees.dir\t'Worktrees base directory'
  gtr.worktrees.prefix\t'Worktree folder prefix'
  gtr.defaultBranch\t'Default branch'
  gtr.editor.default\t'Default editor'
  gtr.ai.default\t'Default AI tool'
  gtr.copy.include\t'Files to copy'
  gtr.copy.exclude\t'Files to exclude'
  gtr.hook.postCreate\t'Post-create hook'
  gtr.hook.postRemove\t'Post-remove hook'
"

# Helper function to get branch names and special '1' for main repo
function __gtr_worktree_branches
  # Special ID for main repo
  echo "1"
  # Get branch names
  git branch --format='%(refname:short)' 2>/dev/null
end

# Complete branch names for commands that need them
complete -c gtr -n "__fish_seen_subcommand_from go editor ai rm" -f -a "(__gtr_worktree_branches)"
