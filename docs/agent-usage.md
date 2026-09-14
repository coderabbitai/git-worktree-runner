# AI Agent Usage

Shell-capable coding agents can call `git gtr` directly. A separate MCP server
is not necessary for creating, locating, using, and removing worktrees.

## Machine-readable creation

Create a worktree with stable output:

```bash
git gtr new agent/my-task --porcelain
```

The command writes exactly three tab-separated records to stdout:

```text
path	/absolute/path/to/repo-worktrees/agent-my-task
branch	agent/my-task
hook_status	ran
```

Values escape backslashes, tabs, and newlines as `\\`, `\t`, and `\n`.
Progress messages, warnings, and hook output go to stderr. `--porcelain` implies
`--yes` and cannot be combined with `--editor` or `--ai`.

`hook_status` is one of:

| Value | Meaning |
| --- | --- |
| `disabled` | Hooks were disabled with `--no-hooks`. |
| `none` | No post-create hooks were configured. |
| `ran` | All configured post-create hooks were trusted and ran successfully. |
| `skipped-untrusted` | Only untrusted `.gtrconfig` hooks were configured, so none ran. |
| `partial` | Trusted hooks ran, while untrusted `.gtrconfig` hooks were skipped. |

A non-zero exit means creation or a post-create hook failed. No success records
are emitted in that case.

## Restricting side effects

`--porcelain` only changes output and prompting. Repository setup still runs:
configured file copying (`gtr.copy.*`), trusted post-create hooks, and a
`git fetch` before creation. Automation that wants a bare worktree can disable
each of these explicitly:

```bash
# Option 1: no hooks, no file copying
git gtr new agent/bare-task --porcelain --no-hooks --no-copy

# Option 2: additionally skip the network round-trip
git gtr new agent/offline-task --porcelain --no-hooks --no-copy --no-fetch
```

With `--no-hooks`, `hook_status` is always `disabled`. The trust model still
applies without it: `.gtrconfig` hooks the user has not approved never run.

## Recommended agent lifecycle

1. Inspect existing worktrees with `git gtr list --porcelain`.
2. Create an isolated worktree with `git gtr new <branch> --porcelain`.
3. Parse the `path` record and perform all task work inside that directory.
4. Before handing off, run `git status --short --branch` in the worktree and
   report its branch, changes, and validation results.
5. Remove the worktree only when the user explicitly asks for cleanup.

Agents should not run `git gtr trust`. Trusting committed `.gtrconfig` commands
authorizes code execution and requires human review. Agents should also avoid
`git gtr rm --force`, `--delete-branch`, and `git gtr clean` unless the user has
explicitly authorized the destructive scope.

## `AGENTS.md` example

```markdown
## Worktree policy

- Use `git gtr list --porcelain` to inspect worktrees.
- For implementation tasks, create an isolated worktree with
  `git gtr new <branch> --porcelain` and work only in the returned `path`.
- Treat a non-zero exit as failure; do not infer success from human-readable logs.
- If `hook_status` is `skipped-untrusted` or `partial`, report it. Never run
  `git gtr trust` on the user's behalf.
- Do not remove worktrees, force cleanup, or delete branches without explicit
  user authorization.
```
