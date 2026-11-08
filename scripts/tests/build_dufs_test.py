"""Source checkout tests using real isolated Git repositories.

Only the script's literal source pin/repository are configured in a temporary
project. Cargo/Rust/toolchain installation are compiler boundaries; Git is
never substituted. Unique fixture commits/tags also isolate the old script's
legacy /tmp cache during the red run. Final checkouts must respect TMPDIR.
"""

import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest
import uuid


REPO = Path(__file__).resolve().parents[2]


def run(*args, cwd=None, env=None, check=True):
    result = subprocess.run(args, cwd=cwd, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if check and result.returncode:
        raise AssertionError(f"Command failed ({result.returncode}): {args}\n{result.stdout}")
    return result


def write(path, text, executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    if executable:
        path.chmod(0o755)


CARGO_BOUNDARY = r'''#!/usr/bin/env python3
import json, os, pathlib, subprocess, sys
args = sys.argv[1:]
assert args[0] == 'build'
target = args[args.index('--target') + 1]
root = pathlib.Path.cwd()
record = {
    'args': args, 'cwd': str(root),
    'head': subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
    'source': (root / 'src/server.rs').read_text(),
    'lock': (root / 'Cargo.lock').read_text(),
    'shim': (root / 'src/lib.rs').read_text(),
    'config': (root / '.cargo/config.toml').read_text() if (root / '.cargo/config.toml').exists() else None,
    'cc': os.environ.get('CC'),
}
with open(os.environ['FI_CARGO_LOG'], 'a') as log:
    log.write(json.dumps(record) + '\n')
release = root / 'target' / target / 'release'
release.mkdir(parents=True, exist_ok=True)
for name in ['dufs', 'dufs.dll', 'libdufs.so', 'libdufs.dylib']:
    (release / name).write_text(json.dumps(record))
'''


class BuildDufsTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="fi-dufs-git-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.project = self.root / "project"
        self.source = self.root / "upstream"
        self.tag = f"v-fi-test-{uuid.uuid4().hex}"
        run("git", "init", str(self.source))
        run("git", "-C", str(self.source), "config", "user.name", "FileInfra test")
        run("git", "-C", str(self.source), "config", "user.email", "fileinfra-test@example.invalid")
        write(self.source / "Cargo.toml", '[package]\nname = "dufs"\nversion = "0.1.0"\n')
        write(self.source / "Cargo.lock", "version = 3\n# fixture locked dependencies\n")
        write(self.source / ".gitignore", "/target/\n")
        write(self.source / "src/lib.rs", "// upstream library\n")
        self.first_source = f"// source first {uuid.uuid4().hex}\n"
        write(self.source / "src/server.rs", self.first_source)
        self.first = self.commit("first")
        run("git", "-C", str(self.source), "tag", self.tag)
        write(self.source / "src/server.rs", "// source second\n")
        self.second = self.commit("second")
        self.log = self.root / "cargo.jsonl"
        self.sysroot = self.root / "rust-sysroot"
        targets = ["x86_64-unknown-linux-gnu", "aarch64-unknown-linux-gnu",
                   "aarch64-linux-android", "armv7-linux-androideabi", "x86_64-linux-android",
                   "x86_64-pc-windows-gnu", "x86_64-pc-windows-msvc",
                   "aarch64-apple-darwin", "x86_64-apple-darwin", "aarch64-apple-ios"]
        for target in targets:
            (self.sysroot / f"lib/rustlib/{target}/lib").mkdir(parents=True)
        write(self.root / "bin/cargo", CARGO_BOUNDARY, True)
        write(self.root / "bin/rustc", '#!/bin/bash\n[[ "$*" == "--print sysroot" ]] || exit 1\nprintf "%s\\n" "$FI_RUST_SYSROOT"\n', True)
        write(self.root / "bin/rustup", "#!/bin/bash\nexit 0\n", True)
        # Package installation only supplies cross compiler toolchains, which
        # the Cargo boundary above substitutes; never mutate host packages.
        write(self.root / "bin/sudo", '#!/bin/bash\n[[ "$1" == apt-get ]] || exit 1\n', True)
        self.ndk = self.root / "ndk"
        for host in ("linux-x86_64", "darwin-x86_64"):
            for prefix in ("aarch64-linux-android", "armv7a-linux-androideabi", "x86_64-linux-android"):
                write(self.ndk / f"toolchains/llvm/prebuilt/{host}/bin/{prefix}24-clang", "#!/bin/bash\nexit 0\n", True)
        self.checkout_temp = self.root / "checkout-temp"
        self.checkout_temp.mkdir()
        self.env = dict(os.environ, PATH=f"{self.root / 'bin'}:{os.environ['PATH']}",
                        TMPDIR=str(self.checkout_temp), FI_CARGO_LOG=str(self.log),
                        FI_RUST_SYSROOT=str(self.sysroot), ANDROID_NDK_HOME=str(self.ndk))
        self.env.pop("DUFS_NO_DEFAULT_FEATURES", None)
        self.env.pop("ANDROID_API", None)
        write(self.project / "scripts/dufs-ffi/lib.rs", "// fixture FFI shim\n")
        # Remove only this fixture's unique legacy caches, never sweep /tmp.
        for ref in (self.first, self.second, self.tag):
            legacy = Path("/tmp") / f"dufs-src-{ref}"
            self.assertFalse(legacy.exists(), f"fixture cache collision: {legacy}")
            self.addCleanup(shutil.rmtree, legacy, ignore_errors=True)

    def commit(self, message):
        run("git", "-C", str(self.source), "add", ".")
        run("git", "-C", str(self.source), "commit", "-qm", message)
        return run("git", "-C", str(self.source), "rev-parse", "HEAD").stdout.strip()

    def configured_script(self, ref):
        text = (REPO / "scripts/build_dufs.sh").read_text()
        text, pin_count = re.subn(r'^DUFS_VERSION="[^"\n]+"', f'DUFS_VERSION="{ref}"', text, count=1, flags=re.M)
        text, repo_count = re.subn(r'^DUFS_REPO="[^"\n]+"', f'DUFS_REPO="{self.source.as_uri()}"', text, count=1, flags=re.M)
        if pin_count != 1 or repo_count != 1:
            raise AssertionError("could not configure the literal source pin/repository for the fixture")
        path = self.project / "scripts/build_dufs.sh"
        write(path, text)
        return path

    def build(self, ref=None, platform="linux-x86_64", check=True):
        return run("bash", str(self.configured_script(ref or self.tag)), platform,
                   env=self.env, cwd=self.project, check=check)

    def records(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_cold_full_sha_checks_out_exact_older_commit(self):
        self.build(self.first)
        record = self.records()[-1]
        self.assertEqual(record["head"], self.first)
        self.assertEqual(record["source"], self.first_source)
        self.assertEqual(Path(record["cwd"]).parent, self.checkout_temp)
        symbolic = run("git", "-C", record["cwd"], "symbolic-ref", "-q", "HEAD", check=False)
        self.assertNotEqual(symbolic.returncode, 0, "SHA checkout should be detached")

    def test_cached_sha_resets_dirty_tracked_and_untracked_source_before_shim(self):
        cache = self.checkout_temp / f"dufs-src-{self.first}"
        run("git", "clone", self.source.as_uri(), str(cache))
        write(cache / "src/server.rs", "// locally edited source\n")
        write(cache / "Cargo.lock", "changed dependencies\n")
        write(cache / "src/untracked.rs", "// unwanted source\n")
        write(cache / "target/cached-compiler-object", "preserve ignored compilation cache\n")
        self.build(self.first)
        record = self.records()[-1]
        self.assertEqual(record["head"], self.first)
        self.assertEqual(record["source"], self.first_source)
        self.assertEqual(record["lock"], "version = 3\n# fixture locked dependencies\n")
        self.assertEqual(record["shim"], "// fixture FFI shim\n")
        self.assertFalse((cache / "src/untracked.rs").exists())
        self.assertEqual((cache / "target/cached-compiler-object").read_text(), "preserve ignored compilation cache\n")

    def test_forced_tag_refresh_follows_retagged_commit(self):
        self.build()
        self.assertEqual(self.records()[-1]["head"], self.first)
        run("git", "-C", str(self.source), "tag", "-f", self.tag, self.second)
        self.build()
        self.assertEqual(self.records()[-1]["head"], self.second)
        self.assertEqual(self.records()[-1]["source"], "// source second\n")

    def test_cached_origin_is_restored_to_configured_repository(self):
        self.build()
        cache = Path(self.records()[-1]["cwd"])
        other = self.root / "wrong-fork"
        run("git", "clone", self.source.as_uri(), str(other))
        run("git", "-C", str(other), "tag", "-f", self.tag, self.second)
        run("git", "-C", str(cache), "remote", "set-url", "origin", other.as_uri())
        self.build()
        self.assertEqual(self.records()[-1]["head"], self.first)
        self.assertEqual(run("git", "-C", str(cache), "remote", "get-url", "origin").stdout.strip(), self.source.as_uri())

    def test_cached_tag_removes_untracked_source_but_preserves_ignored_target(self):
        self.build()
        cache = Path(self.records()[-1]["cwd"])
        write(cache / "src/untracked.rs", "// injected source\n")
        write(cache / "target/keep", "compiled cache\n")
        self.build()
        self.assertFalse((cache / "src/untracked.rs").exists())
        self.assertEqual((cache / "target/keep").read_text(), "compiled cache\n")

    def test_all_platform_builds_are_locked_and_preserve_output_names_and_features(self):
        platforms = {
            "linux-x86_64": "assets/dufs/libdufs-linux-x86_64.so",
            "linux-arm64": "assets/dufs/libdufs-linux-aarch64.so",
            "windows-x86_64": "assets/dufs/dufs-windows-x86_64.dll",
            "macos-arm64": "assets/dufs/libdufs-macos-arm64.dylib",
            "macos-x86_64": "assets/dufs/libdufs-macos-x86_64.dylib",
            "ios-arm64": "ios/Frameworks/dufs",
            "android-arm64": "android/app/src/main/jniLibs/arm64-v8a/libdufs.so",
            "android-arm": "android/app/src/main/jniLibs/armeabi-v7a/libdufs.so",
            "android-x86_64": "android/app/src/main/jniLibs/x86_64/libdufs.so",
        }
        for platform, output in platforms.items():
            with self.subTest(platform=platform):
                self.build(platform=platform)
                record = self.records()[-1]
                self.assertIn("--locked", record["args"])
                self.assertEqual(json.loads((self.project / output).read_text())["head"], self.first)
                self.assertEqual("--no-default-features" in record["args"], platform == "ios-arm64")
                if platform.startswith("android-"):
                    self.assertTrue(record["cc"].endswith("24-clang"), record["cc"])
                    for flag in ("--pack-dyn-relocs=none", "max-page-size=0x1000", "common-page-size=0x1000"):
                        self.assertIn(flag, record["config"])
        self.env["DUFS_NO_DEFAULT_FEATURES"] = "1"
        self.build(platform="linux-x86_64")
        self.assertIn("--locked", self.records()[-1]["args"])
        self.assertIn("--no-default-features", self.records()[-1]["args"])

    def test_missing_ndk_error_names_both_supported_environment_variables(self):
        self.env.pop("ANDROID_NDK_HOME", None)
        self.env.pop("ANDROID_HOME", None)
        result = self.build(platform="android-arm64", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("ANDROID_NDK_HOME or ANDROID_HOME must be set", result.stdout)


if __name__ == "__main__":
    unittest.main()
