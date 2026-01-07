#!/usr/bin/env bash
# mcp/gtr-server.sh - MCP server for git-worktree-runner
#
# This server exposes git-worktree-runner commands as MCP tools,
# enabling AI agents to manage worktrees autonomously.
#
# Requirements: jq (for JSON parsing)
# Usage: Configure in your MCP client (Claude Desktop, Cursor, etc.)
#
# Protocol: JSON-RPC 2.0 over stdio (MCP specification 2024-11-05)

set -euo pipefail

# Find the gtr script relative to this server
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GTR_BIN="${SCRIPT_DIR}/../bin/gtr"

# Verify dependencies (errors go to stdout for MCP protocol compliance)
if ! command -v jq >/dev/null 2>&1; then
  echo '{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"jq is required but not installed"}}'
  exit 1
fi

if [[ ! -x "$GTR_BIN" ]]; then
  echo '{"jsonrpc":"2.0","id":null,"error":{"code":-32603,"message":"gtr script not found at '"$GTR_BIN"'"}}'
  exit 1
fi

# ─────────────────────────────────────────────────────────────────────────────
# JSON-RPC Response Helpers
# ─────────────────────────────────────────────────────────────────────────────

send_response() {
  local id="$1" result="$2"
  # Compact the result to ensure single-line output (MCP requires one JSON per line)
  local compact_result
  compact_result=$(printf '%s' "$result" | jq -c .)
  printf '{"jsonrpc":"2.0","id":%s,"result":%s}\n' "$id" "$compact_result"
}

send_error() {
  local id="$1" code="$2" message="$3"
  # Escape message for JSON
  local escaped_msg
  escaped_msg=$(printf '%s' "$message" | jq -Rs .)
  printf '{"jsonrpc":"2.0","id":%s,"error":{"code":%d,"message":%s}}\n' "$id" "$code" "$escaped_msg"
}

send_tool_result() {
  local id="$1" content="$2" is_error="${3:-false}"
  local escaped
  escaped=$(printf '%s' "$content" | jq -Rs .)
  printf '{"jsonrpc":"2.0","id":%s,"result":{"content":[{"type":"text","text":%s}],"isError":%s}}\n' \
    "$id" "$escaped" "$is_error"
}

# ─────────────────────────────────────────────────────────────────────────────
# Tool Implementations
# ─────────────────────────────────────────────────────────────────────────────

tool_gtr_list() {
  local output
  output=$("$GTR_BIN" list --porcelain 2>&1) || true

  # Convert porcelain format (path\tbranch\tstatus) to JSON array using jq
  local json_array="[]"
  while IFS=$'\t' read -r path branch status; do
    [[ -z "$path" ]] && continue
    # Use jq to safely build JSON objects (handles special characters properly)
    json_array=$(echo "$json_array" | jq -c \
      --arg path "$path" \
      --arg branch "$branch" \
      --arg status "$status" \
      '. + [{path: $path, branch: $branch, status: $status}]')
  done <<< "$output"
  echo "$json_array"
}

tool_gtr_new() {
  local params="$1"
  local branch from fromCurrent force name noCopy

  branch=$(echo "$params" | jq -r '.branch // empty')
  from=$(echo "$params" | jq -r '.from // empty')
  fromCurrent=$(echo "$params" | jq -r '.fromCurrent // false')
  force=$(echo "$params" | jq -r '.force // false')
  name=$(echo "$params" | jq -r '.name // empty')
  noCopy=$(echo "$params" | jq -r '.noCopy // false')

  if [[ -z "$branch" ]]; then
    echo "Error: 'branch' parameter is required"
    return 1
  fi

  # Build command array (safer than string concatenation)
  local cmd=("$GTR_BIN" new "$branch")
  [[ -n "$from" ]] && cmd+=(--from "$from")
  [[ "$fromCurrent" == "true" ]] && cmd+=(--from-current)
  [[ "$force" == "true" ]] && cmd+=(--force)
  [[ -n "$name" ]] && cmd+=(--name "$name")
  [[ "$noCopy" == "true" ]] && cmd+=(--no-copy)

  "${cmd[@]}" 2>&1
}

tool_gtr_go() {
  local params="$1"
  local identifier

  identifier=$(echo "$params" | jq -r '.identifier // empty')

  if [[ -z "$identifier" ]]; then
    echo "Error: 'identifier' parameter is required"
    return 1
  fi

  "$GTR_BIN" go "$identifier" 2>&1
}

tool_gtr_run() {
  local params="$1"
  local identifier command

  identifier=$(echo "$params" | jq -r '.identifier // empty')
  command=$(echo "$params" | jq -r '.command // empty')

  if [[ -z "$identifier" ]]; then
    echo "Error: 'identifier' parameter is required"
    return 1
  fi

  if [[ -z "$command" ]]; then
    echo "Error: 'command' parameter is required"
    return 1
  fi

  # Pass command as separate words for shell expansion
  # shellcheck disable=SC2086
  "$GTR_BIN" run "$identifier" $command 2>&1
}

tool_gtr_rm() {
  local params="$1"
  local identifier yes deleteBranch force

  identifier=$(echo "$params" | jq -r '.identifier // empty')
  yes=$(echo "$params" | jq -r '.yes // false')
  deleteBranch=$(echo "$params" | jq -r '.deleteBranch // false')
  force=$(echo "$params" | jq -r '.force // false')

  if [[ -z "$identifier" ]]; then
    echo "Error: 'identifier' parameter is required"
    return 1
  fi

  # SAFETY: Require explicit confirmation
  if [[ "$yes" != "true" ]]; then
    echo "Error: 'yes' parameter must be true to confirm removal (safety measure)"
    return 1
  fi

  local cmd=("$GTR_BIN" rm "$identifier" --yes)
  [[ "$deleteBranch" == "true" ]] && cmd+=(--delete-branch)
  [[ "$force" == "true" ]] && cmd+=(--force)

  "${cmd[@]}" 2>&1
}

tool_gtr_doctor() {
  "$GTR_BIN" doctor 2>&1
}

tool_gtr_copy() {
  local params="$1"
  local target from dryRun all

  target=$(echo "$params" | jq -r '.target // empty')
  from=$(echo "$params" | jq -r '.from // empty')
  dryRun=$(echo "$params" | jq -r '.dryRun // false')
  all=$(echo "$params" | jq -r '.all // false')

  # Check patterns using jq length (more robust than string comparison)
  local patterns_count
  patterns_count=$(echo "$params" | jq '.patterns // [] | length')
  if [[ "$patterns_count" -eq 0 ]]; then
    echo "Error: 'patterns' parameter is required (array of glob patterns)"
    return 1
  fi

  # Build command
  local cmd=("$GTR_BIN" copy)

  if [[ "$all" == "true" ]]; then
    cmd+=(-a)
  elif [[ -n "$target" ]]; then
    cmd+=("$target")
  else
    echo "Error: Either 'target' or 'all: true' is required"
    return 1
  fi

  [[ -n "$from" ]] && cmd+=(--from "$from")
  [[ "$dryRun" == "true" ]] && cmd+=(--dry-run)

  # Add patterns after --
  cmd+=(--)

  # Parse patterns array and add each
  while IFS= read -r pattern; do
    [[ -n "$pattern" ]] && cmd+=("$pattern")
  done < <(echo "$params" | jq -r '.patterns // [] | .[]')

  "${cmd[@]}" 2>&1
}

# ─────────────────────────────────────────────────────────────────────────────
# MCP Protocol Definitions
# ─────────────────────────────────────────────────────────────────────────────

# Server capabilities (returned for initialize request)
# Note: read returns non-zero at EOF, so we use || true
read -r -d '' SERVER_INFO << 'SERVERINFO_EOF' || true
{
  "protocolVersion": "2024-11-05",
  "capabilities": {
    "tools": {}
  },
  "serverInfo": {
    "name": "gtr-mcp-server",
    "version": "1.0.0"
  }
}
SERVERINFO_EOF

# Tool definitions (returned for tools/list request)
read -r -d '' TOOLS_LIST << 'TOOLSLIST_EOF' || true
{
  "tools": [
    {
      "name": "gtr_list",
      "description": "List all git worktrees in the current repository. Returns an array of worktrees with their paths, branch names, and status (ok, detached, locked, prunable, missing).",
      "inputSchema": {
        "type": "object",
        "properties": {},
        "required": []
      }
    },
    {
      "name": "gtr_new",
      "description": "Create a new git worktree for isolated development. Creates a new branch if it does not exist. Returns the path to the created worktree.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "branch": {
            "type": "string",
            "description": "Branch name for the worktree (will be created if it does not exist)"
          },
          "from": {
            "type": "string",
            "description": "Base ref (branch, tag, or commit) to create branch from. Defaults to repository default branch."
          },
          "fromCurrent": {
            "type": "boolean",
            "description": "Create branch from current HEAD instead of default branch"
          },
          "force": {
            "type": "boolean",
            "description": "Allow creating worktree even if branch is already checked out elsewhere (requires name)"
          },
          "name": {
            "type": "string",
            "description": "Custom suffix for worktree folder name (used with force for multiple worktrees per branch)"
          },
          "noCopy": {
            "type": "boolean",
            "description": "Skip copying files defined in gtr.copy.include patterns"
          }
        },
        "required": ["branch"]
      }
    },
    {
      "name": "gtr_go",
      "description": "Get the absolute filesystem path to a worktree. Use this to locate a worktree before running commands in it. Special ID 1 always refers to the main repository.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "identifier": {
            "type": "string",
            "description": "Branch name or special ID. Use 1 for the main repository, or a branch name for a worktree."
          }
        },
        "required": ["identifier"]
      }
    },
    {
      "name": "gtr_run",
      "description": "Execute a shell command in the context of a specific worktree. The command runs with the worktree directory as the current working directory.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "identifier": {
            "type": "string",
            "description": "Branch name or worktree ID to run command in"
          },
          "command": {
            "type": "string",
            "description": "Shell command to execute (e.g., npm test, git status, make build)"
          }
        },
        "required": ["identifier", "command"]
      }
    },
    {
      "name": "gtr_rm",
      "description": "Remove a worktree and optionally its branch. DESTRUCTIVE: Requires explicit yes:true parameter for safety. Use gtr_list first to verify the worktree exists.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "identifier": {
            "type": "string",
            "description": "Branch name or worktree ID to remove"
          },
          "deleteBranch": {
            "type": "boolean",
            "description": "Also delete the git branch after removing worktree (cannot be undone easily)"
          },
          "force": {
            "type": "boolean",
            "description": "Force removal even if worktree has uncommitted changes"
          },
          "yes": {
            "type": "boolean",
            "description": "REQUIRED: Must be true to confirm removal. This is a safety measure."
          }
        },
        "required": ["identifier", "yes"]
      }
    },
    {
      "name": "gtr_doctor",
      "description": "Run health checks on the git-worktree-runner installation. Verifies git is available, checks repository status, and validates worktree configuration.",
      "inputSchema": {
        "type": "object",
        "properties": {},
        "required": []
      }
    },
    {
      "name": "gtr_copy",
      "description": "Copy files matching glob patterns from the main repository (or another worktree) to a target worktree. Useful for copying configuration files like .env.example.",
      "inputSchema": {
        "type": "object",
        "properties": {
          "target": {
            "type": "string",
            "description": "Target worktree identifier (branch name or ID). Required unless all is true."
          },
          "patterns": {
            "type": "array",
            "items": {"type": "string"},
            "description": "Glob patterns for files to copy (e.g., .env.example, *.config.js)"
          },
          "from": {
            "type": "string",
            "description": "Source worktree to copy from (defaults to main repository)"
          },
          "dryRun": {
            "type": "boolean",
            "description": "Preview what would be copied without making changes"
          },
          "all": {
            "type": "boolean",
            "description": "Copy to all worktrees instead of a specific target"
          }
        },
        "required": ["patterns"]
      }
    }
  ]
}
TOOLSLIST_EOF

# ─────────────────────────────────────────────────────────────────────────────
# Message Handler
# ─────────────────────────────────────────────────────────────────────────────

handle_message() {
  local msg="$1"
  local id method params

  # Parse JSON-RPC message
  # Use jq -c to preserve ID type (string vs number)
  local raw_id
  raw_id=$(echo "$msg" | jq -c '.id // null')
  id="$raw_id"  # Keep as JSON literal (quoted strings, raw numbers)
  method=$(echo "$msg" | jq -r '.method // empty')
  params=$(echo "$msg" | jq -c '.params // {}')

  case "$method" in
    "initialize")
      send_response "$id" "$SERVER_INFO"
      ;;

    "notifications/initialized")
      # Notification - no response needed
      ;;

    "tools/list")
      send_response "$id" "$TOOLS_LIST"
      ;;

    "tools/call")
      local tool_name tool_args output is_error
      tool_name=$(echo "$params" | jq -r '.name')
      tool_args=$(echo "$params" | jq -c '.arguments // {}')
      is_error="false"

      case "$tool_name" in
        "gtr_list")
          output=$(tool_gtr_list)
          ;;
        "gtr_new")
          output=$(tool_gtr_new "$tool_args") || is_error="true"
          ;;
        "gtr_go")
          output=$(tool_gtr_go "$tool_args") || is_error="true"
          ;;
        "gtr_run")
          output=$(tool_gtr_run "$tool_args") || is_error="true"
          ;;
        "gtr_rm")
          output=$(tool_gtr_rm "$tool_args") || is_error="true"
          ;;
        "gtr_doctor")
          output=$(tool_gtr_doctor)
          ;;
        "gtr_copy")
          output=$(tool_gtr_copy "$tool_args") || is_error="true"
          ;;
        *)
          send_error "$id" -32601 "Unknown tool: $tool_name"
          return
          ;;
      esac

      send_tool_result "$id" "$output" "$is_error"
      ;;

    "ping")
      send_response "$id" '{}'
      ;;

    *)
      # Unknown method
      if [[ "$id" != "null" ]]; then
        send_error "$id" -32601 "Method not found: $method"
      fi
      # Ignore unknown notifications (id is null)
      ;;
  esac
}

# ─────────────────────────────────────────────────────────────────────────────
# Main Loop
# ─────────────────────────────────────────────────────────────────────────────

main() {
  # Read JSON-RPC messages from stdin, one per line
  while IFS= read -r line; do
    # Skip empty lines
    [[ -z "$line" ]] && continue

    # Validate JSON before processing
    if ! echo "$line" | jq -e . >/dev/null 2>&1; then
      echo '{"jsonrpc":"2.0","id":null,"error":{"code":-32700,"message":"Parse error: Invalid JSON"}}'
      continue
    fi

    handle_message "$line"
  done
}

main "$@"
