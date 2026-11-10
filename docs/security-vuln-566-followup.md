# VULN-566 follow-up validation

Retested on November 10, 2026 against main `fc8afc0` and the published
`v3.0.0` tag (`2d4852d`). All execution fixtures write harmless marker files
inside disposable repositories. No real shell startup files are modified.

## Repository contents replaced in place

`tests/trust_followup.bats` approves an unchanged command invoking
`bootstrap.sh`, initializes an unrelated donor repository, deletes every child
of the approved `.git` directory, and copies the donor's Git contents into it.
The `.git` device, inode, birth time, canonical path, and command definitions
remain identical. The replacement script executes in CLI, Bash, Zsh, and Fish.
Changing the command definition then blocks execution on every path.

This behavior is reproducible on both v3.0.0 and current main. It demonstrates
the limit of the existing command-definition trust model: neither repository
history nor delegated script bytes are attested. It requires the ability to
replace the approved repository's contents; an ordinary checkout of changed
delegated code already has the same effect. Replacing the common Git directory
itself is a different case and remains covered by the original identity tests.

Assessment: this is not a new command-approval bypass under the documented
model, but the original statement that any replacement requires approval was
too broad. The configuration documentation now explicitly describes retaining
the directory while reseeding its contents. A requirement to reject this case
would require a stronger content/provenance approval model and a decision about
normal commits and updates to delegated code. Adding another repository-owned
identity file would not attest that code. Seif's final scope decision remains
outstanding; this assessment does not decide HackerOne report status or payment.

## Old shell caches: H1 #4153317

Controlled historical retest generated actual init=6 helpers using v2.11.1,
created its path-only approval, replaced `.git`, and changed the delegated
script while retaining the command. Executing the Bash/Zsh/Fish setup from the
v3.0.0 README loaded the old cache and executed the replacement marker in all
three shells. Fresh v3.0.0 init=7 helpers blocked the same old approval, as did
current init=16 helpers. This confirms an upgrade bypass, rather than a failure
of a fresh installation's identity check.

The old startup snippets skip the installed CLI entirely when `init=6` matches.
Consequently, a CLI schema bump alone cannot invalidate that path. The v3.0.0
release still contained those snippets. [PR #215](https://github.com/coderabbitai/git-worktree-runner/pull/215)
subsequently changed the README/help setup to invoke the installed CLI at every
startup, bumped the schema, and documented migration. Current init tests execute
the actual README/help snippets against old caches, including schemas 6 and 7,
and test rejection of older trust formats. The new follow-up tests retain the
old snippet as a counterexample and verify explicit regeneration removes it.

Users must replace direct-cache or hard-coded-schema startup snippets with the
current documented setup and restart/reload their shell. Already-loaded
functions also require reloading. Merely installing a binary cannot rewrite
startup files or functions in another running shell.

## Versions, impact, and closure evidence

- The original trust mechanism appears in released tags beginning with v2.7.1;
  this retest directly demonstrates the old-cache path from v2.11.1 to v3.0.0.
  It does not claim exhaustive testing of every intermediate release.
- Retained-directory behavior remains present in v3.0.0 and main by design.
  Impact is execution of changed code delegated by an already approved command.
- #4153317 overlaps VULN-566 as incomplete upgrade remediation: the old helpers
  preserve the original path-only approval behavior. The retained-directory
  case shares the delegated-script impact but has different preconditions and
  is not automatically equivalent to that migration defect.
- The October 28 statement that the original H1 report was Resolved is supplied
  history. No live HackerOne status or private report contents were accessed.
- v3.0.0 was published October 28 at 22:58:54 UTC and contains #207/#211 but
  predates #215. At retest time it was the latest published GitHub release.
  [Release evidence](https://github.com/coderabbitai/git-worktree-runner/releases/tag/v3.0.0).
  A release containing #215 plus upgrade retesting is still needed for closure;
  this PR does not publish a release or claim researcher acceptance.

Local validation: all seven follow-up cases pass on current main; all seven also
pass against the v3.0.0 source archive (they intentionally document the retained
identity and legacy-startup behavior). Historical cache execution used Bash
5.3, Zsh 5.9, and Fish 4.9 on macOS with private XDG directories and isolated Git
configuration. Fresh/current helpers blocked the legacy approval in each shell.
Use `bats tests/trust_followup.bats tests/cmd_trust.bats tests/hooks.bats tests/init.bats`
for the maintained regression suite. CI on this PR provides the corresponding
Linux checks.

The validation and documentation work is ready for review. Release timing and
Seif's stronger-boundary/duplicate decision are the closure blockers; no release
ETA or deadline is assumed. No Linear, Slack, or HackerOne updates were posted.
