---
applyTo: completions/*, scripts/generate-completions.sh
---

# Completions Instructions

## Generated Files

`completions/gtr.bash` (Bash), `completions/_git-gtr` (Zsh), and `completions/git-gtr.fish` (Fish) are **generated** by `scripts/generate-completions.sh`. Each file starts with an `AUTO-GENERATED ... DO NOT EDIT MANUALLY` header. CI (`.github/workflows/lint.yml`) runs `./scripts/generate-completions.sh --check` and fails when any committed file differs from the generator output.

Sources of truth:

- Adapter names: `_EDITOR_REGISTRY` and `_AI_REGISTRY` in `lib/adapters.sh`, plus any `adapters/{editor,ai}/*.sh` file overrides.
- Config keys: `_CFG_KEY_MAP` in `lib/config.sh`.
- Commands, their flags, and which commands accept branch arguments: the `generate_bash`, `generate_zsh`, and `generate_fish` templates inside the script.

`git gtr completion <shell>` (`lib/commands/completion.sh`) resolves the asset from the source checkout or the Homebrew install layout. For bash and fish it prints the generated file; for zsh it prints a `zstyle` + `fpath` + `compinit` snippet that puts the generated `_git-gtr` on your fpath. It never builds completions at runtime.

## Making Changes

| Change                   | Edit                                                                  | Then                                |
| ------------------------ | --------------------------------------------------------------------- | ----------------------------------- |
| New editor or AI adapter | registry line in `lib/adapters.sh`                                    | `./scripts/generate-completions.sh` |
| New config key           | `_CFG_KEY_MAP` in `lib/config.sh`                                     | `./scripts/generate-completions.sh` |
| New command or flag      | all three `generate_*` templates in `scripts/generate-completions.sh` | `./scripts/generate-completions.sh` |

Commit the regenerated files together with the source change. Keep the three templates in sync: same commands, same flags per command, and the same branch-completion behavior (git branches plus special ID `1` for commands that take a worktree target).

## Testing

`./scripts/generate-completions.sh --check` verifies the committed files. Interactive behavior is checked by hand, and all three shells require git's own completion to be enabled:

```bash
# Bash
source completions/gtr.bash
git gtr <TAB>                  # commands
git gtr new <TAB>              # flags
git gtr go <TAB>               # branches + '1'
git gtr editor --editor <TAB>  # editor names

# Zsh (add before compinit in ~/.zshrc)
eval "$(git gtr completion zsh)"

# Fish
git gtr completion fish > ~/.config/fish/completions/git-gtr.fish
```

## Shell Notes

- Bash: defines `_git_gtr`, which git's bash-completion (v2+) discovers for `git gtr`, and fills `COMPREPLY` with `compgen`.
- Zsh: `#compdef _git-gtr git-gtr gtr`, built on `_arguments`.
- Fish: `complete -c git` with `__fish_git_gtr_needs_command` and `__fish_git_gtr_using_command` predicates.

## Pitfalls

- Editing `completions/*` directly: CI rejects it and the next regeneration discards it.
- Updating one shell template but not the other two.
- Skipping `./scripts/generate-completions.sh --check` before pushing.
