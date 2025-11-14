---
applyTo: **/*.bash, **/*.fish, **/*.sh
---

# Shell Instructions

## Architecture

**Key Pattern**: Everything is sourced at startup (`set -e` enabled). Functions call each other directly. No subshells except for hooks and AI tools.

## Code Conventions

### Shell Script Style

- **Bash 3.2+ compatible** (macOS default), but 4.0+ features allowed where appropriate
- **Always quote variables**: `"$var"` not `$var`
- **Function-scoped vars**: Use `local var="value"`
- **Error handling**: Check return codes; functions return 1 on failure
- **Naming**: `snake_case` for functions/vars, `UPPER_CASE` for constants

### Strict Mode & Safety

- Global `set -e` in `bin/gtr`: guard non-critical commands with `|| true`.
- Prefer `[ ]` over `[[ ]]` for POSIX portability (use `[[` only when needed).
- Always quote glob inputs; disable unintended globbing (`set -f` temporarily if required).

### Portability

- Target Bash 3.2+: avoid associative arrays; use simple string/loop constructs.
- Avoid `readarray` and process substitution unsupported in older Bash.

### Debugging

- Quick trace: `bash -x ./bin/gtr <cmd>`.
- Inline: wrap suspicious block with `set -x` / `set +x`.
- Function presence: `declare -f create_worktree` or `declare -f resolve_target`.
- Variable inspection: `echo "DEBUG var=$var" >&2` (stderr keeps stdout clean for command substitution).

### External Commands

- Keep dependencies minimal: only `git`, `sed`, `awk`, `find`, `grep` (avoid jq/curl unless justified).
- Check availability before use if adding new tools.

### Quoting & Paths

- Use `"${var}"`; for loop over lines: `while IFS= read -r line; do ... done` to preserve spaces.
- Sanitize branch names via `sanitize_branch_name` (do NOT duplicate logic elsewhere).
