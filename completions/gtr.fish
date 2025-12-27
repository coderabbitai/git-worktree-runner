# Fish completion for git gtr
#
# This completion integrates with fish's completion system by registering completions
# for the "git" command with custom predicates that detect "git gtr" usage.
#
# Installation:
#   Symlink to fish's completions directory:
#     ln -s /path/to/git-worktree-runner/completions/gtr.fish ~/.config/fish/completions/
#   Then reload fish:
#     exec fish

# Helper function to check if we're in 'git gtr' context
function __fish_git_gtr_needs_command
  set -l cmd (commandline -opc)
  if [ (count $cmd) -eq 2 -a "$cmd[1]" = "git" -a "$cmd[2]" = "gtr" ]
    return 0
  end
  return 1
end

function __fish_git_gtr_using_command
  set -l cmd (commandline -opc)
  if [ (count $cmd) -ge 3 -a "$cmd[1]" = "git" -a "$cmd[2]" = "gtr" ]
    for i in $argv
      if [ "$cmd[3]" = "$i" ]
        return 0
      end
    end
  end
  return 1
end

# Commands
complete -f -c git -n '__fish_git_gtr_needs_command' -a new -d 'Create a new worktree'
complete -f -c git -n '__fish_git_gtr_needs_command' -a go -d 'Navigate to worktree'
complete -f -c git -n '__fish_git_gtr_needs_command' -a run -d 'Execute command in worktree'
complete -f -c git -n '__fish_git_gtr_needs_command' -a rm -d 'Remove worktree(s)'
complete -f -c git -n '__fish_git_gtr_needs_command' -a copy -d 'Copy files between worktrees'
complete -f -c git -n '__fish_git_gtr_needs_command' -a editor -d 'Open worktree in editor'
complete -f -c git -n '__fish_git_gtr_needs_command' -a ai -d 'Start AI coding tool'
complete -f -c git -n '__fish_git_gtr_needs_command' -a ls -d 'List all worktrees'
complete -f -c git -n '__fish_git_gtr_needs_command' -a list -d 'List all worktrees'
complete -f -c git -n '__fish_git_gtr_needs_command' -a clean -d 'Remove stale worktrees'
complete -f -c git -n '__fish_git_gtr_needs_command' -a doctor -d 'Health check'
complete -f -c git -n '__fish_git_gtr_needs_command' -a adapter -d 'List available adapters'
complete -f -c git -n '__fish_git_gtr_needs_command' -a config -d 'Manage configuration'
complete -f -c git -n '__fish_git_gtr_needs_command' -a version -d 'Show version'
complete -f -c git -n '__fish_git_gtr_needs_command' -a help -d 'Show help'

# New command options
complete -c git -n '__fish_git_gtr_using_command new' -l from -d 'Base ref' -r
complete -c git -n '__fish_git_gtr_using_command new' -l from-current -d 'Create from current branch'
complete -c git -n '__fish_git_gtr_using_command new' -l track -d 'Track mode' -r -a 'auto remote local none'
complete -c git -n '__fish_git_gtr_using_command new' -l no-copy -d 'Skip file copying'
complete -c git -n '__fish_git_gtr_using_command new' -l no-fetch -d 'Skip git fetch'
complete -c git -n '__fish_git_gtr_using_command new' -l force -d 'Allow same branch in multiple worktrees'
complete -c git -n '__fish_git_gtr_using_command new' -l name -d 'Custom folder name suffix' -r
complete -c git -n '__fish_git_gtr_using_command new' -l yes -d 'Non-interactive mode'

# Remove command options
complete -c git -n '__fish_git_gtr_using_command rm' -l delete-branch -d 'Delete branch'
complete -c git -n '__fish_git_gtr_using_command rm' -l force -d 'Force removal even if dirty'
complete -c git -n '__fish_git_gtr_using_command rm' -l yes -d 'Non-interactive mode'

# Copy command options
complete -c git -n '__fish_git_gtr_using_command copy' -s n -l dry-run -d 'Preview without copying'
complete -c git -n '__fish_git_gtr_using_command copy' -s a -l all -d 'Copy to all worktrees'
complete -c git -n '__fish_git_gtr_using_command copy' -l from -d 'Source worktree' -r

# Config command
complete -f -c git -n '__fish_git_gtr_using_command config' -a 'get set add unset'
complete -f -c git -n '__fish_git_gtr_using_command config' -a "
  gtr.worktrees.dir\t'Worktrees base directory'
  gtr.worktrees.prefix\t'Worktree folder prefix'
  gtr.defaultBranch\t'Default branch'
  gtr.editor.default\t'Default editor'
  gtr.ai.default\t'Default AI tool'
  gtr.copy.include\t'Files to copy'
  gtr.copy.exclude\t'Files to exclude'
  gtr.copy.includeDirs\t'Directories to copy (e.g., node_modules)'
  gtr.copy.excludeDirs\t'Directories to exclude'
  gtr.hook.postCreate\t'Post-create hook'
  gtr.hook.preRemove\t'Pre-remove hook (abort on failure)'
  gtr.hook.postRemove\t'Post-remove hook'
"

# Helper function to get branch names and special '1' for main repo
function __gtr_worktree_branches
  # Special ID for main repo
  echo '1'
  # Get branch names
  git branch --format='%(refname:short)' 2>/dev/null
end

# Complete branch names for commands that need them
complete -f -c git -n '__fish_git_gtr_using_command go' -a '(__gtr_worktree_branches)'
complete -f -c git -n '__fish_git_gtr_using_command run' -a '(__gtr_worktree_branches)'
complete -f -c git -n '__fish_git_gtr_using_command copy' -a '(__gtr_worktree_branches)'
complete -f -c git -n '__fish_git_gtr_using_command editor' -a '(__gtr_worktree_branches)'
complete -f -c git -n '__fish_git_gtr_using_command ai' -a '(__gtr_worktree_branches)'
complete -f -c git -n '__fish_git_gtr_using_command rm' -a '(__gtr_worktree_branches)'
