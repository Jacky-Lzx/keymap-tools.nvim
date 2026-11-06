#!/usr/bin/env python3
"""Drive staged keystrokes through a real terminal, not feedkeys-only tests."""
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
import sys
import tempfile
import termios
import time

root = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix="keymap-advanced-", dir="/tmp") as directory:
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 36, 110, 0, 0))
    env = dict(os.environ, TERM="xterm-256color", KEYMAP_TOOLS_TEST_DIR=directory,
               NVIM_LOG_FILE=directory + "/nvim.log")
    process = subprocess.Popen([os.environ.get("NVIM_BIN") or shutil.which("nvim"), "-u", "NONE", "-n", "-i", "NONE",
                                "-c", "lua dofile(" + repr(sys.argv[1] if len(sys.argv) > 1 else "tests/advanced_tui.lua") + ")"], cwd=root, env=env,
                               stdin=slave, stdout=slave, stderr=slave)
    os.close(slave)
    output, last_stage = bytearray(), ""
    deadline = time.monotonic() + 45
    try:
        while process.poll() is None and time.monotonic() < deadline:
            if select.select([master], [], [], 0.01)[0]:
                try:
                    output.extend(os.read(master, 65536))
                except OSError as error:
                    if error.errno != errno.EIO:
                        raise
            file = Path(directory, "stage")
            stage = file.read_text().strip() if file.exists() else ""
            if stage and stage != last_stage:
                resize = Path(directory, "resize")
                if resize.exists():
                    columns = int(resize.read_text())
                    resize.unlink()
                    fcntl.ioctl(master, termios.TIOCSWINSZ, struct.pack("HHHH", 36, columns, 0, 0))
                    os.kill(process.pid, signal.SIGWINCH)
                os.write(master, Path(directory, "input").read_bytes())
                Path(directory, "ack").write_text(stage)
                last_stage = stage
        if process.poll() is None:
            process.kill()
        process.wait()
        file = Path(directory, "result")
        result = file.read_text() if file.exists() else "No result; stage " + last_stage
        assert process.returncode == 0 and result.startswith("PASS"), result + "\n" + output.decode(errors="replace")[-5000:]
        print(result.strip())
    finally:
        if process.poll() is None:
            process.kill()
        process.wait()
        os.close(master)
