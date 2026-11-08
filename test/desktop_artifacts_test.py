"""Desktop packaging regressions; run with python3 -m unittest discover -s test -p desktop_artifacts_test.py.

Uses real CMake installs, ELF symbol tables, deb/tar metadata, and a compiled
Dart executable loading a C library. Flutter compilation and linuxdeploy are
external build boundaries and are replaced by fixtures. To package existing
release bundles instead of small compiled ELF fixtures, set
FILEINFRA_TEST_RELEASE_ROOT to a directory containing tar-linux-x86_64,
tar-linux-aarch64 and tar-compat-linux-x86_64 (each with a fileinfra bundle).
"""

import concurrent.futures
import hashlib
import io
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tarfile
import tempfile
import unittest
import zipfile


REPO = Path(__file__).resolve().parents[1]


def run(*args, cwd=None, env=None, check=True):
    result = subprocess.run(args, cwd=cwd, env=env, text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    if check and result.returncode:
        raise AssertionError(f"Command failed ({result.returncode}): {args}\n{result.stdout}")
    return result


def write(path, content, executable=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content)
    if executable:
        path.chmod(0o755)


class LinuxPackagingTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="fi-linux-package-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.output = self.root / "output"
        self.build = self.root / "build"
        self.native_outputs = self.root / "native-outputs"
        self.native_build_log = self.root / "native-build.log"
        self.script = self.root / "scripts/build_linux.sh"
        self.script.parent.mkdir()
        shutil.copy(REPO / "scripts/build_linux.sh", self.script)
        write(self.root / "scripts/build_dufs.sh", '''#!/bin/bash
set -euo pipefail
case "$1" in
  linux-x86_64) arch=x86_64 ;;
  linux-arm64) arch=aarch64 ;;
  *) exit 2 ;;
esac
printf '%s\\n' "$1" >> "$FI_NATIVE_BUILD_LOG"
cp "$FI_NATIVE_OUTPUTS/libdufs-$arch.so" "assets/dufs/libdufs-linux-$arch.so"
''', True)
        write(self.root / "pubspec.yaml", "version: 0.5.12+57\n")
        shutil.copytree(REPO / "assets/icon", self.root / "assets/icon")
        write(self.root / "bin/flutter", "#!/bin/bash\n[[ \"$*\" == 'build linux --release' ]]\n", True)
        # The original script has an absolute tool cache path. Stub only that
        # external boundary, without writing to the machine's shared /tmp.
        write(self.root / "build-boundaries.sh", '''
function [() {
  if [[ "$1" == -f && "$2" == /tmp/linuxdeploy-* ]]; then return 0; fi
  builtin [ "$@"
}
function /tmp/linuxdeploy-x86_64() { : > "$OUTPUT"; }
function /tmp/linuxdeploy-aarch64() { : > "$OUTPUT"; }
''')
        self.env = dict(os.environ, PATH=f"{self.root / 'bin'}:{os.environ['PATH']}",
                        FILEINFRA_BUILD_ROOT=str(self.build),
                        FILEINFRA_OUTPUT_DIR=str(self.output),
                        FI_NATIVE_OUTPUTS=str(self.native_outputs),
                        FI_NATIVE_BUILD_LOG=str(self.native_build_log),
                        BASH_ENV=str(self.root / "build-boundaries.sh"))

    def make_bundle(self, arch="x86_64", compat=False):
        flutter_arch = "arm64" if arch == "aarch64" else "x64"
        bundle = self.build / f"linux/{flutter_arch}/release/bundle"
        source_root = os.environ.get("FILEINFRA_TEST_RELEASE_ROOT")
        if source_root:
            name = f"tar-{'compat-' if compat else ''}linux-{arch}"
            shutil.copytree(Path(source_root) / name / "fileinfra", bundle)
        else:
            # Construct real versioned ELF imports without depending on the
            # host's glibc version or requiring an old Ubuntu installation.
            glibc = "2.27" if compat else "2.38"
            glibcxx = "3.4.21" if compat else "3.4.29"
            write(self.root / "provider.c", "int fi_glibc(void){return 0;}\nint fi_glibcxx(void){return 0;}\n")
            write(self.root / "versions", f"GLIBC_{glibc} {{ global: fi_glibc; }};\nGLIBCXX_{glibcxx} {{ global: fi_glibcxx; }};\n")
            write(self.root / "consumer.c", "extern int fi_glibc(void), fi_glibcxx(void);\nint main(void){return fi_glibc()+fi_glibcxx();}\n")
            bundle.mkdir(parents=True)
            run("gcc", "-nostdlib", "-shared", "-fPIC", str(self.root / "provider.c"),
                f"-Wl,--version-script={self.root / 'versions'}", "-o", str(self.root / "libfixture.so"))
            (bundle / "lib").mkdir()
            run("gcc", "-nostdlib", "-shared", "-fPIC", str(self.root / "consumer.c"),
                f"-L{self.root}", "-lfixture", "-o", str(bundle / "lib/libplugin.so"))
            write(self.root / "main.c", "int main(void){return 0;}\n")
            run("gcc", "-nostdlib", "-shared", "-fPIC", str(self.root / "main.c"),
                "-o", str(bundle / "fileinfra"))
            (bundle / "fileinfra").chmod(0o755)
            shutil.copy(self.root / "libfixture.so", bundle / "libdufs.so")
            write(bundle / "data/build-marker", "fresh bundle\n")
        assets = self.root / "assets/dufs"
        assets.mkdir(parents=True, exist_ok=True)
        shutil.copy(bundle / "libdufs.so", assets / f"libdufs-linux-{arch}.so")
        self.native_outputs.mkdir(exist_ok=True)
        shutil.copy(bundle / "libdufs.so", self.native_outputs / f"libdufs-{arch}.so")
        self.env["FILEINFRA_ARCHIVE_SUFFIX"] = "-compat" if compat else ""
        return bundle

    def package(self, arch="x86_64", check=True):
        return run("bash", str(self.script), arch,
                   cwd=self.root, env=self.env, check=check)

    def deb(self, arch="x86_64", compat=False):
        suffix = "-compat" if compat else ""
        return self.output / f"fileinfra-0.5.12{suffix}-linux-{arch}.deb"

    def test_normal_deb_rejects_systems_below_actual_elf_requirements(self):
        for arch in ("x86_64", "aarch64"):
            with self.subTest(arch=arch):
                self.make_bundle(arch)
                self.package(arch)
                depends = run("dpkg-deb", "-f", str(self.deb(arch)), "Depends").stdout
                self.assertIn("libc6 (>= 2.38)", depends)
                self.assertRegex(depends, r"libstdc\+\+6 \(>= 11(?:\.\d+)*\)")

    def test_packaging_refreshes_existing_native_library(self):
        bundle = self.make_bundle()
        fresh = (bundle / "libdufs.so").read_bytes()
        (self.root / "assets/dufs/libdufs-linux-x86_64.so").write_bytes(b"stale native core")
        self.package()
        self.assertEqual((self.output / "fileinfra/libdufs.so").read_bytes(), fresh)
        self.assertEqual(self.native_build_log.read_text(), "linux-x86_64\n")

    def test_packaging_rejects_unknown_architecture(self):
        self.make_bundle()
        result = self.package("arm64", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Unsupported Linux architecture", result.stdout)
        self.assertFalse(self.native_build_log.exists())

    def test_compat_deb_keeps_ubuntu_18_04_dependency_floor(self):
        self.make_bundle(compat=True)
        self.package()
        depends = run("dpkg-deb", "-f", str(self.deb(compat=True)), "Depends").stdout
        self.assertIn("libc6 (>= 2.27)", depends)
        match = re.search(r"libstdc\+\+6 \(>= ([\d.]+)\)", depends)
        self.assertIsNotNone(match, depends)
        self.assertLessEqual(float(match.group(1)), 6.0)

    def test_deb_declares_graphics_libraries_loaded_indirectly_by_libepoxy(self):
        for arch in ("x86_64", "aarch64"):
            with self.subTest(arch=arch):
                self.make_bundle(arch)
                self.package(arch)
                depends = run("dpkg-deb", "-f", str(self.deb(arch)), "Depends").stdout
                packages = {entry.strip().split(" ")[0] for entry in depends.split(",")}
                self.assertTrue({"libegl1", "libgles1", "libgles2"}.issubset(packages), depends)

    def test_compat_rejects_newer_elf_instead_of_mislabeling_the_package(self):
        self.make_bundle()
        self.env["FILEINFRA_ARCHIVE_SUFFIX"] = "-compat"
        result = self.package(check=False)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("2.27", result.stdout)
        self.assertFalse(self.deb(compat=True).exists())

    def test_deb_members_are_owned_by_root(self):
        self.make_bundle()
        self.package()
        archive = subprocess.check_output(["dpkg-deb", "--fsys-tarfile", str(self.deb())])
        with tarfile.open(fileobj=io.BytesIO(archive)) as data:
            owners = {(entry.uid, entry.gid) for entry in data}
        self.assertEqual(owners, {(0, 0)})

    def test_repackaging_removes_stale_files_and_does_not_nest_bundle(self):
        bundle = self.make_bundle()
        self.package()
        write(self.output / "fileinfra/stale-file", "old\n")
        write(bundle / "data/new-marker", "new\n")
        self.package()
        archive = self.output / "fileinfra-0.5.12-linux-x86_64.tar.gz"
        with tarfile.open(archive) as data:
            names = set(data.getnames())
            self.assertNotIn("fileinfra/stale-file", names)
            self.assertFalse(any(name.startswith("fileinfra/bundle/") for name in names))
            self.assertIn("fileinfra/data/new-marker", names)
        installed = self.output / "fileinfra-deb/opt/fileinfra"
        self.assertEqual((installed / "data/new-marker").read_text(), "new\n")

    def test_desktop_entries_match_window_class_and_install_real_icon(self):
        self.make_bundle()
        self.package()
        extracted = self.root / "installed"
        run("dpkg-deb", "-x", str(self.deb()), str(extracted))
        for desktop in (extracted / "usr/share/applications/fileinfra.desktop",
                        self.output / "fileinfra.AppDir/fileinfra.desktop"):
            values = dict(line.split("=", 1) for line in desktop.read_text().splitlines() if "=" in line)
            self.assertEqual(values.get("StartupWMClass"), "cc.merr.fileinfra")
            self.assertEqual(values.get("Icon"), "fileinfra")
        icon = extracted / "usr/share/icons/hicolor/256x256/apps/fileinfra.png"
        self.assertEqual(icon.read_bytes(), (REPO / "assets/icon/app_icon.png").read_bytes())

    @unittest.skipUnless(shutil.which("rpmbuild"), "rpmbuild is not installed")
    def test_rpm_build_works_with_rpmbuilds_own_working_directory(self):
        self.make_bundle()
        self.package()
        package = self.output / "fileinfra-0.5.12-linux-x86_64.rpm"
        self.assertTrue(package.exists(), "rpmbuild did not produce the release package")
        database = self.root / "rpm-database"
        database.mkdir()
        metadata = run("rpm", "--dbpath", str(database), "-qp", "--qf", "%{NAME} %{VERSION}", str(package)).stdout
        self.assertEqual(metadata, "fileinfra 0.5.12")
        requires = run("rpm", "--dbpath", str(database), "-qp", "--requires", str(package)).stdout.splitlines()
        self.assertTrue({"libEGL.so.1()(64bit)", "libGLESv1_CM.so.1()(64bit)",
                         "libGLESv2.so.2()(64bit)"}.issubset(set(requires)), requires)
        files = run("rpm", "--dbpath", str(database), "-qpl", str(package)).stdout.splitlines()
        self.assertIn("/opt/fileinfra/libdufs.so", files)
        self.assertIn("/usr/bin/fileinfra", files)
        self.assertFalse(any("/bundle/" in path for path in files))


class WindowsRuntimeInstallTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="fi-windows-install-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.source = self.root / "source"
        self.source.mkdir()
        for path in (REPO / "windows").glob("*.cmake"):
            shutil.copy(path, self.source / path.name)
        if (REPO / "windows/cmake").exists():
            shutil.copytree(REPO / "windows/cmake", self.source / "cmake")
        shutil.copy(REPO / "windows/CMakeLists.txt", self.source / "CMakeLists.txt")
        self.runtime_names = ("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")
        self.redist = self.root / "redist"
        for name in self.runtime_names:
            write(self.redist / name, f"fixture runtime bytes: {name}\n")
        # Stub only MSVC's platform-specific discovery. Installation is done
        # by the project's real CMake rules against actual fixture files.
        write(self.source / "modules/InstallRequiredSystemLibraries.cmake", '''
file(GLOB CMAKE_INSTALL_SYSTEM_RUNTIME_LIBS "${TEST_REDIST}/*.dll")
''')
        write(self.source / "flutter/CMakeLists.txt", '''
set(MSVC TRUE PARENT_SCOPE)
list(APPEND CMAKE_MODULE_PATH "${CMAKE_SOURCE_DIR}/modules")
set(CMAKE_MODULE_PATH "${CMAKE_MODULE_PATH}" PARENT_SCOPE)
set(PROJECT_BUILD_DIR "${CMAKE_BINARY_DIR}/payload/" PARENT_SCOPE)
file(MAKE_DIRECTORY "${CMAKE_BINARY_DIR}/payload/native_assets/windows" "${CMAKE_BINARY_DIR}/payload/flutter_assets")
foreach(name icu flutter aot)
  file(WRITE "${CMAKE_BINARY_DIR}/payload/${name}" "${name}")
endforeach()
set(FLUTTER_ICU_DATA_FILE "${CMAKE_BINARY_DIR}/payload/icu" PARENT_SCOPE)
set(FLUTTER_LIBRARY "${CMAKE_BINARY_DIR}/payload/flutter" PARENT_SCOPE)
set(AOT_LIBRARY "${CMAKE_BINARY_DIR}/payload/aot" PARENT_SCOPE)
''')
        write(self.source / "flutter/generated_plugins.cmake", "")
        write(self.source / "runner/CMakeLists.txt", "add_executable(fileinfra main.cc)\n")
        write(self.source / "runner/main.cc", "int main() { return 0; }\n")
        self.build = self.root / "build"
        self.install = self.root / "installed"

    def configure(self):
        run("cmake", "-S", str(self.source), "-B", str(self.build),
            f"-DTEST_REDIST={self.redist}", f"-DCMAKE_INSTALL_PREFIX={self.install}",
            "-DCMAKE_BUILD_TYPE=Release")
        run("cmake", "--build", str(self.build))

    def install_config(self, config="Release", check=True):
        return run("cmake", "--install", str(self.build), "--config", config,
                   "--component", "Runtime", check=check)

    def test_release_runtime_is_beside_executable_and_in_zip(self):
        self.configure()
        self.install_config()
        self.assertTrue((self.install / "fileinfra").exists())
        archive_path = self.root / "bundle.zip"
        with zipfile.ZipFile(archive_path, "w") as archive:
            for path in self.install.rglob("*"):
                if path.is_file():
                    archive.write(path, path.relative_to(self.install))
        with zipfile.ZipFile(archive_path) as archive:
            for name in self.runtime_names:
                self.assertIn(name, archive.namelist())
                self.assertEqual(archive.read(name), (self.redist / name).read_bytes())

    def test_release_install_fails_if_required_runtime_was_not_discovered(self):
        (self.redist / "vcruntime140_1.dll").unlink()
        self.configure()
        result = self.install_config(check=False)
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("vcruntime140_1.dll", result.stdout.lower())

    def test_missing_release_runtime_does_not_block_debug_install(self):
        (self.redist / "vcruntime140_1.dll").unlink()
        self.configure()
        self.install_config("Debug")

    def test_release_install_fails_if_runtime_disappears_after_configure(self):
        self.configure()
        (self.redist / "vcruntime140.dll").unlink()
        result = self.install_config(check=False)
        self.assertNotEqual(result.returncode, 0, result.stdout)


class AppImageDufsStagingTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temp = tempfile.TemporaryDirectory(prefix="fi-appimage-ffi-test-")
        cls.addClassCleanup(cls.temp.cleanup)
        cls.root = Path(cls.temp.name)
        cls.mount = cls.root / ".mount_fileinfra-test/usr/bin"
        cls.mount.mkdir(parents=True)
        write(cls.root / "probe.dart", f'''
import 'dart:convert';
import 'dart:io';
import '{(REPO / 'lib/services/dufs_ffi.dart').as_uri()}';
Future<void> main(List<String> args) async {{
  final path = await resolveDufsLibPath();
  if (args.contains('--resolve-only')) {{ print(path); return; }}
  if (args.contains('--cancel')) {{
    await discardResolvedDufsLibPath(args.last);
    await discardResolvedDufsLibPath(path);
    await discardResolvedDufsLibPath(path);
    print(jsonEncode({{'path': path, 'existsAfterDiscard': await File(path).exists()}}));
    return;
  }}
  final ffi = DufsFfi();
  ffi.load(path);
  print(jsonEncode({{'path': path, 'marker': ffi.start(['dufs']),
    'existsAfterLoad': await File(path).exists()}}));
}}
''')
        cls.probe = cls.mount / "fileinfra"
        run("dart", "compile", "exe", f"--packages={REPO / '.dart_tool/package_config.json'}",
            str(cls.root / "probe.dart"), "-o", str(cls.probe), cwd=REPO)
        for name, marker in (("trusted", 23), ("planted", 99)):
            write(cls.root / f"{name}.c", f"int dufs_start(int argc, char** argv) {{ return {marker}; }}\n"
                  "void dufs_stop(void) {}\nint dufs_is_running(void) { return 1; }\n")
            run("gcc", "-shared", "-fPIC", str(cls.root / f"{name}.c"),
                "-o", str(cls.root / f"{name}.so"))
        shutil.copy(cls.root / "trusted.so", cls.mount / "libdufs.so")
        cls.mtime_ms = 1793432122000
        os.utime(cls.mount / "libdufs.so", ns=(cls.mtime_ms * 1000000,) * 2)

    def setUp(self):
        self.shared = Path(tempfile.mkdtemp(prefix="shared-", dir=self.root))
        self.addCleanup(shutil.rmtree, self.shared)
        self.shared.chmod(0o777)
        self.env = dict(os.environ, TMPDIR=str(self.shared))

    def probe_result(self, probe=None, check=True):
        result = run(str(probe or self.probe), env=self.env, check=check)
        return json.loads(result.stdout) if check else result

    def test_planted_legacy_path_is_never_loaded_or_deleted(self):
        planted = self.shared / f"fileinfra-libdufs-{self.mtime_ms}.so"
        shutil.copy(self.root / "planted.so", planted)
        before = hashlib.sha256(planted.read_bytes()).hexdigest()
        result = self.probe_result()
        self.assertEqual(result["marker"], 23, result)
        self.assertNotEqual(result["path"], str(planted))
        self.assertEqual(hashlib.sha256(planted.read_bytes()).hexdigest(), before)

    def test_other_shared_temp_libraries_are_not_swept(self):
        other = self.shared / "fileinfra-libdufs-123.so"
        other.write_bytes(b"another user's file")
        self.probe_result()
        self.assertTrue(other.exists(), "an unrelated shared temporary library was swept")
        self.assertEqual(other.read_bytes(), b"another user's file")

    def test_parallel_launches_use_distinct_private_staging_and_cleanup(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(lambda _: self.probe_result(), range(4)))
        self.assertEqual(len({result["path"] for result in results}), 4)
        for result in results:
            self.assertEqual(result["marker"], 23)
            self.assertFalse(result["existsAfterLoad"], result)
            self.assertFalse(Path(result["path"]).parent.exists(), result)
        self.assertEqual(list(self.shared.iterdir()), [])

    def test_resolved_copy_is_private_before_loading(self):
        path = Path(run(str(self.probe), "--resolve-only", env=self.env).stdout.strip())
        self.assertEqual(path.read_bytes(), (self.root / "trusted.so").read_bytes())
        self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)
        self.assertEqual(path.parent.stat().st_uid, os.getuid())

    def test_private_staging_even_with_permissive_umask(self):
        result = run("bash", "-c", 'umask 000; exec "$@"', "bash",
                     str(self.probe), "--resolve-only", env=self.env)
        path = Path(result.stdout.strip())
        self.assertEqual(stat.S_IMODE(path.parent.stat().st_mode), 0o700)
        self.assertEqual(path.read_bytes(), (self.root / "trusted.so").read_bytes())

    def test_failed_load_cleans_only_its_owned_staging_directory(self):
        broken_mount = self.root / ".mount_broken/usr/bin"
        broken_mount.mkdir(parents=True, exist_ok=True)
        shutil.copy(self.probe, broken_mount / "fileinfra")
        write(broken_mount / "libdufs.so", "invalid library\n")
        result = self.probe_result(broken_mount / "fileinfra", check=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Failed to load dynamic library", result.stdout)
        self.assertEqual(list(self.shared.iterdir()), [])

    def test_canceled_resolve_discards_own_copy_and_preserves_unregistered_file(self):
        unrelated = self.shared / "fileinfra-libdufs-unregistered"
        unrelated.mkdir()
        other = unrelated / "libdufs.so"
        other.write_bytes(b"another launch")
        result = json.loads(run(str(self.probe), "--cancel", str(other), env=self.env).stdout)
        self.assertFalse(result["existsAfterDiscard"])
        self.assertFalse(Path(result["path"]).parent.exists())
        self.assertEqual(other.read_bytes(), b"another launch")


if __name__ == "__main__":
    unittest.main()
