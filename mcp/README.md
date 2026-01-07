# MCP Server for git-worktree-runner

This directory contains an MCP (Model Context Protocol) server that exposes git-worktree-runner commands as tools for AI agents.

## What is MCP?

[Model Context Protocol](https://modelcontextprotocol.io/) is an open standard by Anthropic for connecting AI applications to external tools and data sources. This server allows AI assistants like Claude, ChatGPT, and Cursor to manage git worktrees autonomously.

## Requirements

- **jq**: JSON processor for parsing MCP messages

  ```bash
  # macOS
  brew install jq

  # Ubuntu/Debian
  sudo apt install jq

  # Windows (with chocolatey)
  choco install jq
  ```

- **git-worktree-runner**: The `gtr` script must be available (this server uses `../bin/gtr`)

## Setup

### Claude Desktop

Edit `~/Library/Application Support/Claude/claude_desktop_config.json` (macOS) or `%APPDATA%\Claude\claude_desktop_config.json` (Windows):

```json
{
  "mcpServers": {
    "gtr": {
      "command": "bash",
      "args": ["/absolute/path/to/git-worktree-runner/mcp/gtr-server.sh"],
      "cwd": "/path/to/your/repository"
    }
  }
}
```

### Cursor

Create `.cursor/mcp.json` in your project:

```json
{
  "mcpServers": {
    "gtr": {
      "command": "bash",
      "args": ["./path/to/git-worktree-runner/mcp/gtr-server.sh"]
    }
  }
}
```

### Claude Code

Add to your Claude Code MCP configuration:

```json
{
  "mcpServers": {
    "gtr": {
      "command": "bash",
      "args": ["/path/to/git-worktree-runner/mcp/gtr-server.sh"]
    }
  }
}
```

## Available Tools

| Tool         | Description                                               |
| ------------ | --------------------------------------------------------- |
| `gtr_list`   | List all worktrees with their paths, branches, and status |
| `gtr_new`    | Create a new worktree (and branch if needed)              |
| `gtr_go`     | Get the absolute path to a worktree                       |
| `gtr_run`    | Execute a command in a worktree's context                 |
| `gtr_rm`     | Remove a worktree (requires explicit confirmation)        |
| `gtr_doctor` | Run health checks on the installation                     |
| `gtr_copy`   | Copy files to worktrees using glob patterns               |

## Example Usage

Once configured, you can ask your AI assistant:

> "Create a new worktree for feature-login, run the tests, and show me the results"

The AI will:

1. Call `gtr_new` with `{"branch": "feature-login"}`
2. Call `gtr_run` with `{"identifier": "feature-login", "command": "npm test"}`
3. Report the test results

> "List all my worktrees and clean up any that are for merged branches"

The AI will:

1. Call `gtr_list` to see all worktrees
2. Analyze which ones might be stale
3. Call `gtr_rm` (with `yes: true`) to remove them

## Safety Features

The MCP server includes safety measures for destructive operations:

- **`gtr_rm` requires explicit confirmation**: The `yes` parameter must be `true`
- **Read-only tools are always safe**: `gtr_list`, `gtr_go`, `gtr_doctor`
- **No global config exposure**: The server doesn't expose `config set` for global scope
- **No hook configuration**: Custom hooks aren't exposed to prevent arbitrary code execution

## Testing

### Manual Testing

```bash
# Test that the server starts and responds to tools/list
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | bash mcp/gtr-server.sh

# Test gtr_list
echo '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"gtr_list","arguments":{}}}' | bash mcp/gtr-server.sh

# Test gtr_new
echo '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"gtr_new","arguments":{"branch":"test-mcp"}}}' | bash mcp/gtr-server.sh

# Test gtr_go
echo '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"gtr_go","arguments":{"identifier":"test-mcp"}}}' | bash mcp/gtr-server.sh

# Test gtr_rm (cleanup)
echo '{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"gtr_rm","arguments":{"identifier":"test-mcp","yes":true}}}' | bash mcp/gtr-server.sh
```

### MCP Inspector

Use the official MCP inspector for interactive testing:

```bash
npx @modelcontextprotocol/inspector bash mcp/gtr-server.sh
```

## Protocol Details

- **Transport**: stdio (JSON-RPC 2.0)
- **Protocol Version**: 2024-11-05
- **Capabilities**: tools

## Troubleshooting

### "jq is required but not installed"

Install jq using your package manager (see Requirements above).

### "gtr script not found"

Ensure the server is run from within the git-worktree-runner directory, or that the relative path `../bin/gtr` resolves correctly.

### No response from server

Check that the server is receiving valid JSON. Each message must be on a single line:

```bash
# Good - single line
echo '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | bash mcp/gtr-server.sh

# Bad - formatted JSON
echo '{
  "jsonrpc": "2.0",
  "id": 1,
  "method": "tools/list"
}' | bash mcp/gtr-server.sh
```

### Permission denied

Make the server executable:

```bash
chmod +x mcp/gtr-server.sh
```

## Related Resources

- [MCP Specification](https://spec.modelcontextprotocol.io/)
- [MCP TypeScript SDK](https://github.com/modelcontextprotocol/typescript-sdk)
- [git-worktree-runner Documentation](../README.md)
