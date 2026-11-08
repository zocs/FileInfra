#!/usr/bin/env python3
"""Generate SHA-256 entries usable beside downloaded release attachments."""

import fnmatch
import hashlib
import sys
from pathlib import Path


PATTERNS = (
    "*.AppImage", "*.deb", "*.rpm", "*.tar.gz", "*.apk", "*.exe", "*.dmg",
    "*-windows-x64.zip", "*-macos-arm64.zip", "*-macos-x64.zip", "*-ios-arm64.zip",
)


def generate(root: Path) -> None:
    packages = {}
    for path in root.rglob("*"):
        if not path.is_file() or not any(fnmatch.fnmatchcase(path.name, p) for p in PATTERNS):
            continue
        if path.name in packages:
            raise ValueError(f"duplicate attachment name: {path.name}")
        if any(char in path.name for char in "\n\r\\"):
            raise ValueError(f"unsupported attachment name: {path.name!r}")
        packages[path.name] = path
    if not packages:
        raise ValueError("no release attachments found")

    lines = []
    for name, path in sorted(packages.items()):
        digest = hashlib.sha256()
        with path.open("rb") as package:
            for chunk in iter(lambda: package.read(1024 * 1024), b""):
                digest.update(chunk)
        lines.append(f"{digest.hexdigest()}  {name}\n")
    (root / "checksums.txt").write_text("".join(lines), encoding="utf-8")


if __name__ == "__main__":
    try:
        generate(Path(sys.argv[1]))
    except (IndexError, OSError, ValueError) as error:
        print(f"Cannot generate release checksums: {error}", file=sys.stderr)
        sys.exit(1)
