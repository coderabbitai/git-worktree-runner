# Fish completion for gtr

# Commands
complete -c gtr -f -n "__fish_use_subcommand" -a "create" -d "Create a new worktree"
complete -c gtr -f -n "__fish_use_subcommand" -a "rm" -d "Remove worktree(s)"
complete -c gtr -f -n "__fish_use_subcommand" -a "remove" -d "Remove worktree(s)"
complete -c gtr -f -n "__fish_use_subcommand" -a "cd" -d "Change to worktree directory"
complete -c gtr -f -n "__fish_use_subcommand" -a "open" -d "Open worktree in editor"
complete -c gtr -f -n "__fish_use_subcommand" -a "ai" -d "Start AI coding tool"
complete -c gtr -f -n "__fish_use_subcommand" -a "list" -d "List all worktrees"
complete -c gtr -f -n "__fish_use_subcommand" -a "config" -d "Manage configuration"
complete -c gtr -f -n "__fish_use_subcommand" -a "version" -d "Show version"
complete -c gtr -f -n "__fish_use_subcommand" -a "help" -d "Show help"

# Create command options
complete -c gtr -n "__fish_seen_subcommand_from create" -l branch -d "Branch name" -r
complete -c gtr -n "__fish_seen_subcommand_from create" -l id -d "Worktree ID" -r
complete -c gtr -n "__fish_seen_subcommand_from create" -l auto -d "Auto-assign ID"
complete -c gtr -n "__fish_seen_subcommand_from create" -l from -d "Base ref" -r
complete -c gtr -n "__fish_seen_subcommand_from create" -l track -d "Track mode" -r -a "auto remote local none"
complete -c gtr -n "__fish_seen_subcommand_from create" -l open -d "Open in editor" -r -a "cursor vscode zed"
complete -c gtr -n "__fish_seen_subcommand_from create" -l ai -d "AI tool" -r -a "aider claudecode codex cursor continue"
complete -c gtr -n "__fish_seen_subcommand_from create" -l no-copy -d "Skip file copying"
complete -c gtr -n "__fish_seen_subcommand_from create" -l yes -d "Non-interactive mode"

# Remove command options
complete -c gtr -n "__fish_seen_subcommand_from rm remove" -l delete-branch -d "Delete branch"
complete -c gtr -n "__fish_seen_subcommand_from rm remove" -l yes -d "Non-interactive mode"

# Open command options
complete -c gtr -n "__fish_seen_subcommand_from open" -l editor -d "Editor name" -r -a "cursor vscode zed"

# AI command options
complete -c gtr -n "__fish_seen_subcommand_from ai" -l tool -d "AI tool name" -r -a "aider claudecode codex cursor continue"

# Config command
complete -c gtr -n "__fish_seen_subcommand_from config" -f -a "get set unset"
complete -c gtr -n "__fish_seen_subcommand_from config; and __fish_seen_subcommand_from get set unset" -f -a "\
  gtr.worktrees.dir\t'Worktrees base directory'
  gtr.worktrees.prefix\t'Worktree name prefix'
  gtr.worktrees.startId\t'Starting ID'
  gtr.defaultBranch\t'Default branch'
  gtr.editor.default\t'Default editor'
  gtr.ai.default\t'Default AI tool'
  gtr.copy.include\t'Files to copy'
  gtr.copy.exclude\t'Files to exclude'
  gtr.hook.postCreate\t'Post-create hook'
  gtr.hook.postRemove\t'Post-remove hook'
"

# Helper function to get worktree IDs
function __gtr_worktree_ids
  # Use gtr ids command for config-aware completion
  command gtr ids 2>/dev/null
end

# Complete worktree IDs for commands that need them
complete -c gtr -n "__fish_seen_subcommand_from cd open ai rm remove" -f -a "(__gtr_worktree_ids)"
