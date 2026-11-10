# VULN-565 follow-up validation

Retested on November 10, 2026 against main `fc8afc0`, original remediation
`07b4205` (#208), and published tags v2.11.1 and v3.0.0 (`2d4852d`). Fixtures
operate entirely in disposable repositories and sibling worktrees. Targets are
ordinary sentinel files; no real shell startup files are touched.

## External writes

`tests/copy_followup.bats` commits an unapproved `.gtrconfig` containing
`worktrees.dir` and a copy include, plus a relative symlink. The repository's
basename and sibling worktree layout make that link resolve to an external
fixture from the new worktree. The source checkout replaces the committed link
with a regular file or directory containing replacement bytes. `git gtr new`
then materializes the committed link in the destination and copies the source.
No approval marker or hook is involved.

Four cases cover destination-file and destination-parent symlinks, each with an
existing target and an absent target. Against v2.11.1 and #208, all four safety
assertions fail: existing sentinels are overwritten and absent files are created.
Against v3.0.0 and current main, all four pass: symlinks remain, existing
sentinels retain their bytes, and absent targets remain absent. The existing-file
assertion also reads through the worktree's relative link to verify that its
referent really is the intended external sentinel.

This confirms that #208 fixed exclusion-driven deletion but did not initially
fix external writes through `_copy_pattern_file`. The later
[PR #210](https://github.com/coderabbitai/git-worktree-runner/pull/210) checks
source/destination components and stages leaf replacements without writing the
old inode. It already blocks these reported write paths and is included in
v3.0.0. No additional production fix is justified by these reproductions.

Existing copy-safety tests additionally cover source links, destination leaf
and ancestor links, hard-linked external files, expanded traversal, exclusions,
Git metadata, and directory merges. [PR #220](https://github.com/coderabbitai/git-worktree-runner/pull/220)
later hardened a distinct publication race and failure propagation. Bash path
checks do not promise isolation from arbitrary concurrent replacement of
ancestor directories by another writer; that documented limitation remains.

## Versions, impact, and duplicate scope

| Case | v2.11.1 | #208 | v3.0.0 | Current main |
| --- | --- | --- | --- | --- |
| Relative destination-file link, overwrite/create | Writes escape | Writes escape | Blocked | Blocked |
| Relative parent link plus naming/worktrees.dir, overwrite/create | Writes escape | Writes escape | Blocked | Blocked |

These are directly tested versions/commits, not an assertion that every earlier
tag is affected. Copying through existing links predates #208; the precise
earliest affected release was not established by this retest.

Demonstrated impact is overwrite or creation of files writable by the invoking
user outside the destination worktree, without hook trust. Shell-startup RCE
would additionally require a suitably located writable startup file, suitable
payload bytes, and subsequent shell behavior. Those conditions were not tested
and RCE is not claimed as an unconditional result.

H1 #4143483, #4151745, and #4139261 are candidate duplicates when their payloads
reach the same copy-through-link write primitive. File-leaf and parent-link
variants and the repository-naming/worktrees.dir chain share this sink and the
#210 remediation. The deletion primitive fixed by #208 is distinct; external
writes represent incomplete original remediation, not evidence that the
deletion fix failed. Individual report bodies and chronology were not supplied
or accessed, so attribution of each ID, final duplicate adjudication, and
payment scope remain pending report-specific comparison. This retest does not
infer a one-to-one mapping from report numbers alone.

## Release and retest evidence

[v3.0.0](https://github.com/coderabbitai/git-worktree-runner/releases/tag/v3.0.0)
was published October 28, 2026 at 22:58:54 UTC. Its release notes include #208
and #210; the tagged source passes the four new fixtures. At retest time it was
the latest published GitHub release. These are source-archive retests, not an
attestation of every package-manager binary or researcher acceptance.

Run `bats tests/copy_followup.bats tests/copy_safety.bats tests/cmd_copy.bats tests/cmd_create_integration.bats`
for the maintained regressions. To compare history, extract the requested tag
or commit with `git archive`, copy `tests/copy_followup.bats` into its tests
directory, and run it with isolated Git configuration and signing disabled.
The four failures on pre-#210 source are expected counterexamples. Current and
release retests used macOS, Bash 5.3, and private disposable paths; Linux CI is
provided by this PR.

The controlled retest and regression coverage are ready for review. Final
report-specific duplicate decisions and researcher retest evidence remain
closure blockers. No deadline or external-response ETA is assumed. No Linear,
Slack, or HackerOne updates were posted, and no release or merge was performed.
