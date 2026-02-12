---
applyTo: adapters/editor/**/*.sh
---

# Editor Adapter Instructions

## When to Use a File vs Registry

Most editors are defined as **registry entries** in `lib/adapters.sh` — no adapter file needed.
Only create an adapter file in `adapters/editor/` for editors that need **custom behavior** beyond what the standard/terminal builders provide (see `nano.sh` for an example).

## Adding a Standard Editor (Registry)

Add a line to `_EDITOR_REGISTRY` in `lib/adapters.sh`:

```
yourname|yourcmd|standard|EditorName not found. Install from https://...|flags
```

Format: `name|cmd|type|err_msg|flags`
- `type`: `standard` (GUI app) or `terminal` (runs in terminal)
- `flags`: comma-separated — `workspace` (supports .code-workspace), `background` (terminal bg)

## Adding a Custom Editor (File Override)

Create `adapters/editor/<name>.sh` implementing:

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

File-based adapters take precedence over registry entries of the same name.

**Also update**:

- README.md (setup instructions)
- All three completion files: `completions/gtr.bash`, `completions/_git-gtr`, `completions/gtr.fish`
- Help text in `lib/commands/help.sh` (`cmd_help` function)

## Contract & Guidelines

- Required functions: `editor_can_open` (probe via `command -v`), `editor_open <path>`.
- Quote all paths; support spaces. Avoid changing PWD globally—no subshell needed (editor opens path).
- Use `log_error` with actionable install guidance if command missing.
- Keep adapter lean: no project scans, no blocking prompts.
- Naming: file/registry name = tool name (`zed` → `zed` flag). Avoid uppercase.
- Update: README editor list, completions (bash/zsh/fish), help (`Available editors:`), optional screenshots.
- Fallback behavior: if editor absent, fail clearly; do NOT silently defer to file browser.
- Inspect function definition if needed: `declare -f editor_open`.
