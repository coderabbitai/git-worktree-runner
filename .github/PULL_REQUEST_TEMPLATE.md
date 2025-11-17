# Pull Request

## Description

<!-- A clear and concise description of what this PR does -->

## Motivation

<!-- Why is this change needed? What problem does it solve? -->

Fixes # (issue)

## Type of Change

<!-- Check all that apply -->

- [ ] Bug fix (non-breaking change that fixes an issue)
- [ ] New feature (non-breaking change that adds functionality)
- [ ] Breaking change (fix or feature that would cause existing functionality to not work as expected)
- [ ] Documentation update
- [ ] Code refactoring (no functional changes)
- [ ] Other (please describe):

## Testing

<!-- Describe the tests you ran to verify your changes -->

### Manual Testing Checklist

**Tested on:**

- [ ] macOS
- [ ] Linux (specify distro: **\*\***\_**\*\***)
- [ ] Windows (Git Bash)

**Core functionality tested:**

- [ ] `git gtr new <branch>` - Create worktree
- [ ] `git gtr go <branch>` - Navigate to worktree
- [ ] `git gtr editor <branch>` - Open in editor (if applicable)
- [ ] `git gtr ai <branch>` - Start AI tool (if applicable)
- [ ] `git gtr rm <branch>` - Remove worktree
- [ ] `git gtr list` - List worktrees
- [ ] `git gtr config` - Configuration commands (if applicable)
- [ ] Other commands affected by this change: **\*\***\_\_**\*\***

### Test Steps

<!-- Provide detailed steps to reproduce/test your changes -->

1.
2.
3.

**Expected behavior:**

**Actual behavior:**

## Breaking Changes

<!-- If this introduces breaking changes, describe: -->
<!-- - What breaks -->
<!-- - Why it's necessary -->
<!-- - Migration path for users -->

- [ ] This PR introduces breaking changes
- [ ] I have discussed this in an issue first
- [ ] Migration guide is included in documentation

## Checklist

Before submitting this PR, please check:

- [ ] I have read [CONTRIBUTING.md](../CONTRIBUTING.md)
- [ ] My code follows the project's style guidelines
- [ ] I have performed manual testing on at least one platform
- [ ] I have updated documentation (README.md, CLAUDE.md, etc.) if needed
- [ ] My changes work on multiple platforms (or I've noted platform-specific behavior)
- [ ] I have added/updated shell completions (if adding new commands or flags)
- [ ] I have tested with both `git gtr` (production) and `./bin/gtr` (development)
- [ ] No new external dependencies are introduced (Bash + git only)
- [ ] All existing functionality still works

## Additional Context

<!-- Add any other context, screenshots, or information about the PR here -->

---

## License Acknowledgment

By submitting this pull request, I confirm that my contribution is made under the terms of the [Apache License 2.0](../LICENSE.txt).
