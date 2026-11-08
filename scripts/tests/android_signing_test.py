"""Certificate continuity across actual apksigner 35/36/37 output formats."""

import importlib.util
from pathlib import Path
import subprocess
import unittest
from unittest import mock


SCRIPT = Path(__file__).resolve().parents[1] / "verify_android_signing.py"
SPEC = importlib.util.spec_from_file_location("verify_android_signing", SCRIPT)
SIGNING = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SIGNING)
CERT = "e4db9054ff7070e4bee3387e928e1388facfec0526da10e4510282e9d26aed6a"


class AndroidSigningTest(unittest.TestCase):
    def test_sdk35_and_36_signer_label(self):
        output = "Signer #1 certificate SHA-256 digest: " + CERT + "\n"
        self.assertEqual(SIGNING.certificate_digest(output), CERT)

    def test_sdk37_scheme_labels_and_duplicate_certificate(self):
        output = ("V2 Signer: certificate SHA-256 digest: " + CERT + "\n"
                  "V3 Signer: certificate SHA-256 digest: " + CERT + "\n")
        self.assertEqual(SIGNING.certificate_digest(output), CERT)

    def test_uppercase_certificate_is_normalized(self):
        output = "V2 Signer: certificate SHA-256 digest: " + CERT.upper() + "\n"
        self.assertEqual(SIGNING.certificate_digest(output), CERT)

    def test_missing_certificate_is_rejected(self):
        with self.assertRaises(ValueError):
            SIGNING.certificate_digest("Verifies\n")

    def test_malformed_certificate_is_rejected(self):
        for value in ("", "abc", "g" * 64, CERT + " trailing text"):
            with self.subTest(value=value), self.assertRaises(ValueError):
                SIGNING.certificate_digest("V2 Signer: certificate SHA-256 digest: " + value)

    def test_distinct_certificates_are_rejected(self):
        output = ("Signer #1 certificate SHA-256 digest: " + CERT + "\n"
                  "Signer #2 certificate SHA-256 digest: " + "0" * 64 + "\n")
        with self.assertRaises(ValueError):
            SIGNING.certificate_digest(output)

    def test_failed_signature_verification_cannot_pass_with_a_printed_certificate(self):
        result = subprocess.CompletedProcess([], 1, "V2 Signer: certificate SHA-256 digest: " + CERT)
        with mock.patch.object(SIGNING.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(RuntimeError, "signature verification failed"):
                SIGNING.verify_apk("apksigner", Path("release.apk"), CERT)

    def test_different_valid_certificate_is_rejected(self):
        result = subprocess.CompletedProcess([], 0, "V2 Signer: certificate SHA-256 digest: " + "0" * 64)
        with mock.patch.object(SIGNING.subprocess, "run", return_value=result):
            with self.assertRaisesRegex(RuntimeError, CERT):
                SIGNING.verify_apk("apksigner", Path("release.apk"), CERT)

    def test_valid_signature_and_certificate_are_required_together(self):
        result = subprocess.CompletedProcess([], 0, "V2 Signer: certificate SHA-256 digest: " + CERT)
        with mock.patch.object(SIGNING.subprocess, "run", return_value=result) as verify:
            self.assertEqual(SIGNING.verify_apk("apksigner", Path("release.apk"), CERT), CERT)
        self.assertEqual(verify.call_args[0][0], ["apksigner", "verify", "--print-certs", "release.apk"])


if __name__ == "__main__":
    unittest.main()
