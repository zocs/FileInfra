import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "fdroid_prep_check.py"


class RecipeContractTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="fileinfra-fdroid-test-")
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        spec = importlib.util.spec_from_file_location("fdroid_check", SCRIPT)
        self.check = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(self.check)
        self.check.ROOT = self.root
        self.check.PUBSPEC = self.root / "pubspec.yaml"
        self.check.WORKFLOW = self.root / "build.yml"
        self.check.PUBSPEC.write_text("version: 1.2.3+10\n", encoding="utf-8")
        self.check.WORKFLOW.write_text(
            "env:\n  FLUTTER_VERSION: '3.47.0'\n"
            "  EXPECTED_NDK_MAJOR: '29'\n  RUST_VERSION: '1.99.1'\n",
            encoding="utf-8",
        )
        (self.root / "scripts").mkdir()
        (self.root / "scripts/build_dufs.sh").write_text(
            'DUFS_VERSION="v0.47.0-fix1"\n', encoding="utf-8"
        )
        self.gradle = self.root / "android/app/build.gradle.kts"
        self.gradle.parent.mkdir(parents=True)
        self.gradle.write_text('val unsigned = System.getenv("FILEINFRA_UNSIGNED_RELEASE") == "1"\n',
                               encoding="utf-8")
        self.git("init", "--initial-branch=main")
        self.git("add", ".")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "commit", "-m", "fixture")
        sha = self.git("rev-parse", "HEAD").strip()
        self.git("update-ref", "refs/remotes/origin/main", sha)
        self.recipe = {
            "Builds": [{
                "versionName": "1.2.3", "versionCode": 10, "commit": sha,
                "output": "build/app/outputs/flutter-apk/app-release.apk",
                "build": ["export FILEINFRA_UNSIGNED_RELEASE=1",
                          "$$flutter$$/bin/flutter build apk --release"],
                "srclibs": ["flutter@3.47.0"], "ndk": "r29",
                "prebuild": [
                    "curl https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.99.1",
                    "bash scripts/build_dufs.sh android-arm64",
                    "bash scripts/build_dufs.sh android-arm",
                    "bash scripts/build_dufs.sh android-x86_64",
                ],
            }],
            "CurrentVersion": "1.2.3", "CurrentVersionCode": 10,
            "AutoUpdateMode": "Version", "UpdateCheckMode": "Tags",
            "UpdateCheckData": r"pubspec.yaml|version:\s+[^\s+]+\+(\d+)|.|version:\s+([^\s+]+)\+",
            "License": "MIT",
        }

    def git(self, *args):
        return subprocess.check_output(
            ["git", *args], cwd=self.root, text=True, stderr=subprocess.DEVNULL
        )

    def test_unsigned_recipe_can_use_pubspec_versions_and_fdroid_signing(self):
        self.check.check_recipe(self.recipe)
        self.assertEqual(self.check.FAILS, [])

    def test_developer_signing_key_requires_upstream_binary(self):
        self.recipe["AllowedAPKSigningKeys"] = "e" * 64
        self.check.check_recipe(self.recipe)
        self.assertTrue(any("Binaries" in failure for failure in self.check.FAILS))

    def test_tag_update_regex_must_extract_the_pubspec_version(self):
        self.recipe["UpdateCheckData"] = r"pubspec.yaml|version:(\d+)|.|version:(\d+)"
        self.check.check_recipe(self.recipe)
        self.assertTrue(any("UpdateCheckData" in failure for failure in self.check.FAILS))

    def test_rust_pin_drift_is_rejected(self):
        self.recipe["Builds"][0]["prebuild"][0] = (
            "curl https://sh.rustup.rs | sh -s -- -y --default-toolchain 1.98.0"
        )
        self.check.check_drift(self.recipe)
        self.assertTrue(any("Rust" in failure for failure in self.check.FAILS))

    def test_published_verification_branch_is_a_reachable_source(self):
        (self.root / "revision").write_text("candidate", encoding="utf-8")
        self.git("add", ".")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "commit", "-m", "candidate")
        sha = self.git("rev-parse", "HEAD").strip()
        self.git("update-ref", "refs/remotes/origin/verify", sha)
        self.recipe["Builds"][0]["commit"] = sha
        self.check.check_recipe(self.recipe)
        self.assertEqual(self.check.FAILS, [])

    def test_pinned_source_must_support_unsigned_release(self):
        self.gradle.write_text('signingConfig = signingConfigs.getByName("release")\n',
                               encoding="utf-8")
        self.git("add", ".")
        self.git("-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                 "commit", "-m", "old signing")
        sha = self.git("rev-parse", "HEAD").strip()
        self.git("update-ref", "refs/remotes/origin/main", sha)
        self.recipe["Builds"][0]["commit"] = sha
        self.check.check_recipe(self.recipe)
        self.assertTrue(any("FILEINFRA_UNSIGNED_RELEASE" in failure for failure in self.check.FAILS))

    def test_pinned_source_version_must_match_recipe(self):
        self.check.PUBSPEC.write_text("version: 1.2.4+11\n", encoding="utf-8")
        self.recipe["Builds"][0].update(versionName="1.2.4", versionCode=11)
        self.recipe.update(CurrentVersion="1.2.4", CurrentVersionCode=11)
        self.check.check_recipe(self.recipe)
        self.assertTrue(any("固定源码版本" in failure for failure in self.check.FAILS))


if __name__ == "__main__":
    unittest.main()
