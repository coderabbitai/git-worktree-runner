---
applyTo: adapters/editor/**/*.sh
---

# Editor Instructions

## Adding Features

### New Editor Adapter (`adapters/editor/<name>.sh`)

```bash
#!/usr/bin/env bash
# EditorName adapter

editor_can_open() {
  command -v editor-cli >/dev/null 2>&1
}

editor_open() {
  local path="$1"
  if ! editor_can_open; then
    log_error "EditorName not found. Install from https://..."
    return 1
  fi
  editor-cli "$path"
}
```

**Also update**:

- README.md (setup instructions)
- All three completion files: `completions/gtr.bash`, `completions/_gtr`, `completions/gtr.fish`
- Help text in `bin/gtr` (`cmd_help` function)

## Contract & Guidelines

- Required functions: `editor_can_open` (probe via `command -v`), `editor_open <path>`.
- Quote all paths; support spaces. Avoid changing PWD globally—no subshell needed (editor opens path).
- Use `log_error` with actionable install guidance if command missing.
- Keep adapter lean: no project scans, no blocking prompts.
- Naming: file name = tool name (`zed.sh` → `zed` flag). Avoid uppercase.
- Update: README editor list, completions (bash/zsh/fish), help (`Available editors:`), optional screenshots.
- Manual test: `bash -c 'source adapters/editor/<tool>.sh && editor_can_open && editor_open . || echo fail'`.
- Fallback behavior: if editor absent, fail clearly; do NOT silently defer to file browser.
- Inspect function definition if needed: `declare -f editor_open`.
