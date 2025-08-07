#!/bin/bash
# gtr - Git worktree helper for parallel Claude Code development
# Enhanced for CodeRabbit monorepo workflow

gtr () {
  local cmd="$1"; shift || { echo "Usage: gtr {create|rm|cd|claude|cursor|desktop|list} <name>"; return 1; }

  # Base folder for worktrees (relative to current git repo)
  local repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [ -z "$repo_root" ]; then
    echo "❌ Not in a git repository"
    return 1
  fi
  
  local repo_name=$(basename "$repo_root")
  local base="$(dirname "$repo_root")/${repo_name}-worktrees"

  case "$cmd" in
    create)
      local worktree_id=""
      local branch_name=""
      
      # If no arguments, auto-assign ID starting from 2
      if [ $# -eq 0 ]; then
        # Find the next available worktree id starting from 2
        local id=2
        while [ -d "$base/mono-$id" ]; do
          ((id++))
        done
        worktree_id="$id"
      elif [ $# -eq 1 ]; then
        # One argument - could be branch name (auto-assign ID) or worktree ID
        if [ -d "$base/mono-$1" ]; then
          echo "❌ Worktree mono-$1 already exists"
          return 1
        elif [[ "$1" =~ ^[0-9]+$ ]] || [[ "$1" =~ ^(secondary|third|aux)$ ]]; then
          # Looks like a worktree ID
          worktree_id="$1"
        else
          # Assume it's a branch name, auto-assign ID
          local id=2
          while [ -d "$base/mono-$id" ]; do
            ((id++))
          done
          worktree_id="$id"
          branch_name="$1"
        fi
      else
        # Two arguments: worktree ID and branch name
        worktree_id="$1"
        branch_name="$2"
      fi
      
      local worktree_path="$base/mono-$worktree_id"
      
      # If no branch name provided, prompt for it
      if [ -z "$branch_name" ]; then
        printf "❓ Enter branch name for worktree mono-$worktree_id: "
        read -r branch_name
        if [ -z "$branch_name" ]; then
          echo "❌ Branch name required"
          return 1
        fi
      fi
      
      echo "🚀 Creating worktree: mono-$worktree_id"
      echo "📂 Location: $worktree_path"
      echo "🌿 Branch: $branch_name"
      
      # Check if worktree already exists
      if [ -d "$worktree_path" ]; then
        echo "❌ Worktree mono-$worktree_id already exists at $worktree_path"
        echo "💡 Use GitHub Desktop to switch branches in existing worktree"
        return 1
      fi
      
      # First fetch to ensure we have latest remote refs
      echo "🔄 Fetching remote branches..."
      git fetch origin 2>/dev/null
      
      # Check if branch exists on remote
      if git show-ref --verify --quiet "refs/remotes/origin/$branch_name"; then
        echo "🌿 Branch '$branch_name' exists on remote"
        
        # Check if local branch also exists
        if git show-ref --verify --quiet "refs/heads/$branch_name"; then
          echo "⚠️  Local branch '$branch_name' also exists"
          printf "❓ Use remote branch 'origin/$branch_name'? [Y/n] "
        else
          printf "❓ Create worktree from remote branch 'origin/$branch_name'? [Y/n] "
        fi
        
        read -r reply
        case "$reply" in
          [nN]|[nN][oO])
            echo "❌ Aborted"
            return 1
            ;;
          *)
            echo "🌿 Creating worktree from remote branch"
            # Create worktree with a new local branch tracking the remote
            if git worktree add "$worktree_path" -b "$branch_name" "origin/$branch_name" 2>/dev/null || \
               git worktree add "$worktree_path" "$branch_name" 2>/dev/null; then
              echo "✅ Worktree created tracking origin/$branch_name"
            else
              echo "❌ Failed to create worktree"
              return 1
            fi
            ;;
        esac
      # Check if branch exists locally
      elif git show-ref --verify --quiet "refs/heads/$branch_name"; then
        echo "⚠️  Branch '$branch_name' exists locally only"
        printf "❓ Use existing local branch '$branch_name'? [y/N] "
        read -r reply
        case "$reply" in
          [yY]|[yY][eE][sS])
            echo "🌿 Using existing local branch: $branch_name"
            
            if git worktree add "$worktree_path" "$branch_name"; then
              echo "✅ Worktree created with existing local branch"
            else
              echo "❌ Failed to create worktree with existing branch"
              return 1
            fi
            ;;
          *)
            echo "❌ Aborted"
            return 1
            ;;
        esac
      else
        echo "🌿 Creating new branch from main"
        
        # Create new branch from main
        if git worktree add "$worktree_path" -b "$branch_name" main; then
          echo "✅ Worktree created successfully"
        else
          echo "❌ Failed to create worktree"
          return 1
        fi
      fi
          
        # Open GitHub Desktop automatically
        echo ""
        echo "🖥️  Opening GitHub Desktop for worktree: mono-$worktree_id"
        open -a "GitHub Desktop" "$worktree_path"
        
        # CodeRabbit-specific setup
        cd "$worktree_path"
        
        # Copy environment files from all services
        echo "📋 Copying .env.local files..."
        cd "$repo_root"
        find . -name ".env.local" -type f | while read -r env_file; do
          # Get the directory path relative to repo root
          rel_dir=$(dirname "$env_file")
          # Create the directory in worktree if needed
          mkdir -p "$worktree_path/$rel_dir"
          # Copy the .env.local file
          cp "$env_file" "$worktree_path/$env_file"
          echo "   ✅ Copied $env_file"
        done
        
        # Copy all CLAUDE.md files preserving directory structure
        echo "📋 Copying CLAUDE.md files..."
        cd "$repo_root"
        find . -name "CLAUDE.md" -type f | while read -r claude_file; do
          # Get the directory path relative to repo root
          rel_dir=$(dirname "$claude_file")
          # Create the directory in worktree if needed
          if [ "$rel_dir" != "." ]; then
            mkdir -p "$worktree_path/$rel_dir"
          fi
          # Copy the CLAUDE.md file
          cp "$claude_file" "$worktree_path/$claude_file"
          echo "   ✅ Copied $claude_file"
        done
        
        # Copy run_services.sh script
        if [ -f "$repo_root/run_services.sh" ]; then
          cp "$repo_root/run_services.sh" "$worktree_path/" && echo "📋 Copied run_services.sh"
          chmod +x "$worktree_path/run_services.sh"
        fi
        cd "$worktree_path"
        
        # Install dependencies if package.json exists
        if [ -f "package.json" ]; then
          echo "📦 Installing dependencies with pnpm..."
          pnpm install
          echo "✅ Dependencies installed"
          
          # Build the project
          echo "🔨 Building the project with turbo..."
          if turbo build; then
            echo "✅ Build completed successfully"
          else
            echo "⚠️  Build completed with warnings/errors"
          fi
        fi
        
        echo "🎯 Navigate with: cd $worktree_path"
        echo "🤖 Start Claude with: gtr claude $worktree_id"
        echo "🖥️  Open GitHub Desktop: gtr desktop $worktree_id"
        echo "💡 Switch branches later using GitHub Desktop"
        cd "$repo_root"
      ;;

    rm|remove)
      if [ $# -eq 0 ]; then
        echo "Usage: gtr rm <worktree-id>"
        echo "Example: gtr rm 2              # Removes mono-2"
        return 1
      fi
      
      for worktree_id in "$@"; do
        local worktree_path="$base/mono-$worktree_id"
        
        echo "🗑️  Removing worktree: mono-$worktree_id"
        
        if [ ! -d "$worktree_path" ]; then
          echo "⚠️  Worktree mono-$worktree_id not found at $worktree_path"
          continue
        fi
        
        # Get the current branch from the worktree
        local current_branch=$(cd "$worktree_path" 2>/dev/null && git branch --show-current)
        
        if git worktree remove "$worktree_path" 2>/dev/null; then
          echo "✅ Worktree removed: $worktree_path"
          
          # Ask if they want to delete the branch too
          if [ -n "$current_branch" ]; then
            printf "❓ Also delete branch '$current_branch'? [y/N] "
            read -r reply
            case "$reply" in
              [yY]|[yY][eE][sS])
                if git branch -D "$current_branch" 2>/dev/null; then
                  echo "✅ Branch deleted: $current_branch"
                fi
                ;;
              *)
                echo "ℹ️  Branch '$current_branch' kept"
                ;;
            esac
          fi
        else
          echo "❌ Failed to remove worktree"
        fi
        echo ""
      done
      ;;

    cd)
      if [ $# -ne 1 ]; then
        echo "Usage: gtr cd <worktree-id>"
        echo "Example: gtr cd 2              # cd to mono-2"
        return 1
      fi
      
      local worktree_id="$1"
      local worktree_path="$base/mono-$worktree_id"
      if [ -d "$worktree_path" ]; then
        cd "$worktree_path"
        local current_branch=$(git branch --show-current)
        echo "📂 Switched to worktree: mono-$worktree_id"
        echo "🌿 Current branch: $current_branch"
      else
        echo "❌ Worktree not found: mono-$worktree_id"
        return 1
      fi
      ;;

    claude)
      if [ $# -ne 1 ]; then
        echo "Usage: gtr claude <worktree-id>"
        echo "Example: gtr claude 2          # Start Claude in mono-2"
        return 1
      fi
      
      local worktree_id="$1"
      local worktree_path="$base/mono-$worktree_id"

      if [ ! -d "$worktree_path" ]; then
        echo "❌ Worktree mono-$worktree_id not found"
        echo "💡 Create it first with: gtr create $worktree_id [branch-name]"
        return 1
      fi

      local current_branch=$(cd "$worktree_path" && git branch --show-current)
      echo "🤖 Starting Claude Code in worktree: mono-$worktree_id"
      echo "📂 Directory: $worktree_path"
      echo "🌿 Current branch: $current_branch"
      
      ( cd "$worktree_path" && claude-code )
      ;;

    cursor)
      if [ $# -ne 1 ]; then
        echo "Usage: gtr cursor <worktree-id>"
        echo "Example: gtr cursor 2          # Open Cursor in mono-2"
        return 1
      fi
      
      local worktree_id="$1"
      local worktree_path="$base/mono-$worktree_id"

      if [ ! -d "$worktree_path" ]; then
        echo "❌ Worktree mono-$worktree_id not found"
        echo "💡 Create it first with: gtr create $worktree_id [branch-name]"
        return 1
      fi

      local current_branch=$(cd "$worktree_path" && git branch --show-current)
      echo "🪟 Opening Cursor in worktree: mono-$worktree_id"
      echo "📂 Directory: $worktree_path"
      echo "🌿 Current branch: $current_branch"
      
      cursor "$worktree_path"
      ;;

    desktop|github)
      if [ $# -ne 1 ]; then
        echo "Usage: gtr desktop <worktree-id>"
        echo "Example: gtr desktop 2         # Open GitHub Desktop for mono-2"
        return 1
      fi
      
      local worktree_id="$1"
      local worktree_path="$base/mono-$worktree_id"

      if [ ! -d "$worktree_path" ]; then
        echo "❌ Worktree mono-$worktree_id not found"
        echo "💡 Create it first with: gtr create $worktree_id [branch-name]"
        return 1
      fi

      local current_branch=$(cd "$worktree_path" && git branch --show-current)
      echo "🖥️  Opening GitHub Desktop for worktree: mono-$worktree_id"
      echo "📂 Directory: $worktree_path"
      echo "🌿 Current branch: $current_branch"
      
      open -a "GitHub Desktop" "$worktree_path"
      ;;

    list|ls)
      echo "📋 Git worktrees:"
      git worktree list
      
      # List worktrees in the worktrees directory
      echo ""
      echo "📁 Worktree directories:"
      if [ -d "$base" ]; then
        ls -la "$base" 2>/dev/null | grep "^d.*mono-" || echo "   (none found)"
      else
        echo "   (worktrees directory doesn't exist yet)"
      fi
      ;;

    help|--help|-h)
      echo "gtr - Git worktree helper for parallel Claude Code development"
      echo ""
      echo "Commands:"
      echo "  create [branch]        Auto-create next worktree (mono-2, mono-3, etc)"
      echo "  create <id> [branch]   Create specific worktree (mono-<id>)"
      echo "  rm <id>                Remove worktree"
      echo "  cd <id>                Change to worktree directory"
      echo "  claude <id>            Start Claude Code in worktree"
      echo "  cursor <id>            Open Cursor editor in worktree"
      echo "  desktop <id>           Open GitHub Desktop for worktree"
      echo "  list                   List all worktrees"
      echo "  help                   Show this help"
      echo ""
      echo "Examples:"
      echo "  gtr create                    # Auto-creates mono-2 with new branch"
      echo "  gtr create tommy-mcp          # Auto-creates mono-2 with branch tommy-mcp"
      echo "  gtr create 3 ui-fixes         # Creates mono-3 with branch ui-fixes"
      echo "  gtr claude 2                  # Start Claude in mono-2"
      echo "  gtr cursor 2                  # Open Cursor in mono-2"
      echo "  gtr desktop 2                 # Open GitHub Desktop for mono-2"
      echo "  cd ~/Documents/GitHub/mono-worktrees/mono-2"
      echo ""
      echo "Navigation shortcuts:"
      echo "  cdw              # Jump to worktrees directory"
      echo "  cdm              # Jump to main repo"
      ;;

    *)
      echo "❌ Unknown command: $cmd"
      echo "Use 'gtr help' for available commands"
      return 1
      ;;
  esac
}

# Auto-completion for gtr
if [ -n "$BASH_VERSION" ]; then
  _gtr_completion() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local cmd="${COMP_WORDS[1]}"
    
    case "$cmd" in
      cd|claude|cursor|desktop|github|rm|remove)
        local repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
        if [ -n "$repo_root" ]; then
          local repo_name=$(basename "$repo_root")
          local base="$(dirname "$repo_root")/${repo_name}-worktrees"
          if [ -d "$base" ]; then
            local worktrees=$(ls "$base" 2>/dev/null)
            COMPREPLY=($(compgen -W "$worktrees" -- "$cur"))
          fi
        fi
        ;;
      *)
        COMPREPLY=($(compgen -W "create rm cd claude cursor desktop list help" -- "$cur"))
        ;;
    esac
  }
  
  complete -F _gtr_completion gtr
fi

# Zsh completion
if [ -n "$ZSH_VERSION" ]; then
  _gtr() {
    local -a commands
    commands=(
      'create:Create worktree from main branch'
      'rm:Remove worktree and branch'
      'cd:Change to worktree directory'
      'claude:Start Claude Code in worktree'
      'cursor:Open Cursor editor in worktree'
      'desktop:Open GitHub Desktop for worktree'
      'list:List all worktrees'
      'help:Show help'
    )
    
    local -a worktree_names
    local repo_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [ -n "$repo_root" ]; then
      local repo_name=$(basename "$repo_root")
      local base="$(dirname "$repo_root")/${repo_name}-worktrees"
      if [ -d "$base" ]; then
        worktree_names=(${(f)"$(ls "$base" 2>/dev/null)"})
      fi
    fi
    
    if (( CURRENT == 2 )); then
      _describe 'commands' commands
    elif (( CURRENT == 3 )); then
      case "$words[2]" in
        cd|claude|cursor|desktop|github|rm|remove)
          _describe 'worktrees' worktree_names
          ;;
      esac
    fi
  }
  
  compdef _gtr gtr
fi