#!/usr/bin/env python3
"""Verify APK signatures and certificate continuity across apksigner versions."""

import argparse
from pathlib import Path
import re
import subprocess
import sys


CERTIFICATE_FIELD = "certificate SHA-256 digest:"


def normalized_digest(value):
    value = value.strip().lower()
    if not re.fullmatch(r"[0-9a-f]{64}", value):
        raise ValueError("certificate SHA-256 digest must contain exactly 64 hexadecimal characters")
    return value


def certificate_digest(output):
    # SDK 35/36 use "Signer #1"; SDK 37 uses scheme labels such as "V2 Signer".
    # Multiple schemes may print the same certificate. Distinct signers fail.
    certificates = set()
    for line in output.splitlines():
        if CERTIFICATE_FIELD in line:
            certificates.add(normalized_digest(line.split(CERTIFICATE_FIELD, 1)[1]))
    if len(certificates) != 1:
        raise ValueError("expected one distinct certificate SHA-256 digest; found: " +
                         (", ".join(sorted(certificates)) or "none"))
    return next(iter(certificates))


def verify_apk(apksigner, apk, expected):
    expected = normalized_digest(expected)
    result = subprocess.run([str(apksigner), "verify", "--print-certs", str(apk)],
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            universal_newlines=True)
    if result.returncode:
        raise RuntimeError("{} signature verification failed:\n{}".format(apk.name, result.stdout))
    actual = certificate_digest(result.stdout)
    if actual != expected:
        raise RuntimeError("{} certificate SHA-256 is {}; expected {}".format(apk.name, actual, expected))
    return actual


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("apksigner")
    parser.add_argument("expected_digest")
    parser.add_argument("apks", nargs="+", type=Path)
    args = parser.parse_args()
    try:
        for apk in args.apks:
            actual = verify_apk(args.apksigner, apk, args.expected_digest)
            print("Verified {}: certificate SHA-256 {}".format(apk.name, actual))
    except (OSError, RuntimeError, ValueError) as error:
        print("ERROR: " + str(error), file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
