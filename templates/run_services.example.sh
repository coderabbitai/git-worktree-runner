#!/bin/sh
# Example service runner script for development
# This demonstrates a generic pattern for running multiple services in a worktree

set -e

# Get the repository root
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

echo "🚀 Starting development services..."
echo "📂 Repository: $REPO_ROOT"
echo ""

# Example: Run a database
# Uncomment and customize for your needs
# echo "Starting database..."
# docker-compose up -d postgres
# Or: pg_ctl -D /usr/local/var/postgres start

# Example: Run API server in background
# echo "Starting API server..."
# cd "$REPO_ROOT/apps/api" && npm run dev &

# Example: Run frontend dev server
# echo "Starting frontend..."
# cd "$REPO_ROOT/apps/web" && npm run dev &

# Example: Run multiple services with a process manager
# if command -v overmind >/dev/null 2>&1; then
#   echo "Starting services with Overmind..."
#   cd "$REPO_ROOT" && overmind start
# elif command -v foreman >/dev/null 2>&1; then
#   echo "Starting services with Foreman..."
#   cd "$REPO_ROOT" && foreman start
# else
#   echo "No process manager found. Install overmind or foreman."
# fi

# Example: Run services in new terminal tabs (macOS with iTerm2)
# if command -v osascript >/dev/null 2>&1; then
#   osascript <<-EOF
#     tell application "iTerm"
#       tell current window
#         create tab with default profile
#         tell current session
#           write text "cd '$REPO_ROOT/apps/api' && npm run dev"
#         end tell
#       end tell
#     end tell
# EOF
# fi

# Example: Run with tmux sessions
# if command -v tmux >/dev/null 2>&1; then
#   tmux new-session -d -s dev "cd $REPO_ROOT/apps/api && npm run dev"
#   tmux split-window -h "cd $REPO_ROOT/apps/web && npm run dev"
#   tmux attach-session -t dev
# fi

echo "✅ Services started!"
echo ""
echo "💡 Customize this script for your project's needs:"
echo "   - Docker containers"
echo "   - Development servers"
echo "   - Background workers"
echo "   - Database migrations"
echo ""
echo "To stop services, use Ctrl+C or your process manager's stop command."

# Keep script running if services are in background
# wait
