#!/usr/bin/env python3
"""Reproduce SIGTTOU on a PTY and check timeout --foreground avoids it."""
import errno
import os
import pty
import subprocess
import sys


def run(foreground):
    pid, master = pty.fork()
    if pid == 0:
        command = ['timeout'] + (['--foreground'] if foreground else [])
        # This parent retains the terminal foreground process group while
        # ordinary timeout puts its child in a background group.
        probe = ('import termios; '
                 'termios.tcsetattr(0, termios.TCSANOW, termios.tcgetattr(0)); '
                 'print("TERMINAL_SETUP_OK", flush=True)')
        result = subprocess.run(command + ['1', sys.executable, '-c', probe])
        os._exit(result.returncode)
    output = bytearray()
    try:
        while True:
            try:
                data = os.read(master, 4096)
            except OSError as error:
                if error.errno == errno.EIO:
                    break
                raise
            if not data:
                break
            output.extend(data)
    finally:
        os.close(master)
    _, status = os.waitpid(pid, 0)
    return os.waitstatus_to_exitcode(status), bytes(output)


status, output = run(False)
assert status == 124 and b'TERMINAL_SETUP_OK' not in output, (status, output)
status, output = run(True)
assert status == 0 and b'TERMINAL_SETUP_OK' in output, (status, output)
print('PASS: ordinary timeout stops terminal setup; --foreground completes it')
