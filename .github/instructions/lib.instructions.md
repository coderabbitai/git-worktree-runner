---
applyTo: lib/**/*.sh
---

# Lib Instructions

## Modifying Core (`lib/*.sh`)

- **Maintain backwards compatibility** with existing configs
- **Quote all paths**: Support spaces in directory names
- **Use `log_error` / `log_info`** from `lib/ui.sh` for user messages
- **Git version fallbacks**: See `get_current_branch()` in `lib/core.sh` (Git 2.22+ `branch --show-current`, falling back to `rev-parse --abbrev-ref HEAD`)
- **Regenerate completions** after touching `_EDITOR_REGISTRY`, `_AI_REGISTRY`, or `_CFG_KEY_MAP`: `./scripts/generate-completions.sh` (CI runs `--check`)

## Key Functions & Responsibilities

- `resolve_base_dir`: config/env/default selection; warn if inside repo & not ignored.
- `resolve_target`: ID `1` + branch/current + sanitized path scan; returns TSV.
- `create_worktree`: decides remote/local/new; respects `--force` + `--name` safety.
- `cfg_default`: precedence local git config → `.gtrconfig` → global/system git config → `GTR_*` env var → fallback (do not reorder). `cfg_default_trusted_file` uses the same order but ignores `.gtrconfig` values until `git gtr trust` approves them.
- `sanitize_branch_name`: branch name → folder name; the only place that logic lives.
- `run_hooks_in` (`lib/hooks.sh`): runs postCreate/preRemove/postRemove/postCd hooks, trust-gated for `.gtrconfig`.
- `cfg_get_all`: merge multi-value keys; preserves order; deduplicates.

## Change Guidelines

- Preserve adapter contracts; do not rename exported functions used by command handlers in `lib/commands/`.
- Add new config keys with `gtr.<name>` prefix; avoid collisions.
- For performance-sensitive loops (e.g. directory scans) prefer built-ins (`find`, `grep`) with minimal subshells.
- Any new Git command: add fallback for older versions or guard with detection.
- Run `bats tests/` and ShellCheck, then smoke-test the affected subset: `new`, `editor`, `ai`, `rm`, `list --porcelain`, `config set/get/unset`, `go 1`, hooks run once.
