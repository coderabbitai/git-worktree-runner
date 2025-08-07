  #!/usr/bin/env bash
  set -euo pipefail
  BASE_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"

  require() { command -v "$1" >/dev/null || { echo "Missing: $1"; exit 1; }; }
  require ttab; require pnpm; require turbo

  run_in_new_terminal() { ttab -d "$BASE_DIR/$2" -t "$1" "$3"; }

  # pnpm install && turbo build # uncomment if desired
  run_in_new_terminal "DB API Server" "apps/db-api-server" "pnpm run dev"
  # add your services...
  if command -v ngrok >/dev/null && [ -f "$BASE_DIR/ngrok.yaml" ]; then
    run_in_new_terminal "ngrok - PR Reviewer" "." "ngrok start --all --config ngrok.yaml"
  fi
