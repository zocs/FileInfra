#!/usr/bin/env python3
"""Exercise the shipped native FFI library, its HTTP listener and restarts."""

import base64
import ctypes
import socket
import sys
import tempfile
import time
import urllib.request
from pathlib import Path


def verify(path: Path) -> None:
    library = ctypes.CDLL(str(path.resolve()))
    library.dufs_start.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_char_p)]
    library.dufs_start.restype = ctypes.c_int
    library.dufs_stop.argtypes = []
    library.dufs_stop.restype = None
    library.dufs_is_running.argtypes = []
    library.dufs_is_running.restype = ctypes.c_int
    if library.dufs_start(-1, None) != -1:
        raise RuntimeError("FFI accepted invalid argc")

    with socket.socket() as probe:
        probe.bind(("127.0.0.1", 0))
        port = probe.getsockname()[1]
    origin = f"http://127.0.0.1:{port}"
    authorization = "Basic " + base64.b64encode(b"fileinfra:verification").decode()

    with tempfile.TemporaryDirectory(prefix="fileinfra-ffi-") as temporary:
        root = Path(temporary)
        (root / "hello.txt").write_bytes(b"native FFI\n")
        for cycle in range(3):
            args = ["dufs", str(root), "-b", "127.0.0.1", "-p", str(port),
                    "-A", "--auth", "fileinfra:verification@/:rw",
                    "--log-file", str(root / f"cycle-{cycle}.log")]
            encoded = [arg.encode("utf-8") for arg in args]
            argv = (ctypes.c_char_p * len(encoded))(*encoded)
            try:
                if library.dufs_start(len(encoded), argv) != 0:
                    raise RuntimeError(f"FFI start failed on cycle {cycle}")
                if library.dufs_is_running() != 1:
                    raise RuntimeError("FFI did not report its running state")

                def request(target, method="GET", data=None, destination=None):
                    headers = {"Authorization": authorization}
                    if destination:
                        headers["Destination"] = origin + destination
                    req = urllib.request.Request(origin + target, data=data,
                                                 headers=headers, method=method)
                    return urllib.request.urlopen(req, timeout=5)

                deadline = time.monotonic() + 5
                while True:
                    try:
                        with request("/hello.txt") as response:
                            if response.read() != b"native FFI\n":
                                raise RuntimeError("FFI download was truncated")
                        break
                    except (OSError, urllib.error.URLError):
                        if time.monotonic() >= deadline:
                            raise
                        time.sleep(0.05)
                with request("/put.txt", "PUT", b"uploaded\n"):
                    pass
                with request("/put.txt", "MOVE", destination="/moved.txt"):
                    pass
                with request("/moved.txt", "COPY", destination="/copied.txt"):
                    pass
                with request("/copied.txt") as response:
                    if response.read() != b"uploaded\n":
                        raise RuntimeError("native MOVE/COPY lost file contents")
            finally:
                library.dufs_stop()
                if library.dufs_is_running() != 0:
                    raise RuntimeError("FFI still reports running after stop")
            time.sleep(0.1)
    print(f"Native FFI verified: {path.name}, HTTP GET/PUT/MOVE/COPY, three restarts")


if __name__ == "__main__":
    verify(Path(sys.argv[1]))
