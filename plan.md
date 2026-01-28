# Plan: Add `--no-verify` Flag to `git gtr new`

## Overview

Add a `--no-verify` flag to the `new` command that skips `postCreate` hooks, following Git's standard naming convention for skipping hooks (e.g., `git commit --no-verify`).

---

## Phase 1: Code Implementation

### 1.1 Modify `bin/gtr` - `cmd_create()` function

| Location | Change |
|----------|--------|
| **Line ~131-132** | Add variable declaration: `local skip_hooks=0` alongside `skip_copy` and `skip_fetch` |
| **Line ~155-162** | Add flag parsing case in the while loop: |

```bash
--no-verify)
  skip_hooks=1
  shift
  ;;
```

| Location | Change |
|----------|--------|
| **Line ~316-320** | Wrap the `run_hooks_in postCreate` call in a conditional: |

```bash
# Run post-create hooks (unless --no-verify)
if [ "$skip_hooks" -eq 0 ]; then
  run_hooks_in postCreate "$worktree_path" \
    REPO_ROOT="$repo_root" \
    WORKTREE_PATH="$worktree_path" \
    BRANCH="$branch_name"
fi
```

### 1.2 Modify `bin/gtr` - `cmd_help()` function

| Location | Change |
|----------|--------|
| **Line ~1550** | Add `--no-verify: skip post-create hooks` after `--no-fetch` line |

---

## Phase 2: Shell Completion Updates

### 2.1 `completions/gtr.bash` (Bash)

| Location | Change |
|----------|--------|
| **Line 62** | Add `--no-verify` to the COMPREPLY options list |

### 2.2 `completions/_git-gtr` (Zsh)

| Location | Change |
|----------|--------|
| **Line ~60-61** | Add `'--no-verify[Skip post-create hooks]'` to the `_arguments` list |

### 2.3 `completions/git-gtr.fish` (Fish)

| Location | Change |
|----------|--------|
| **Line ~57** | Add completion entry after `--no-fetch`: |

```fish
complete -c git -n '__fish_git_gtr_using_command new' -l no-verify -d 'Skip post-create hooks'
```

---

## Phase 3: Documentation Updates

### 3.1 `README.md`

| Location | Change |
|----------|--------|
| **Line ~173** | Add `- \`--no-verify\`: Skip post-create hooks` after `--no-fetch` |

### 3.2 `docs/advanced-usage.md`

| Location | Change |
|----------|--------|
| **Line ~128** | Add table row: `| \`--no-verify\` | Skip post-create hooks |` |

### 3.3 `CLAUDE.md` - Manual Testing Workflow section

| Location | Change |
|----------|--------|
| **~Line 65** | Add test case for `--no-verify` flag in manual testing workflow |

```bash
# Test --no-verify flag
git config --add gtr.hook.postCreate "echo 'Created!' > /tmp/gtr-test"
./bin/gtr new test-no-verify --no-verify
# Expected: /tmp/gtr-test should NOT be created
ls /tmp/gtr-test 2>&1  # Should fail
./bin/gtr rm test-no-verify
git config --unset gtr.hook.postCreate
```

---

## Phase 4: Manual Testing

Since this project has **no automated tests**, all testing must be done manually.

### 4.1 Basic functionality tests

```bash
# Test 1: Create worktree WITH hooks (default behavior)
git config --add gtr.hook.postCreate "echo 'Hook ran!' > /tmp/gtr-hook-test"
./bin/gtr new test-with-hooks
# Expected: /tmp/gtr-hook-test file should exist with "Hook ran!"
cat /tmp/gtr-hook-test
rm /tmp/gtr-hook-test
./bin/gtr rm test-with-hooks

# Test 2: Create worktree WITHOUT hooks (--no-verify)
./bin/gtr new test-no-verify --no-verify
# Expected: /tmp/gtr-hook-test should NOT be created
ls /tmp/gtr-hook-test 2>&1  # Should show "No such file or directory"
./bin/gtr rm test-no-verify

# Clean up config
git config --unset gtr.hook.postCreate
```

### 4.2 Combination tests with other flags

```bash
# Test 3: --no-verify combined with --no-copy
git config --add gtr.hook.postCreate "echo 'Hook ran!' > /tmp/gtr-combo-test"
./bin/gtr new test-combo --no-verify --no-copy
# Expected: Hook should NOT run, files should NOT be copied
ls /tmp/gtr-combo-test 2>&1  # Should fail
./bin/gtr rm test-combo
git config --unset gtr.hook.postCreate

# Test 4: --no-verify combined with --editor
./bin/gtr new test-editor --no-verify -e
# Expected: Worktree created, editor opens, hooks NOT run
./bin/gtr rm test-editor
```

### 4.3 Shell completion tests

```bash
# Test 5: Bash/Zsh completion
git gtr new --no<TAB>
# Expected: Should suggest --no-verify, --no-copy, --no-fetch
```

### 4.4 Help text verification

```bash
# Test 6: Help displays the new flag
./bin/gtr help | grep -A15 "new <branch>"
# Expected: Should show --no-verify in the list
```

### 4.5 Edge cases

```bash
# Test 7: Verify --no-verify doesn't affect preRemove/postRemove hooks
git config --add gtr.hook.postRemove "echo 'Remove hook!' > /tmp/gtr-remove-test"
./bin/gtr new test-remove --no-verify
./bin/gtr rm test-remove
# Expected: /tmp/gtr-remove-test SHOULD exist (--no-verify only affects postCreate)
cat /tmp/gtr-remove-test
rm /tmp/gtr-remove-test
git config --unset gtr.hook.postRemove
```

### 4.6 Cross-platform verification (if available)

- [ ] Test on macOS
- [ ] Test on Linux (Ubuntu/Fedora/Arch)
- [ ] Test on Windows Git Bash

---

## Summary of Files to Modify

| File | Changes |
|------|---------|
| `bin/gtr` | Add flag variable, parsing, conditional execution, help text |
| `completions/gtr.bash` | Add `--no-verify` to completion list |
| `completions/_git-gtr` | Add `--no-verify` to _arguments |
| `completions/git-gtr.fish` | Add `--no-verify` completion entry |
| `README.md` | Document the flag in Options section |
| `docs/advanced-usage.md` | Add to automation flags table |
| `CLAUDE.md` | Add `--no-verify` test case to manual testing section |

---

## Compliance with CONTRIBUTING.md

| Guideline | Status |
|-----------|--------|
| Cross-platform first | ✅ Simple boolean logic works everywhere |
| No external dependencies | ✅ No new dependencies |
| Maintain compatibility | ✅ Default behavior unchanged |
| Update docs | ✅ README, advanced-usage, CLAUDE.md |
| Update completions | ✅ All three shells included |
| Consider edge cases | ✅ Testing checklist covers edge cases |
| Manual testing | ✅ Comprehensive test plan |
