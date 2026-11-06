#!/usr/bin/env python3
"""Exercise the generated completion with Readline, including C-locale quoted input."""

import os
from pathlib import Path
import pty
import select
import shlex
import shutil
import signal
import subprocess
import sys
import time


def main():
    """Check literal argv, cd destinations, and marker absence after Tab+Enter."""
    project = Path(sys.argv[1])
    shell = shutil.which(sys.argv[2])
    mode = sys.argv[3] if len(sys.argv) > 3 else "all"
    path_candidates = mode == "path-candidates"
    wrapper_only = mode != "all"
    repo = Path.cwd()
    state = repo.parent / "interactive"
    state.mkdir()
    env = dict(os.environ, GTR_DIR=str(project), LC_ALL="C", PS1="GTR_READY> ", PS2="GTR_MORE> ",
               HISTFILE="/dev/null", INPUTRC="/dev/null", TERM="dumb",
               XDG_CACHE_HOME=str(state / "cache"), XDG_CONFIG_HOME=str(state / "config"))
    branches = {
        "dollar": "dollar$(>marker-dollar)",
        "backtick": "backtick`>marker-backtick`",
        "quotes": "quotesé\"and'apostrophe",
        "unicode": "unicodeé$(>marker-unicode)",
        "bang": "bang!é$(>marker-bang)",
        "directory": "directory-target",
    }
    destinations = {"1": repo}
    if path_candidates:
        # The legacy porcelain output leaves tabs in paths unescaped. Its second
        # field can therefore contain arbitrary path text, not just a valid ref.
        branches = {
            "pathdollar": r"pathdollar\$(>marker-path-dollar)",
            "pathtick": r"pathtick\`>marker-path-tick`",
            "pathansi": r"pathansi\n\x27\047\141",
            "pathquote": "pathquote\\\"and\\'apostrophe",
            "pathslash": "pathslash\\",
        }
    registered = list(branches.values())
    if not path_candidates:
        registered += ["sharedé$(>marker-shared)a", "sharedé$(>marker-shared)b"]
    for index, branch in enumerate(registered):
        destination = state / f"worktree {index}"
        if path_candidates:
            destination = state / f"worktree {index}\t{branch}\tend"
            branch = f"path-target-{index}"
        subprocess.run(["git", "worktree", "add", "-b", branch, str(destination)],
                       env=env, check=True, capture_output=True)
        destinations[branch] = destination
    (repo / "directory-target").mkdir()

    init_files = []
    for wrapper in ("gtr", "worktrees"):
        init = state / f"init-{wrapper}.bash"
        init.write_bytes(subprocess.check_output(
            [str(project / "bin/gtr"), "init", "bash", "--as", wrapper], env=env))
        init_files.append(init)
    bindir = state / "bin"
    bindir.mkdir()
    capture = state / "argv"
    capture_cwd = state / "cwd"
    # This matrix never changes the registry. Snapshot the real porcelain output
    # once; the init BATS tests also exercise live filtering of registered targets.
    targets = state / "targets.tsv"
    targets.write_bytes(subprocess.check_output(
        [str(project / "bin/gtr"), "list", "--porcelain"], env=env))
    stub = bindir / "git-gtr"
    # Use real registered targets for cd completion and resolution. Other commands
    # only capture argv, so the destructive siblings never modify these worktrees.
    stub.write_text('#!/bin/bash\n'
                    'if [ "$1" = list ]; then cat "$GTR_TEST_TARGETS"; exit; fi\n'
                    'printf "%s\\0" "$@" > "$CAPTURE_PATH"\n'
                    'if [ "$1" = go ] && [ "$GTR_TEST_RESOLVE_CD" = 1 ]; then\n'
                    '  exec "$GTR_DIR/bin/git-gtr" "$@"\n'
                    'fi\n'
                    '# Path fragments are not valid targets; capture them then reject.\n'
                    'if [ "$GTR_TEST_RESOLVE_CD" = reject ]; then exit 1; fi\n')
    stub.chmod(0o755)
    env.update(PATH=str(bindir) + os.pathsep + env["PATH"], CAPTURE_PATH=str(capture),
               GTR_TEST_TARGETS=str(targets))

    setup = state / "setup.bash"
    # The optional paths let manual checks use the real installed completion libraries.
    lines = []
    if not wrapper_only:
        for name in ("GTR_TEST_BASH_COMPLETION", "GTR_TEST_GIT_COMPLETION"):
            if env.get(name):
                lines.append("source " + shlex.quote(env[name]))
        lines.append("source " + shlex.quote(str(project / "completions/gtr.bash")))
        if not env.get("GTR_TEST_GIT_COMPLETION"):
            lines.append("complete -o nospace -F _git_gtr git")
        if not env.get("GTR_TEST_BASH_COMPLETION"):
            lines.append('_init_completion() { words=("${COMP_WORDS[@]}"); cword=$COMP_CWORD; '
                         'cur=${words[cword]}; prev=${words[cword-1]}; COMPREPLY=(); }')
    lines += ["source " + shlex.quote(str(init)) for init in init_files]
    setup.write_text("\n".join(lines) + "\n")

    pid, fd = pty.fork()
    if pid == 0:
        os.execve(shell, [shell, "--noprofile", "--norc", "-i"], env)

    def read_prompt():
        """Read through the next primary prompt, allowing for loaded CI runners."""
        output = b""
        deadline = time.monotonic() + 15
        while not output.endswith(b"GTR_READY> "):
            remaining = deadline - time.monotonic()
            if remaining <= 0 or not select.select([fd], [], [], remaining)[0]:
                raise AssertionError("Bash did not return to its prompt: " + repr(output))
            output += os.read(fd, 65536)
        return output

    checks = 0
    try:
        read_prompt()
        os.write(fd, ("source " + shlex.quote(str(setup)) + "\n").encode())
        read_prompt()
        invocations = ("gtr", "worktrees") if wrapper_only else ("git gtr", "gtr", "worktrees")
        option_modes = ("-s", "-u") if path_candidates else (None,)
        for option, invocation in ((option, name) for option in option_modes for name in invocations):
            if option:
                # Bash 3.2 has no patsub_replacement; exercise both settings on 5.x.
                os.write(fd, ("shopt " + option + " patsub_replacement 2>/dev/null || true\n").encode())
                read_prompt()
            commands = () if wrapper_only else ("go", "run", "rm", "mv", "rename", "editor", "ai", "copy")
            if invocation != "git gtr":
                commands = ("cd",) + commands
            for command in commands:
                os.write(fd, ("export GTR_TEST_RESOLVE_CD=" +
                              ("reject" if path_candidates else "1" if command == "cd" else "0") + "\n").encode())
                read_prompt()
                candidates = list(branches.items())
                if not path_candidates:
                    candidates += [("shared", "sharedé$(>marker-shared)b"), ("1", "1")]
                for prefix, branch in candidates:
                    prefixes = (prefix, "'" + prefix, '"' + prefix, "$'" + prefix)
                    if len(prefix) > 2:
                        prefixes += (prefix[:2] + "'" + prefix[2:], prefix[:2] + '"' + prefix[2:],
                                     prefix[:2] + "$'" + prefix[2:])
                    for typed in prefixes:
                        if capture.exists():
                            capture.unlink()
                        # An ambiguous first Tab is narrowed before the second Tab.
                        keys = typed + ("\tb\t\n" if prefix == "shared" else "\t\n")
                        os.write(fd, (invocation + " " + command + " " + keys).encode())
                        transcript = read_prompt()
                        assert not list(repo.glob("marker-*")), transcript
                        assert capture.exists(), transcript
                        expected = (("go" if command == "cd" else command) + "\0" + branch + "\0").encode()
                        actual = capture.read_bytes()
                        assert actual == expected, (keys, expected, actual, transcript)
                        if command == "cd" and not path_candidates:
                            os.write(fd, ("pwd -P > " + shlex.quote(str(capture_cwd)) +
                                          "; builtin cd " + shlex.quote(str(repo)) + "\n").encode())
                            read_prompt()
                            assert capture_cwd.read_text().rstrip("\n") == str(destinations[branch]), transcript
                        checks += 1
        print(f"{checks} interactive completion checks passed")
    finally:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        os.waitpid(pid, 0)
        os.close(fd)


if __name__ == "__main__":
    main()
