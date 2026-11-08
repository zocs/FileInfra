"""macOS packaging boundary tests, runnable on Linux or macOS.

Real Mach-O headers, lipo, file, ZIP contents and filesystem symlinks are used.
Native/Flutter compilation and Apple codesign are substituted; the signing double
produces/verifies content seals so missing signing, stale seals and damaged ZIPs
have observable effects. Native codesign verification runs in build_macos.sh.
"""

import json
import os
from pathlib import Path
import plistlib
import shutil
import stat
import struct
import subprocess
import tempfile
import unittest
import zipfile


REPO = Path(__file__).resolve().parents[1]
LIPO = shutil.which("lipo") or shutil.which("llvm-lipo")
ZIP = shutil.which("zip")


def write(path, content, executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    if executable:
        path.chmod(0o755)


def run(*args, cwd=None, env=None, check=True):
    result = subprocess.run(args, cwd=cwd, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if check and result.returncode:
        raise AssertionError(f"Command failed ({result.returncode}): {args}\n{result.stdout}")
    return result


def macho(path, architectures):
    """Minimal real Mach-O headers sufficient for file/lipo architecture checks."""
    slices = []
    for arch in architectures:
        cpu, subtype = (0x1000007, 3) if arch == "x86_64" else (0x100000c, 0)
        # dylib Mach-Os require LC_ID_DYLIB even in a minimal lipo fixture.
        identifier = b"@rpath/Fixture\0".ljust(16, b"\0")
        command = struct.pack("<IIIIII", 0xd, 40, 24, 0, 0, 0) + identifier
        header = struct.pack("<IiiIIIII", 0xfeedfacf, cpu, subtype, 6, 1, len(command), 0, 0)
        slices.append((cpu, subtype, header + command))
    if len(slices) == 1:
        payload = slices[0][2]
    else:
        payload = bytearray(4096 * (len(slices) + 1))
        struct.pack_into(">II", payload, 0, 0xcafebabe, len(slices))
        for i, (cpu, subtype, data) in enumerate(slices):
            offset = 4096 * (i + 1)
            struct.pack_into(">IIIII", payload, 8 + i * 20, cpu, subtype, offset, len(data), 12)
            payload[offset:offset + len(data)] = data
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload)
    path.chmod(0o755)


SIGNING_BOUNDARY = r'''#!/usr/bin/env python3
import hashlib, json, os, plistlib, sys
from pathlib import Path

args = sys.argv[1:]
target = Path(args[-1])
with open(os.environ['FI_CODESIGN_LOG'], 'a') as log:
    log.write(json.dumps(args) + '\n')

def contents(app):
    result = {}
    for entry in (app / 'Contents').rglob('*'):
        name = str(entry.relative_to(app / 'Contents'))
        if name.startswith('_CodeSignature/') or entry.is_dir(): continue
        if entry.is_symlink(): result[name] = {'symlink': os.readlink(entry)}
        elif entry.is_file(): result[name] = {'hash2': hashlib.sha256(entry.read_bytes()).digest()}
    return result

if '--sign' in args:
    assert '--force' in args
    assert args[args.index('--sign') + 1] == '-'
    assert '--timestamp=none' in args
    if target.is_dir():
        assert '--entitlements' in args
        entitlements = plistlib.loads(Path(args[args.index('--entitlements') + 1]).read_bytes())
        assert entitlements.get('com.apple.security.get-task-allow', False) is False
        library = target / 'Contents/MacOS/libdufs.dylib'
        if library.exists(): assert b'FIXTURE_ADHOC_SIGNATURE' in library.read_bytes()
        signature = target / 'Contents/_CodeSignature'
        signature.mkdir(exist_ok=True)
        manifest = contents(target)
        if os.environ.get('FI_SIGNING_FAULT') == 'unsealed-library':
            manifest.pop('MacOS/libdufs.dylib', None)
        (signature / 'CodeResources').write_bytes(plistlib.dumps({'files2': manifest}))
        (signature / 'FixtureEntitlements.plist').write_bytes(plistlib.dumps(entitlements))
    else:
        if os.environ.get('FI_SIGNING_FAULT') == 'sign-dylib':
            sys.exit('dylib signing failed')
        target.write_bytes(target.read_bytes() + b'FIXTURE_ADHOC_SIGNATURE')
elif '--verify' in args:
    assert '--deep' in args and '--strict' in args
    if os.environ.get('FI_SIGNING_FAULT') == 'verify':
        sys.exit('strict signature verification failed')
    seal = plistlib.loads((target / 'Contents/_CodeSignature/CodeResources').read_bytes())
    manifest = contents(target)
    if os.environ.get('FI_SIGNING_FAULT') == 'unsealed-library':
        manifest.pop('MacOS/libdufs.dylib', None)
    if seal['files2'] != manifest:
        sys.exit('staged or archived content is not sealed')
else:
    sys.exit('unexpected codesign operation')
'''


@unittest.skipUnless(LIPO and ZIP and shutil.which("file"), "file/lipo (or llvm-lipo)/zip are required")
class MacosPackagingTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="fi-macos-packaging-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / "project with spaces"
        self.root.mkdir()
        self.app = self.root / "build/macos/Build/Products/Release/FileInfra.app"
        self.staged = self.root / "build/macos/output/FileInfra.app"
        self.native_temp = self.root / "native temp"
        self.native_temp.mkdir()
        self.native_outputs = self.root / "native outputs"
        self.native_outputs.mkdir()
        self.native_build_log = self.root / "native-build.log"
        self.script = self.root / "scripts/build_macos.sh"
        self.script.parent.mkdir()
        shutil.copy(REPO / "scripts/build_macos.sh", self.script)
        entitlements = self.root / "macos/Runner/Release.entitlements"
        entitlements.parent.mkdir(parents=True)
        shutil.copy(REPO / "macos/Runner/Release.entitlements", entitlements)
        write(self.root / "scripts/build_dufs.sh", '''#!/bin/bash
set -euo pipefail
case "$1" in macos-arm64|macos-x86_64) ;; *) exit 2 ;; esac
printf '%s\\n' "$1" >> "$FI_NATIVE_BUILD_LOG"
cp "$FI_NATIVE_OUTPUTS/libdufs-$1.dylib" "assets/dufs/libdufs-$1.dylib"
''', True)
        write(self.root / "pubspec.yaml", "version: 0.5.12+57\n")
        write(self.root / "bin/flutter", "#!/bin/bash\n[[ \"$*\" == 'build macos --release' ]]\n", True)
        write(self.root / "bin/lipo", f"#!/bin/bash\nexec '{LIPO}' \"$@\"\n", True)
        write(self.root / "bin/codesign", SIGNING_BOUNDARY, True)
        write(self.root / "bin/zip", f'''#!/usr/bin/env python3
import os, pathlib, subprocess, sys, zipfile
subprocess.run([{ZIP!r}, *sys.argv[1:]], check=True)
if os.environ.get('FI_SIGNING_FAULT') == 'archive':
    archive = pathlib.Path(next(arg for arg in sys.argv[1:] if arg.endswith('.zip')))
    changed = archive.with_suffix('.changed.zip')
    with zipfile.ZipFile(archive) as original, zipfile.ZipFile(changed, 'w') as damaged:
        for info in original.infolist():
            data = original.read(info.filename)
            if info.filename.endswith('/Contents/MacOS/libdufs.dylib'): data = b'damaged archive library'
            damaged.writestr(info, data)
    changed.replace(archive)
''', True)
        self.log = self.root / "codesign.jsonl"
        self.env = dict(os.environ, PATH=f"{self.root / 'bin'}:{os.environ['PATH']}",
                        TMPDIR=str(self.native_temp), FI_CODESIGN_LOG=str(self.log),
                        FI_NATIVE_OUTPUTS=str(self.native_outputs),
                        FI_NATIVE_BUILD_LOG=str(self.native_build_log))
        macho(self.app / "Contents/MacOS/FileInfra", ("x86_64", "arm64"))
        framework = self.app / "Contents/Frameworks/FlutterMacOS.framework"
        macho(framework / "Versions/A/FlutterMacOS", ("x86_64", "arm64"))
        write(framework / "Versions/A/Resources/Info.plist", "framework resource\n")
        (framework / "Versions/Current").symlink_to("A")
        (framework / "FlutterMacOS").symlink_to("Versions/Current/FlutterMacOS")
        (framework / "Resources").symlink_to("Versions/Current/Resources")
        for platform, arch in (("arm64", "arm64"), ("x86_64", "x86_64")):
            library = self.root / f"assets/dufs/libdufs-macos-{platform}.dylib"
            macho(library, (arch,))
            shutil.copy(library, self.native_outputs / library.name)
        self.source_sign()

    def source_sign(self):
        run(str(self.root / "bin/codesign"), "--force", "--sign", "-", "--timestamp=none",
            "--entitlements", str(REPO / "macos/Runner/Release.entitlements"), str(self.app), env=self.env)
        self.log.unlink()

    def package(self, arch="aarch64", check=True):
        return run("bash", str(self.script), arch,
                   cwd=self.root, env=self.env, check=check)

    def archive(self, arch="arm64"):
        return self.root / f"build/macos/output/FileInfra-0.5.12-macos-{arch}.zip"

    def test_packaging_refreshes_existing_native_library(self):
        fresh = (self.native_outputs / "libdufs-macos-arm64.dylib").read_bytes()
        cached = self.root / "assets/dufs/libdufs-macos-arm64.dylib"
        cached.write_bytes(fresh + b"STALE_NATIVE_CORE")
        self.package()
        expected = fresh + b"FIXTURE_ADHOC_SIGNATURE"
        self.assertEqual((self.staged / "Contents/MacOS/libdufs.dylib").read_bytes(), expected)
        with zipfile.ZipFile(self.archive()) as archive:
            self.assertEqual(archive.read("FileInfra.app/Contents/MacOS/libdufs.dylib"), expected)
        self.assertEqual(self.native_build_log.read_text(), "macos-arm64\n")

    def test_copied_library_is_resigned_and_sealed_in_staged_app_and_zip(self):
        self.package()
        dylib = self.staged / "Contents/MacOS/libdufs.dylib"
        self.assertIn(b"FIXTURE_ADHOC_SIGNATURE", dylib.read_bytes())
        with zipfile.ZipFile(self.archive()) as archive:
            content = archive.read("FileInfra.app/Contents/MacOS/libdufs.dylib")
            seal = plistlib.loads(archive.read("FileInfra.app/Contents/_CodeSignature/CodeResources"))
            self.assertIn("MacOS/libdufs.dylib", seal["files2"])
            self.assertEqual(content, dylib.read_bytes())
            entitlements = plistlib.loads(archive.read("FileInfra.app/Contents/_CodeSignature/FixtureEntitlements.plist"))
            self.assertEqual(entitlements, plistlib.loads((REPO / "macos/Runner/Release.entitlements").read_bytes()))
        calls = [json.loads(line) for line in self.log.read_text().splitlines()]
        verifications = [args for args in calls if "--verify" in args]
        self.assertGreaterEqual(len(verifications), 2, "both staged app and extracted ZIP need native verification")
        self.assertEqual(list(self.native_temp.iterdir()), [], "archive verification staging was leaked")

    def test_framework_symlinks_are_preserved_in_real_zip(self):
        self.package()
        expected = {"Versions/Current": "A", "FlutterMacOS": "Versions/Current/FlutterMacOS",
                    "Resources": "Versions/Current/Resources"}
        with zipfile.ZipFile(self.archive()) as archive:
            for name, target in expected.items():
                entry = f"FileInfra.app/Contents/Frameworks/FlutterMacOS.framework/{name}"
                self.assertTrue(stat.S_ISLNK(archive.getinfo(entry).external_attr >> 16), entry)
                self.assertEqual(archive.read(entry).decode(), target)

    def test_repeat_packaging_discards_stale_bundle_and_archive_entries(self):
        self.package()
        write(self.staged / "Contents/stale-resource", "old")
        with zipfile.ZipFile(self.archive(), "a") as archive:
            archive.writestr("FileInfra.app/obsolete-entry", "old")
        self.package()
        with zipfile.ZipFile(self.archive()) as archive:
            names = archive.namelist()
            self.assertNotIn("FileInfra.app/obsolete-entry", names)
            self.assertNotIn("FileInfra.app/Contents/stale-resource", names)
            self.assertFalse(any(name.startswith("FileInfra.app/FileInfra.app/") for name in names))

    def test_x64_alias_pairs_x86_64_dufs_with_universal_app(self):
        self.package("x64")
        run(LIPO, str(self.staged / "Contents/MacOS/libdufs.dylib"), "-verify_arch", "x86_64")
        self.assertTrue(self.archive("x64").exists())

    def test_x64_rejects_arm64_only_framework(self):
        macho(self.app / "Contents/Frameworks/FlutterMacOS.framework/Versions/A/FlutterMacOS", ("arm64",))
        self.source_sign()
        result = self.package("x86_64", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("lacks x86_64", result.stdout)
        self.assertFalse(self.archive("x64").exists())

    def test_signing_failure_stops_packaging(self):
        self.archive().parent.mkdir(parents=True, exist_ok=True)
        self.archive().write_bytes(b"previous archive")
        self.env["FI_SIGNING_FAULT"] = "sign-dylib"
        result = self.package(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("dylib signing failed", result.stdout)
        self.assertFalse(self.archive().exists())

    def test_library_seal_is_required_even_when_native_verification_succeeds(self):
        self.env["FI_SIGNING_FAULT"] = "unsealed-library"
        result = self.package(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("libdufs.dylib is not sealed", result.stdout)
        self.assertFalse(self.archive().exists())

    def test_strict_verification_failure_stops_packaging(self):
        self.env["FI_SIGNING_FAULT"] = "verify"
        result = self.package(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("strict signature verification failed", result.stdout)
        self.assertFalse(self.archive().exists())

    def test_damaged_zip_is_detected_and_removed_after_extraction(self):
        self.env["FI_SIGNING_FAULT"] = "archive"
        result = self.package(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("not sealed", result.stdout)
        self.assertFalse(self.archive().exists())
        self.assertEqual(list(self.native_temp.iterdir()), [])

    def test_flattened_versioned_framework_is_rejected(self):
        framework = self.app / "Contents/Frameworks/FlutterMacOS.framework"
        (framework / "Versions/Current").unlink()
        shutil.copytree(framework / "Versions/A", framework / "Versions/Current")
        self.source_sign()
        result = self.package(check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Versions/Current", result.stdout)
        self.assertFalse(self.archive().exists())


if __name__ == "__main__":
    unittest.main()
