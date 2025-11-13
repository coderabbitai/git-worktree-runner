---
applyTo: adapters/ai/**/*.sh
---

# AI Instructions

## Adding Features

### New AI Tool Adapter (`adapters/ai/<name>.sh`)

```bash
#!/usr/bin/env bash
# ToolName adapter

ai_can_start() {
  command -v tool-cli >/dev/null 2>&1
}

ai_start() {
  local path="$1"
  shift
  if ! ai_can_start; then
    log_error "ToolName not found. Install with: ..."
    return 1
  fi
  (cd "$path" && tool-cli "$@")  # Note: subshell for directory change
}
```

**Also update**: Same as editor adapters (README, completions, help text)

## Contract & Guidelines

- Must define: `ai_can_start` (0 = available), `ai_start <path> [args...]` (runs in subshell `(cd ...)`).
- Always quote: `"$path"` and arguments; never assume current working directory.
- Use `log_error` + helpful install hint; never silent fail.
- Keep side effects confined to worktree directory; do not modify repo root unintentionally.
- Accept extra args after `--`: preserve ordering (`ai_start` receives already-shifted args).
- Prefer fast startup; heavy initialization belongs in hooks (`postCreate`), not adapters.
- When adding adapter: update `cmd_help`, README tool list, and completions (bash/zsh/fish).
- Test manually: `bash -c 'source adapters/ai/<tool>.sh && ai_can_start && echo OK'`.
- Inspect function definition if needed: `declare -f ai_start`.
