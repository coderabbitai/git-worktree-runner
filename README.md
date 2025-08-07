# gtr — Git worktree runner for parallel Claude Code dev

gtr creates and manages per-branch git worktrees (mono-2, mono-3, …) and automates setup:
- Detects/creates branches (remote/local/new from `main`)
- Opens GitHub Desktop to the new worktree (macOS)
- Copies `.env.local` and `CLAUDE.md` files (preserving paths) and `run_services.sh`
- Installs deps with pnpm and runs `turbo build`
- Shortcuts: cd, remove, launch Claude or Cursor, list worktrees

Related guide: https://docs.anthropic.com/en/docs/claude-code/common-workflows#run-parallel-claude-code-sessions-with-git-worktrees

## Install (zsh on macOS)
```bash
curl -fsSL https://raw.githubusercontent.com/<org>/git-worktree-runner/main/gtr.sh -o ~/.gtr.sh
chmod +x ~/.gtr.sh
echo 'source ~/.gtr.sh' >> ~/.zshrc
exec zsh
```

## Usage
```bash
# Create next available worktree from a branch
gtr create my-feature
# Or specify ID and branch
gtr create 3 ui-fixes

# Jump into a worktree
gtr cd 2

# Start tools
gtr claude 2
gtr cursor 2
gtr desktop 2

# List / remove
gtr list
gtr rm 2
```

## Requirements
- macOS (uses GitHub Desktop via `open -a`)
- git, pnpm, turbo
- Optional: `claude-code`, `cursor` on PATH

## Notes
- Default base branch is `main` (adjust inside `gtr.sh` if needed).
- Script prompts during create/remove (interactive).
- For non‑macOS, replace the GitHub Desktop `open -a` line.

## Uninstall
```bash
sed -i.bak '/source .*\\.gtr\\.sh/d' ~/.zshrc
rm -f ~/.gtr.sh
exec zsh
```
```
