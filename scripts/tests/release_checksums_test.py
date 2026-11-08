import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml


ROOT = Path(__file__).resolve().parents[2]


class ReleaseChecksumTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="fileinfra-checksums-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.artifacts = self.root / "artifacts"
        self.artifacts.mkdir()
        script = ROOT / "scripts/release_checksums.py"
        if script.exists():
            (self.root / "scripts").mkdir()
            shutil.copy2(script, self.root / "scripts")
        workflow = yaml.safe_load((ROOT / ".github/workflows/build.yml").read_text())
        self.command = next(step["run"] for step in workflow["jobs"]["release"]["steps"]
                            if step.get("name") == "Generate checksums")

    def artifact(self, relative):
        path = self.artifacts / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(b"release artifact " + relative.encode())
        return path

    def generate(self):
        return subprocess.run(["bash", "-eu", "-c", self.command], cwd=self.root,
                              text=True, capture_output=True)

    def test_manifest_verifies_in_a_flat_download_directory(self):
        packages = [self.artifact("android/fileinfra-1.2.3-android-arm64.apk"),
                    self.artifact("linux/FileInfra-1.2.3-linux-x64.tar.gz")]
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)
        downloads = self.root / "downloads"
        downloads.mkdir()
        for package in packages:
            shutil.copy2(package, downloads / package.name)
        verified = subprocess.run(["sha256sum", "--check", str(self.artifacts / "checksums.txt")],
                                  cwd=downloads, text=True, capture_output=True)
        self.assertEqual(verified.returncode, 0, verified.stdout + verified.stderr)

    def test_empty_artifact_set_fails(self):
        self.assertNotEqual(self.generate().returncode, 0)

    def test_duplicate_download_names_fail(self):
        self.artifact("first/fileinfra-1.2.3-android-arm64.apk")
        self.artifact("second/fileinfra-1.2.3-android-arm64.apk")
        self.assertNotEqual(self.generate().returncode, 0)

    def test_ios_archive_is_included_without_unpacked_app_files(self):
        package = self.artifact("ios/FileInfra-1.2.3-ios-arm64.zip")
        self.artifact("ios/FileInfra.app/Frameworks/Example.framework/Example")
        result = self.generate()
        self.assertEqual(result.returncode, 0, result.stderr)
        lines = (self.artifacts / "checksums.txt").read_text().splitlines()
        self.assertEqual(len(lines), 1)
        self.assertTrue(lines[0].endswith("  " + package.name), lines)


if __name__ == "__main__":
    unittest.main()
