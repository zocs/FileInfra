"""Real owned-process cleanup regression; only the X-window query is a fixture."""

import os
from pathlib import Path
import signal
import subprocess
import sys
import tempfile
import time
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "verify_linux_gui.py"


def process_is_running(pid):
    try:
        status = Path("/proc/{}/stat".format(pid)).read_text()
    except FileNotFoundError:
        return False
    # A killed orphan may briefly await init's reap; it is no longer running.
    return status.rsplit(")", 1)[1].split()[0] != "Z"


@unittest.skipUnless(sys.platform.startswith("linux"), "Linux process groups and /proc required")
class LinuxGuiCleanupTest(unittest.TestCase):
    def test_cleanup_kills_term_ignoring_descendant_after_launcher_exits(self):
        with tempfile.TemporaryDirectory(prefix="fi-gui-cleanup-test-") as temporary:
            stage = Path(temporary)
            child = stage / "child.py"
            child.write_text("""import os, signal, sys, time
from pathlib import Path
signal.signal(signal.SIGTERM, signal.SIG_IGN)
Path(sys.argv[1]).write_text('{} {}'.format(os.getpid(), os.getpgrp()))
time.sleep(60)
""")
            launcher = stage / "launcher.py"
            launcher.write_text("""import os, subprocess, sys, time
from pathlib import Path
Path(sys.argv[1]).write_text(str(os.getpid()))
subprocess.Popen([sys.executable, sys.argv[2], sys.argv[3]])
time.sleep(60)
""")
            tools = stage / "bin"
            tools.mkdir()
            xwininfo = tools / "xwininfo"
            xwininfo.write_text("""#!/bin/sh
if [ -f "$FILEINFRA_GUI_VERIFY_STAGE/child.pid" ]; then
  printf '%s\n' '0x200002 "FileInfra": ("cc.merr.fileinfra" "Cc.merr.fileinfra")'
fi
""")
            xwininfo.chmod(0o755)
            env = dict(os.environ, FILEINFRA_GUI_VERIFY_STAGE=str(stage),
                       PATH=str(tools) + os.pathsep + os.environ["PATH"])
            launcher_pid = stage / "launcher.pid"
            child_pid = stage / "child.pid"
            try:
                result = subprocess.run(
                    [sys.executable, str(SCRIPT), "--desktop-session", sys.executable,
                     str(launcher), str(launcher_pid), str(child), str(child_pid)],
                    env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                    universal_newlines=True, timeout=30)
                self.assertEqual(result.returncode, 0, result.stdout)
                pid, group = map(int, child_pid.read_text().split())
                self.assertEqual(group, int(launcher_pid.read_text()))
                deadline = time.monotonic() + 3
                while process_is_running(pid) and time.monotonic() < deadline:
                    time.sleep(0.05)
                self.assertFalse(process_is_running(pid),
                                 "owned TERM-ignoring child survived verifier cleanup")
            finally:
                # Keep the fixture bounded even when the production assertion fails.
                if launcher_pid.exists():
                    try:
                        os.killpg(int(launcher_pid.read_text()), signal.SIGKILL)
                    except ProcessLookupError:
                        pass


if __name__ == "__main__":
    unittest.main()
