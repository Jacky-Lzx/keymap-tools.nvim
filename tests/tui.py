#!/usr/bin/env python3
"""Send terminal input to Neovim; exercise the actual sibling selection-tools."""
import errno
import fcntl
import os
from pathlib import Path
import pty
import select
import shutil
import signal
import struct
import subprocess
import tempfile
import termios
import time

root = Path(__file__).resolve().parents[1]
actions = {
    "prefix": b" ", "subgroup": b"s", "back": b"\x7f", "escape": b"\x1b",
    "fast": b" sa", "count": b"3 sj", "register": b'"a sy', "builtin": b"gg",
    "pick": b" ?", "pick_expr": b" ?", "pick_plug": b" ?",
    "filter_local": b"Local action", "filter_expr": b"Expression action",
    "filter_plug": b"Remapped action", "visual": b"vj ?", "filter_visual": b"Visual action",
    "filter_stale": b"Stale action", "cancel_picker": b"\x1b",
    **{f"confirm_{name}": b"\r" for name in ("local", "expr", "plug", "visual", "stale")},
}
with tempfile.TemporaryDirectory(prefix="keymap-tools-", dir="/private/tmp" if Path("/private/tmp").exists() else None) as directory:
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
    env = dict(os.environ, TERM="xterm-256color", KEYMAP_TOOLS_TEST_DIR=directory,
               NVIM_LOG_FILE=directory + "/nvim.log")
    process = subprocess.Popen([os.environ.get("NVIM_BIN") or shutil.which("nvim"), "-u", "NONE", "-n", "-i", "NONE",
                                "-c", "lua dofile('tests/tui.lua')"], cwd=root, env=env,
                               stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
    handled, output = set(), bytearray()
    deadline = time.monotonic() + 25
    try:
        while process.poll() is None and time.monotonic() < deadline:
            if select.select([master], [], [], 0.02)[0]:
                try:
                    output.extend(os.read(master, 65536))
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
            file = Path(directory, "stage")
            stage = file.read_text().strip() if file.exists() else ""
            if stage in handled:
                continue
            if stage == "resize":
                fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 32, 0, 0))
                os.kill(process.pid, signal.SIGWINCH)
                handled.add(stage)
            elif stage in actions:
                if stage == "pick":
                    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
                    os.kill(process.pid, signal.SIGWINCH)
                os.write(master, actions[stage])
                handled.add(stage)
        if process.poll() is None:
            process.kill()
        process.wait()
        result_file = Path(directory, "result")
        result = result_file.read_text() if result_file.exists() else "No result; stages: " + repr(handled)
        assert process.returncode == 0 and result.startswith("PASS"), result + "\n" + output.decode(errors="replace")[-5000:]
        print(result.strip())
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        os.close(master)
