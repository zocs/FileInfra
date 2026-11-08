#!/bin/bash
# build_macos.sh - Build and package FileInfra for macOS
# Usage: bash scripts/build_macos.sh [aarch64|x86_64]   (default: aarch64)
#   aarch64 (alias arm64)        -> FileInfra-<ver>-macos-arm64.zip  (Apple Silicon)
#   x86_64  (alias x64 / amd64)  -> FileInfra-<ver>-macos-x64.zip    (Intel)
#
# `flutter build macos --release` already produces a universal (arm64 + x86_64)
# app; libdufs.dylib is the only per-architecture piece, so each zip pairs the
# same universal app with the matching dufs library. On an Apple Silicon host
# (CI: macos-latest) the x86_64 dufs library is cross-compiled — no Intel
# runner is needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH=${1:-aarch64}
VERSION=$(grep '^version:' pubspec.yaml | head -1 | awk '{print $2}' | awk -F'+' '{print $1}')
APP_NAME="FileInfra"

# Architecture mapping. Unknown values are rejected instead of silently
# falling through to an x86_64 build (e.g. a typo such as "arm").
case "$ARCH" in
  aarch64|arm64)
    DUFS_PLATFORM="macos-arm64";  MACHO_ARCH="arm64";  DISPLAY_ARCH="arm64" ;;
  x86_64|x64|amd64)
    DUFS_PLATFORM="macos-x86_64"; MACHO_ARCH="x86_64"; DISPLAY_ARCH="x64" ;;
  *)
    echo "ERROR: unsupported arch '$ARCH' (expected aarch64 or x86_64)" >&2
    exit 1 ;;
esac
ARCHIVE_NAME="${APP_NAME}-${VERSION}-macos-${DISPLAY_ARCH}"

echo "Building FileInfra ${VERSION} for macOS ${DISPLAY_ARCH}..."

# Refresh the native core from the pinned source before packaging. Cargo's
# build cache remains available through build_dufs.sh.
# The name must match what build_dufs.sh writes for $DUFS_PLATFORM
# (libdufs-macos-arm64.dylib / libdufs-macos-x86_64.dylib).
DUFS_LIB="assets/dufs/libdufs-${DUFS_PLATFORM}.dylib"
echo "Compiling dufs shared library for ${DUFS_PLATFORM}..."
bash "${SCRIPT_DIR}/build_dufs.sh" "$DUFS_PLATFORM"

# Build Flutter macOS (release = universal arm64 + x86_64 binary)
flutter build macos --release

BUILD_DIR="build/macos/Build/Products/Release"
OUTPUT_DIR="build/macos/output"
mkdir -p "$OUTPUT_DIR"
ARCHIVE_PATH="${OUTPUT_DIR}/${ARCHIVE_NAME}.zip"
# A failed signing/verification attempt must not leave a previous archive
# available under the current build's name.
rm -f "$ARCHIVE_PATH"

# Copy .app bundle (Flutter outputs based on PRODUCT_NAME = FileInfra)
APP_BUNDLE="${BUILD_DIR}/${APP_NAME}.app"
if [ ! -d "$APP_BUNDLE" ]; then
  echo "ERROR: ${APP_BUNDLE} not found"
  ls "$BUILD_DIR/" 2>/dev/null
  exit 1
fi
# Start from a clean copy: `cp -r` onto an existing bundle would nest
# FileInfra.app/FileInfra.app and keep the previous run's libdufs.dylib.
STAGED_APP="${OUTPUT_DIR}/${APP_NAME}.app"
rm -rf "$STAGED_APP"
cp -R "$APP_BUNDLE" "$STAGED_APP"

# Include dufs shared library in the app bundle
APP_CONTENTS="${STAGED_APP}/Contents/MacOS"
cp "$DUFS_LIB" "${APP_CONTENTS}/libdufs.dylib"

# Every Mach-O in the bundle must carry the target slice. Flutter plans to make
# arm64-only the release default ("flutter config --enable-macos-arm64-only");
# an x64 zip without x86_64 slices would not launch on Intel Macs, and a
# libdufs.dylib of the wrong arch fails at "Start server" with dlopen errors.
verify_macho_architectures() {
  local bundle="$1" missing=0 f
  echo "Verifying every Mach-O in the bundle contains ${MACHO_ARCH}..."
  while IFS= read -r -d '' f; do
    case "$(file -b "$f")" in *Mach-O*) ;; *) continue ;; esac
    if ! lipo "$f" -verify_arch "$MACHO_ARCH" 2>/dev/null; then
      echo "ERROR: ${f#"${bundle}/"} lacks ${MACHO_ARCH} (has: $(lipo -archs "$f" 2>/dev/null || echo '?'))" >&2
      missing=1
    fi
  done < <(find "$bundle" -type f -print0)
  [ "$missing" = 0 ] || return 1
  echo "OK: all Mach-O binaries contain ${MACHO_ARCH} (libdufs.dylib: $(lipo -archs "${bundle}/Contents/MacOS/libdufs.dylib"))"
}

verify_framework_symlinks() {
  local bundle="$1" framework name link
  while IFS= read -r -d '' framework; do
    [ -d "${framework}/Versions" ] || continue
    if [ ! -L "${framework}/Versions/Current" ] || [ ! -d "${framework}/Versions/Current" ]; then
      echo "ERROR: ${framework}/Versions/Current must be a valid framework symlink" >&2
      return 1
    fi
    name="$(basename "$framework" .framework)"
    if [ -f "${framework}/Versions/Current/${name}" ] && [ ! -L "${framework}/${name}" ]; then
      echo "ERROR: ${framework}/${name} must be a framework symlink" >&2
      return 1
    fi
    if [ -d "${framework}/Versions/Current/Resources" ] && [ ! -L "${framework}/Resources" ]; then
      echo "ERROR: ${framework}/Resources must be a framework symlink" >&2
      return 1
    fi
  done < <(find "$bundle" -type d -name '*.framework' -print0)
  while IFS= read -r -d '' link; do
    if [ ! -e "$link" ]; then
      echo "ERROR: broken bundle symlink: ${link}" >&2
      return 1
    fi
  done < <(find "$bundle" -type l -print0)
}

verify_signed_bundle() {
  local bundle="$1"
  verify_macho_architectures "$bundle" || return 1
  verify_framework_symlinks "$bundle" || return 1
  codesign --verify --deep --strict --verbose=2 "$bundle" || return 1
  # Deep verification alone does not prove that a copied library was added
  # to the resource seal. Check the exact entry audited in v0.5.12.
  python3 - "$bundle" << 'PY'
import pathlib, plistlib, sys
bundle = pathlib.Path(sys.argv[1])
seal = plistlib.loads((bundle / 'Contents/_CodeSignature/CodeResources').read_bytes())
if not any('MacOS/libdufs.dylib' in seal.get(section, {}) for section in ('files', 'files2')):
    raise SystemExit('ERROR: libdufs.dylib is not sealed in the app signature')
PY
}

verify_macho_architectures "$STAGED_APP"
verify_framework_symlinks "$STAGED_APP"

# Flutter signed the original app before this library was copied in. Sign
# the new code first, then refresh the outer app's seal with Release
# entitlements. Existing nested framework signatures are retained.
echo "Signing staged dufs library and app with ad-hoc identity..."
codesign --force --sign - --timestamp=none "${APP_CONTENTS}/libdufs.dylib"
codesign --force --sign - --timestamp=none \
  --entitlements "${SCRIPT_DIR}/../macos/Runner/Release.entitlements" "$STAGED_APP"
verify_signed_bundle "$STAGED_APP"

echo "App contents:"
ls -la "${APP_CONTENTS}/"

# Create DMG-like zip while preserving versioned-framework symlinks.
echo "Creating zip archive..."
(cd "${OUTPUT_DIR}" && zip -r -y "${ARCHIVE_NAME}.zip" "${APP_NAME}.app")

# Validate the artifact after a real ZIP round trip, including its signatures
# and framework symlinks. Only our unique verification directory is removed.
VERIFY_DIR="$(mktemp -d "${TMPDIR:-/tmp}/fileinfra-macos-zip.XXXXXX")"
trap 'rm -rf "$VERIFY_DIR"' EXIT
if ! unzip -q "$ARCHIVE_PATH" -d "$VERIFY_DIR" || ! verify_signed_bundle "${VERIFY_DIR}/${APP_NAME}.app"; then
  rm -f "$ARCHIVE_PATH"
  exit 1
fi
rm -rf "$VERIFY_DIR"
trap - EXIT

echo "Created and verified: ${ARCHIVE_PATH}"
ls -la "$ARCHIVE_PATH"
