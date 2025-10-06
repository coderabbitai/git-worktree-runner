#!/bin/sh
# Example setup script for gtr configuration
# Customize this for your project

set -e

echo "🔧 Configuring gtr for this repository..."

# Worktree settings
git config --local gtr.worktrees.prefix ""
git config --local gtr.defaultBranch "auto"

# Editor (change to your preference: cursor, vscode, zed)
# git config --local gtr.editor.default cursor

# File copying (add patterns for your project)
# git config --local --add gtr.copy.include "**/.env.example"
# git config --local --add gtr.copy.include "**/CLAUDE.md"

# Hooks (customize for your build system)
# git config --local --add gtr.hook.postCreate "npm install"
# git config --local --add gtr.hook.postCreate "npm run build"

# Or for pnpm projects:
# git config --local --add gtr.hook.postCreate "pnpm install"
# git config --local --add gtr.hook.postCreate "pnpm run build"

# Or for other tools:
# git config --local --add gtr.hook.postCreate "bundle install"
# git config --local --add gtr.hook.postCreate "cargo build"

echo "✅ gtr configured!"
echo ""
echo "View config with: git config --local --list | grep gtr"
echo "Create a worktree with: gtr new my-feature"
