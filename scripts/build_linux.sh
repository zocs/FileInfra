#!/bin/bash
# build_linux.sh - Build and package FileInfra for Linux
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ARCH=${1:-x86_64}
case "$ARCH" in
  x86_64) DUFS_PLATFORM=linux-x86_64; DEB_ARCH=amd64; FLUTTER_ARCH=x64 ;;
  aarch64) DUFS_PLATFORM=linux-arm64; DEB_ARCH=arm64; FLUTTER_ARCH=arm64 ;;
  *) echo "ERROR: Unsupported Linux architecture: ${ARCH} (use x86_64 or aarch64)" >&2; exit 1 ;;
esac
VERSION=$(grep '^version:' pubspec.yaml | head -1 | awk '{print $2}' | awk -F'+' '{print $1}')
APP_NAME="fileinfra"
BUILD_ROOT="${FILEINFRA_BUILD_ROOT:-build}"
OUTPUT_DIR="${FILEINFRA_OUTPUT_DIR:-${BUILD_ROOT}/linux/output}"

# 可选产物后缀：兼容构建（老 glibc 环境）传 -compat，避免与常规产物重名
ARCHIVE_SUFFIX="${FILEINFRA_ARCHIVE_SUFFIX:-}"

ARCHIVE_NAME="${APP_NAME}-${VERSION}${ARCHIVE_SUFFIX}-linux-${ARCH}"

echo "Building FileInfra ${VERSION} for Linux ${ARCH}..."

# Always refresh the native core from the pinned source before packaging.
# build_dufs.sh reuses Cargo's cache and inherits DUFS_NO_DEFAULT_FEATURES.
echo "Compiling dufs shared library for ${DUFS_PLATFORM}..."
bash "${SCRIPT_DIR}/build_dufs.sh" "$DUFS_PLATFORM"

# Build Flutter Linux
flutter build linux --release

# Flutter outputs to build/linux/{x64|arm64}/release/bundle
BUILD_DIR="${BUILD_ROOT}/linux/${FLUTTER_ARCH}/release/bundle"
mkdir -p "$OUTPUT_DIR"

# Copy build output for packaging
PKG_DIR="${OUTPUT_DIR}/${APP_NAME}"
rm -rf "$PKG_DIR"
cp -a "$BUILD_DIR" "$PKG_DIR"
PKG_DIR="$(cd "$PKG_DIR" && pwd)"

# Include dufs shared library in the bundle
cp "assets/dufs/libdufs-linux-${ARCH}.so" "${PKG_DIR}/libdufs.so"

# Derive the native dependency floor from every shipped ELF, including plugins
# and native Flutter assets. Build host glibc alone understates plugin imports.
if ! command -v objdump > /dev/null; then
  echo "ERROR: objdump (binutils) is required to inspect Linux runtime dependencies" >&2
  exit 1
fi
NATIVE_SYMBOLS=$(find "$PKG_DIR" -type f -exec objdump -T {} + 2>/dev/null | awk '/\*UND\*/' || true)
GLIBC_MIN=$(printf '%s\n' "$NATIVE_SYMBOLS" | sed -nE 's/.*[ (]GLIBC_([0-9]+(\.[0-9]+)+)[ )].*/\1/p' | sort -Vu | tail -n 1)
GLIBCXX_MAX=$(printf '%s\n' "$NATIVE_SYMBOLS" | sed -nE 's/.*[ (]GLIBCXX_([0-9]+(\.[0-9]+)+)[ )].*/\1/p' | sort -Vu | tail -n 1)
CXXABI_MAX=$(printf '%s\n' "$NATIVE_SYMBOLS" | sed -nE 's/.*[ (]CXXABI_([0-9]+(\.[0-9]+)+)[ )].*/\1/p' | sort -Vu | tail -n 1)
if [ -z "$GLIBC_MIN" ]; then
  echo "ERROR: Could not determine the shipped ELF glibc requirement" >&2
  exit 1
fi
if [[ "$ARCHIVE_SUFFIX" == *-compat* ]] && [[ "$(printf '%s\n' 2.27 "$GLIBC_MIN" | sort -V | tail -n 1)" != 2.27 ]]; then
  echo "ERROR: compat bundle requires glibc ${GLIBC_MIN}; maximum supported requirement is 2.27" >&2
  exit 1
fi

# GCC's published ABI version table maps symbol versions to the oldest
# libstdc++6 package that supplies them. Fail on new, unmapped ABIs rather
# than silently publishing an understated dependency.
# https://gcc.gnu.org/onlinedocs/libstdc++/manual/abi.html
LIBSTDCXX_GLIBCXX_MIN=""
case "$GLIBCXX_MAX" in
  "") ;;
  3.4|3.4.[1-3]) LIBSTDCXX_GLIBCXX_MIN=3.4 ;;
  3.4.4) LIBSTDCXX_GLIBCXX_MIN=4.0 ;;
  3.4.5) LIBSTDCXX_GLIBCXX_MIN=4.0.1 ;;
  3.4.6) LIBSTDCXX_GLIBCXX_MIN=4.0.2 ;;
  3.4.7) LIBSTDCXX_GLIBCXX_MIN=4.0.3 ;;
  3.4.8) LIBSTDCXX_GLIBCXX_MIN=4.1.1 ;;
  3.4.9) LIBSTDCXX_GLIBCXX_MIN=4.2 ;;
  3.4.10) LIBSTDCXX_GLIBCXX_MIN=4.3 ;;
  3.4.11) LIBSTDCXX_GLIBCXX_MIN=4.4 ;;
  3.4.12) LIBSTDCXX_GLIBCXX_MIN=4.4.1 ;;
  3.4.13) LIBSTDCXX_GLIBCXX_MIN=4.4.2 ;;
  3.4.14) LIBSTDCXX_GLIBCXX_MIN=4.5 ;;
  3.4.15) LIBSTDCXX_GLIBCXX_MIN=4.6 ;;
  3.4.16) LIBSTDCXX_GLIBCXX_MIN=4.6.1 ;;
  3.4.17) LIBSTDCXX_GLIBCXX_MIN=4.7 ;;
  3.4.18) LIBSTDCXX_GLIBCXX_MIN=4.8 ;;
  3.4.19) LIBSTDCXX_GLIBCXX_MIN=4.8.3 ;;
  3.4.20) LIBSTDCXX_GLIBCXX_MIN=4.9 ;;
  3.4.21) LIBSTDCXX_GLIBCXX_MIN=5.1 ;;
  3.4.22) LIBSTDCXX_GLIBCXX_MIN=6.1 ;;
  3.4.23) LIBSTDCXX_GLIBCXX_MIN=7.1 ;;
  3.4.24) LIBSTDCXX_GLIBCXX_MIN=7.2 ;;
  3.4.25) LIBSTDCXX_GLIBCXX_MIN=8.1 ;;
  3.4.26) LIBSTDCXX_GLIBCXX_MIN=9.1 ;;
  3.4.27) LIBSTDCXX_GLIBCXX_MIN=9.2 ;;
  3.4.28) LIBSTDCXX_GLIBCXX_MIN=9.3 ;;
  3.4.29) LIBSTDCXX_GLIBCXX_MIN=11.1 ;;
  3.4.30) LIBSTDCXX_GLIBCXX_MIN=12.1 ;;
  3.4.31) LIBSTDCXX_GLIBCXX_MIN=13.1 ;;
  3.4.32) LIBSTDCXX_GLIBCXX_MIN=13.2 ;;
  3.4.33) LIBSTDCXX_GLIBCXX_MIN=14.1 ;;
  3.4.34) LIBSTDCXX_GLIBCXX_MIN=15.1 ;;
  *) echo "ERROR: Unmapped libstdc++ ABI GLIBCXX_${GLIBCXX_MAX}" >&2; exit 1 ;;
esac
LIBSTDCXX_CXXABI_MIN=""
case "$CXXABI_MAX" in
  "") ;;
  1.3) LIBSTDCXX_CXXABI_MIN=3.4 ;;
  1.3.1) LIBSTDCXX_CXXABI_MIN=4.0 ;;
  1.3.2) LIBSTDCXX_CXXABI_MIN=4.3 ;;
  1.3.3) LIBSTDCXX_CXXABI_MIN=4.4 ;;
  1.3.4) LIBSTDCXX_CXXABI_MIN=4.5 ;;
  1.3.5) LIBSTDCXX_CXXABI_MIN=4.6 ;;
  1.3.6) LIBSTDCXX_CXXABI_MIN=4.7 ;;
  1.3.7) LIBSTDCXX_CXXABI_MIN=4.8 ;;
  1.3.8) LIBSTDCXX_CXXABI_MIN=4.9 ;;
  1.3.9) LIBSTDCXX_CXXABI_MIN=5.1 ;;
  1.3.10) LIBSTDCXX_CXXABI_MIN=6.1 ;;
  1.3.11) LIBSTDCXX_CXXABI_MIN=7.1 ;;
  1.3.12) LIBSTDCXX_CXXABI_MIN=9.1 ;;
  1.3.13) LIBSTDCXX_CXXABI_MIN=11.1 ;;
  1.3.14) LIBSTDCXX_CXXABI_MIN=13.1 ;;
  1.3.15) LIBSTDCXX_CXXABI_MIN=14.1 ;;
  1.3.16) LIBSTDCXX_CXXABI_MIN=15.1 ;;
  1.3.17) LIBSTDCXX_CXXABI_MIN=16.1 ;;
  *) echo "ERROR: Unmapped libstdc++ ABI CXXABI_${CXXABI_MAX}" >&2; exit 1 ;;
esac
NATIVE_DEPENDS="libc6 (>= ${GLIBC_MIN})"
LIBSTDCXX_MIN=$(printf '%s\n' "$LIBSTDCXX_GLIBCXX_MIN" "$LIBSTDCXX_CXXABI_MIN" | sort -V | tail -n 1)
if [ -n "$LIBSTDCXX_MIN" ]; then
  NATIVE_DEPENDS="${NATIVE_DEPENDS}, libstdc++6 (>= ${LIBSTDCXX_MIN})"
fi
echo "Native dependencies: ${NATIVE_DEPENDS}"

# ==================== AppImage ====================
echo "Creating AppImage..."
APPDIR="${OUTPUT_DIR}/${APP_NAME}.AppDir"
rm -rf "${APPDIR}"
mkdir -p "${APPDIR}/usr/bin" "${APPDIR}/usr/share/applications" "${APPDIR}/usr/share/icons/hicolor/256x256/apps"

# Copy app files
cp -a "${PKG_DIR}/." "${APPDIR}/usr/bin/"

# Create desktop entry
cat > "${APPDIR}/${APP_NAME}.desktop" << 'DESKTOP'
[Desktop Entry]
Name=FileInfra
Comment=One-tap LAN file sharing via browser
Exec=fileinfra
Icon=fileinfra
Type=Application
Categories=Utility;FileTransfer;
Terminal=false
StartupWMClass=cc.merr.fileinfra
DESKTOP

cp "${APPDIR}/${APP_NAME}.desktop" "${APPDIR}/usr/share/applications/${APP_NAME}.desktop"

# Copy icon
if [ -f "assets/icon/app_icon.png" ]; then
  cp "assets/icon/app_icon.png" "${APPDIR}/fileinfra.png"
  cp "assets/icon/app_icon.png" "${APPDIR}/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
fi

# AppRun
cat > "${APPDIR}/AppRun" << 'APPRUN'
#!/bin/bash
SELF=$(readlink -f "$0")
HERE="${SELF%/*}"
export LD_LIBRARY_PATH="${HERE}/usr/lib:${HERE}/usr/bin/lib:${LD_LIBRARY_PATH}"
exec "${HERE}/usr/bin/fileinfra" "$@"
APPRUN
chmod +x "${APPDIR}/AppRun"

# Download linuxdeploy (better architecture handling than appimagetool)
LINUXDEPLOY_ARCH=$([ "$ARCH" = "aarch64" ] && echo "aarch64" || echo "x86_64")
# 缓存名带 arch 后缀：同一台机器先后编 x86_64/aarch64 时，旧缓存会把
# 另一个架构的 AppImage 塞进产物。上游只有 continuous 通道在维护，
# 无法 pin tag——已知妥协，记录于此。
LINUXDEPLOY_BIN="/tmp/linuxdeploy-${LINUXDEPLOY_ARCH}"
if [ ! -f "$LINUXDEPLOY_BIN" ]; then
  curl -sL "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-${LINUXDEPLOY_ARCH}.AppImage" -o "$LINUXDEPLOY_BIN"
  chmod +x "$LINUXDEPLOY_BIN"
fi

# Use linuxdeploy for AppImage creation
export ARCH=${LINUXDEPLOY_ARCH}
export OUTPUT="${OUTPUT_DIR}/${ARCHIVE_NAME}.AppImage"
export NO_STRIP=true
export APPIMAGE_EXTRACT_AND_RUN=1
"$LINUXDEPLOY_BIN" --appdir "${APPDIR}" --output appimage
echo "Created: ${OUTPUT}"

# ==================== .deb ====================
echo "Creating .deb package..."
DEB_DIR="${OUTPUT_DIR}/${APP_NAME}-deb"
rm -rf "${DEB_DIR}"
mkdir -p "${DEB_DIR}/DEBIAN" "${DEB_DIR}/opt/${APP_NAME}" "${DEB_DIR}/usr/share/applications" "${DEB_DIR}/usr/bin"

# libepoxy loads EGL/GLES with dlopen; ELF imports do not declare these runtimes.
# Keep them explicit so a minimal desktop can launch the installed GUI.
# Control file
cat > "${DEB_DIR}/DEBIAN/control" << CONTROL
Package: ${APP_NAME}
Version: ${VERSION}
Section: utils
Priority: optional
Architecture: ${DEB_ARCH}
Depends: ${NATIVE_DEPENDS}, libgtk-3-0, libglib2.0-0, libsecret-1-0, libayatana-appindicator3-1, libegl1, libgles1, libgles2
Maintainer: zocs <zocs@live.com>
Description: One-tap LAN file sharing via browser
 A Dufs-based, lightweight cross-platform file distribution GUI optimized
 for air-gapped LANs and restricted industrial environments.
CONTROL

# Copy files
cp -a "${PKG_DIR}/." "${DEB_DIR}/opt/${APP_NAME}/"

# Symlink to /usr/bin
cat > "${DEB_DIR}/DEBIAN/postinst" << 'POSTINST'
#!/bin/bash
ln -sf /opt/fileinfra/fileinfra /usr/bin/fileinfra
chmod +x /opt/fileinfra/fileinfra
POSTINST
chmod 755 "${DEB_DIR}/DEBIAN/postinst"

cat > "${DEB_DIR}/DEBIAN/prerm" << 'PRERM'
#!/bin/bash
rm -f /usr/bin/fileinfra
PRERM
chmod 755 "${DEB_DIR}/DEBIAN/prerm"

# Desktop entry
cat > "${DEB_DIR}/usr/share/applications/${APP_NAME}.desktop" << 'DESKTOP'
[Desktop Entry]
Name=FileInfra
Comment=One-tap LAN file sharing via browser
Exec=/opt/fileinfra/fileinfra
Icon=fileinfra
Type=Application
Categories=Utility;FileTransfer;
Terminal=false
StartupWMClass=cc.merr.fileinfra
DESKTOP

if [ -f "assets/icon/app_icon.png" ]; then
  mkdir -p "${DEB_DIR}/usr/share/icons/hicolor/256x256/apps"
  cp "assets/icon/app_icon.png" "${DEB_DIR}/usr/share/icons/hicolor/256x256/apps/${APP_NAME}.png"
fi

dpkg-deb --root-owner-group --build "${DEB_DIR}" "${OUTPUT_DIR}/${ARCHIVE_NAME}.deb"
echo "Created: ${OUTPUT_DIR}/${ARCHIVE_NAME}.deb"

# ==================== .rpm ====================
echo "Creating .rpm package..."
if command -v rpmbuild &> /dev/null; then
  RPM_DIR="${OUTPUT_DIR}/rpm-build"
  mkdir -p "${RPM_DIR}/BUILD" "${RPM_DIR}/RPMS" "${RPM_DIR}/SOURCES" "${RPM_DIR}/SPECS" "${RPM_DIR}/SRPMS"

  cat > "${RPM_DIR}/SPECS/${APP_NAME}.spec" << SPEC
Name: ${APP_NAME}
Version: ${VERSION}
Release: 1
Summary: One-tap LAN file sharing via browser
License: MIT
Requires: gtk3 glib2 libEGL.so.1()(64bit) libGLESv1_CM.so.1()(64bit) libGLESv2.so.2()(64bit)

%description
A Dufs-based, lightweight cross-platform file distribution GUI optimized
for air-gapped LANs and restricted industrial environments.

%install
mkdir -p %{buildroot}/opt/${APP_NAME}
cp -a "${PKG_DIR}/." "%{buildroot}/opt/${APP_NAME}/"
mkdir -p %{buildroot}/usr/bin
ln -sf /opt/${APP_NAME}/${APP_NAME} %{buildroot}/usr/bin/${APP_NAME}

%files
/opt/${APP_NAME}/*
/usr/bin/${APP_NAME}
SPEC

  # _topdir 必须是绝对路径：rpmbuild 对相对值按 / 解析，
  # 历史上因此一直找不到 BUILDROOT（v0.5.0 起 .rpm 就没产出过）
  RPM_DIR="$(cd "${RPM_DIR}" && pwd)"
  if rpmbuild -bb --define "_topdir ${RPM_DIR}" --define "_builddir ${RPM_DIR}/BUILD" "${RPM_DIR}/SPECS/${APP_NAME}.spec" > "${RPM_DIR}/build.log" 2>&1; then
    cat "${RPM_DIR}/build.log"
  else
    cat "${RPM_DIR}/build.log"
    # 失败不再静默：CI 上至少留 ::warning:: 痕迹（产物少一个 .rpm）
    if [ -n "${GITHUB_ACTIONS:-}" ]; then
      echo "::warning::RPM build failed, continuing without the .rpm artifact"
    else
      echo "WARNING: RPM build failed, continuing without the .rpm artifact" >&2
    fi
  fi
  # Copy RPM if created
  RPM_FILE=$(find "${RPM_DIR}/RPMS" -name "*.rpm" 2>/dev/null | head -1)
  if [ -n "$RPM_FILE" ]; then
    cp "$RPM_FILE" "${OUTPUT_DIR}/${ARCHIVE_NAME}.rpm"
    echo "Created: ${OUTPUT_DIR}/${ARCHIVE_NAME}.rpm"
  else
    echo "RPM not created, skipping"
  fi
  # 构建树不能留在 output 里：artifact 上传用 output/*，rpm-build/RPMS
  # 下的原始 rpm 会被 release 的 **/*.rpm glob 再捞一遍（v0.5.1 踩过）
  rm -rf "${RPM_DIR}"
else
  echo "rpmbuild not found, skipping .rpm"
fi

# ==================== .tar.gz (for Arch/AUR) ====================
echo "Creating .tar.gz..."
tar -czf "${OUTPUT_DIR}/${ARCHIVE_NAME}.tar.gz" -C "${OUTPUT_DIR}" "${APP_NAME}"
echo "Created: ${OUTPUT_DIR}/${ARCHIVE_NAME}.tar.gz"

echo ""
echo "Build complete! Output files:"
ls -la "${OUTPUT_DIR}/"*.AppImage "${OUTPUT_DIR}/"*.deb "${OUTPUT_DIR}/"*.tar.gz 2>/dev/null || true
ls -la "${OUTPUT_DIR}/"*.rpm 2>/dev/null || true
