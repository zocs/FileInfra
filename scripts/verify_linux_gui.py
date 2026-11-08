#!/usr/bin/env python3
"""Require a real FileInfra window and continued startup in a private Xvfb session.

Usage: python3 verify_linux_gui.py /path/to/fileinfra [launcher arguments]
Requires dbus-run-session, xvfb-run, xauth, xwininfo and a working graphics driver.
Supports the Python 3.6 supplied by Ubuntu 18.04. No screenshots are captured.
"""

import os
from pathlib import Path
import shutil
import signal
import subprocess
import sys
import tempfile
import time


def verify_in_session(command):
    stage = Path(os.environ["FILEINFRA_GUI_VERIFY_STAGE"])
    process = None
    try:
        with (stage / "startup.log").open("w") as log:
            process = subprocess.Popen(command, stdin=subprocess.DEVNULL, stdout=log,
                                       stderr=subprocess.STDOUT, start_new_session=True)
            deadline = time.monotonic() + 20
            window_since = None
            while time.monotonic() < deadline:
                if process.poll() is not None:
                    raise RuntimeError("FileInfra exited during startup with code {}".format(process.returncode))
                windows = subprocess.run(["xwininfo", "-root", "-tree"],
                                         stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                         universal_newlines=True)
                if windows.returncode == 0 and '"FileInfra"' in windows.stdout:
                    if window_since is None:
                        window_since = time.monotonic()
                    elif time.monotonic() - window_since >= 5:
                        print("Linux GUI verified: FileInfra window present and process alive for five seconds")
                        return 0
                else:
                    window_since = None
                time.sleep(0.25)
            raise RuntimeError("FileInfra did not keep its window open within 20 seconds")
    except (OSError, RuntimeError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        print((stage / "startup.log").read_text(errors="replace"), file=sys.stderr)
        return 1
    finally:
        if process is not None:
            # The launcher owns this separate process group, including an
            # AppImage's extracted child; never terminate unrelated sessions.
            try:
                os.killpg(process.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                pass
            # A launcher can exit before its descendants handle TERM. Stop
            # remaining members even when the leader has already exited.
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            process.wait()


def main():
    command = sys.argv[1:]
    if command and command[0] == "--desktop-session":
        return verify_in_session(command[1:])
    if not command:
        print(__doc__, file=sys.stderr)
        return 2
    for tool in ("dbus-run-session", "xvfb-run", "xauth", "xwininfo"):
        if not shutil.which(tool):
            print("ERROR: missing GUI verification tool " + tool, file=sys.stderr)
            return 1
    with tempfile.TemporaryDirectory(prefix="fileinfra-gui-verify-") as temporary:
        stage = Path(temporary)
        env = dict(os.environ, FILEINFRA_GUI_VERIFY_STAGE=str(stage),
                   LIBGL_ALWAYS_SOFTWARE="1", GDK_BACKEND="x11")
        for variable, name in (("XDG_CONFIG_HOME", "config"), ("XDG_DATA_HOME", "data"),
                               ("XDG_CACHE_HOME", "cache"), ("XDG_RUNTIME_DIR", "runtime")):
            directory = stage / name
            directory.mkdir(mode=0o700)
            env[variable] = str(directory)
        result = subprocess.run(["dbus-run-session", "--", "xvfb-run", "--auto-servernum",
                                 sys.executable, str(Path(__file__).resolve()),
                                 "--desktop-session"] + command, env=env)
        return result.returncode


if __name__ == "__main__":
    sys.exit(main())
