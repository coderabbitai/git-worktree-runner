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
    """Check literal argv and marker absence through Git and standalone completion."""
    project = Path(sys.argv[1])
    shell = shutil.which(sys.argv[2])
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
    for branch in list(branches.values()) + ["sharedé$(>marker-shared)a", "sharedé$(>marker-shared)b"]:
        subprocess.run(["git", "branch", branch], env=env, check=True, capture_output=True)
    (repo / "directory-target").mkdir()

    init = state / "init.bash"
    init.write_bytes(subprocess.check_output([str(project / "bin/gtr"), "init", "bash"], env=env))
    bindir = state / "bin"
    bindir.mkdir()
    capture = state / "argv"
    stub = bindir / "git-gtr"
    stub.write_text('#!/bin/bash\nprintf "%s\\0" "$@" > "$CAPTURE_PATH"\n')
    stub.chmod(0o755)
    env.update(PATH=str(bindir) + os.pathsep + env["PATH"], CAPTURE_PATH=str(capture))

    setup = state / "setup.bash"
    # The optional paths let manual checks use the real installed completion libraries.
    lines = []
    for name in ("GTR_TEST_BASH_COMPLETION", "GTR_TEST_GIT_COMPLETION"):
        if env.get(name):
            lines.append("source " + shlex.quote(env[name]))
    lines += ["source " + shlex.quote(str(project / "completions/gtr.bash")),
              "source " + shlex.quote(str(init))]
    if not env.get("GTR_TEST_GIT_COMPLETION"):
        lines.append("complete -o nospace -F _git_gtr git")
    if not env.get("GTR_TEST_BASH_COMPLETION"):
        lines.append('_init_completion() { words=("${COMP_WORDS[@]}"); cword=$COMP_CWORD; '
                     'cur=${words[cword]}; prev=${words[cword-1]}; COMPREPLY=(); }')
    setup.write_text("\n".join(lines) + "\n")

    pid, fd = pty.fork()
    if pid == 0:
        os.execve(shell, [shell, "--noprofile", "--norc", "-i"], env)

    def read_prompt():
        """Read through the next primary prompt, failing within five seconds."""
        output = b""
        deadline = time.monotonic() + 5
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
        for invocation in ("git gtr", "gtr"):
            for command in ("go", "run", "rm", "mv", "rename", "editor", "ai", "copy"):
                for prefix, branch in list(branches.items()) + [("shared", "sharedé$(>marker-shared)b")]:
                    prefixes = (prefix, "'" + prefix, '"' + prefix, "$'" + prefix,
                                prefix[:2] + "'" + prefix[2:], prefix[:2] + '"' + prefix[2:],
                                prefix[:2] + "$'" + prefix[2:])
                    for typed in prefixes:
                        if capture.exists():
                            capture.unlink()
                        # An ambiguous first Tab is narrowed before the second Tab.
                        keys = typed + ("\tb\t\n" if prefix == "shared" else "\t\n")
                        os.write(fd, (invocation + " " + command + " " + keys).encode())
                        transcript = read_prompt()
                        assert capture.exists(), transcript
                        expected = (command + "\0" + branch + "\0").encode()
                        actual = capture.read_bytes()
                        assert actual == expected, (keys, expected, actual, transcript)
                        assert not list(repo.glob("marker-*")), transcript
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
