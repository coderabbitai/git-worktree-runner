---
applyTo: adapters/ai/**/*.sh
---

# AI Adapter Instructions

## When to Use a File vs Registry

Most AI tools are defined as **registry entries** in `lib/adapters.sh` — no adapter file needed.
Only create an adapter file in `adapters/ai/` for tools that need **custom behavior** beyond the standard builder (see `claude.sh` or `cursor.sh` for examples).

## Adding a Standard AI Tool (Registry)

Add a line to `_AI_REGISTRY` in `lib/adapters.sh`:

```
yourname|yourcmd|ToolName not found. Install with: ...|Extra info;More info
```

Format: `name|cmd|err_msg|info_lines` (info lines are semicolon-separated)

## Adding a Custom AI Tool (File Override)

Create `adapters/ai/<name>.sh` implementing:

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

File-based adapters take precedence over registry entries of the same name.

**Also update**: README, completions (bash/zsh/fish), help text in `lib/commands/help.sh`

## Contract & Guidelines

- Must define: `ai_can_start` (0 = available), `ai_start <path> [args...]` (runs in subshell `(cd ...)`).
- Always quote: `"$path"` and arguments; never assume current working directory.
- Use `log_error` + helpful install hint; never silent fail.
- Keep side effects confined to worktree directory; do not modify repo root unintentionally.
- Accept extra args after `--`: preserve ordering (`ai_start` receives already-shifted args).
- Prefer fast startup; heavy initialization belongs in hooks (`postCreate`), not adapters.
- When adding adapter: update `cmd_help`, README tool list, and completions (bash/zsh/fish).
- Inspect function definition if needed: `declare -f ai_start`.
