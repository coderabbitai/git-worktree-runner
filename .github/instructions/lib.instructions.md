---
applyTo: lib/**/*.sh
---

# Lib Instructions

## Modifying Core (`lib/*.sh`)

- **Maintain backwards compatibility** with existing configs
- **Quote all paths**: Support spaces in directory names
- **Use `log_error` / `log_info`** from `lib/ui.sh` for user messages
- **Git version fallbacks**: Check `lib/core.sh:97-100` for example (Git 2.22+ `--show-current` vs older `rev-parse`)

## Key Functions & Responsibilities

- `resolve_base_dir`: config/env/default selection; warn if inside repo & not ignored.
- `resolve_target`: ID `1` + branch/current + sanitized path scan; returns TSV.
- `create_worktree`: decides remote/local/new; respects `--force` + `--name` safety.
- `cfg_default`: precedence local→global→system→env→fallback (do not reorder).
- `cfg_get_all`: merge multi-value keys; preserves order; deduplicates.

## Change Guidelines

- Preserve adapter contracts; do not rename exported functions used by command handlers in `lib/commands/`.
- Add new config keys with `gtr.<name>` prefix; avoid collisions.
- For performance-sensitive loops (e.g. directory scans) prefer built-ins (`find`, `grep`) with minimal subshells.
- Any new Git command: add fallback for older versions or guard with detection.
- Manual test after changes (subset): `new`, `open`, `ai`, `rm`, `list --porcelain`, `config set/get/unset`, `go 1`, hooks run once.
