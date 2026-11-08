<div align="center">

<h1><img src="fastlane/metadata/android/en-US/icon.png" width="48" align="absmiddle"> FileInfra</h1>

**File sharing made easy.** — 让文件分发更轻松。

<sub>formerly known as <b>DufsHub</b> · 曾用名 DufsHub</sub>

[![Release](https://img.shields.io/github/v/release/zocs/fileinfra)](https://github.com/zocs/fileinfra/releases)
[![License](https://img.shields.io/github/license/zocs/fileinfra)](LICENSE)
[![Downloads](https://img.shields.io/github/downloads/zocs/fileinfra/total)](https://github.com/zocs/fileinfra/releases)
[![Flutter](https://img.shields.io/badge/Flutter-3.47+-blue)](https://flutter.dev)
[![Windows](https://img.shields.io/badge/Windows-green)](https://github.com/zocs/fileinfra/releases)
[![Android](https://img.shields.io/badge/Android-green)](https://github.com/zocs/fileinfra/releases)
[![Linux](https://img.shields.io/badge/Linux-green)](https://github.com/zocs/fileinfra/releases)
[![macOS](https://img.shields.io/badge/macOS-yellow)](https://github.com/zocs/fileinfra/releases)
[![Build](https://img.shields.io/github/actions/workflow/status/zocs/fileinfra/build.yml?label=build)](https://github.com/zocs/fileinfra/actions)
[![F-Droid](https://img.shields.io/badge/F-Droid-preparation-grey)](./.fdroid.yml)

[中文文档](./README_zh.md) · [Privacy Policy](./PRIVACY.md) · [📥 Releases](https://github.com/zocs/fileinfra/releases)

</div>

---

A Dufs-based, lightweight cross-platform file distribution GUI optimized for **air-gapped LANs and restricted industrial environments**. Built on [dufs](https://github.com/sigoden/dufs). **Zero config, zero barrier** — share a folder or a single file from one device, and anyone with a browser can access and transfer it. The other side needs no app.

Latest release: [v0.5.13](https://github.com/zocs/FileInfra/releases/tag/v0.5.13) updates the file-server core, fixes clipboard and Android lifecycle behavior, and improves desktop packaging. All required [release build and verification jobs](https://github.com/zocs/FileInfra/actions/runs/42531076830) passed.

---

## 📱 Screenshots

[![Screenshots](fastlane/metadata/android/en-US/phoneScreenshots/screenshots_overview.jpg)](fastlane/metadata/android/en-US/phoneScreenshots/screenshots_overview.jpg)

---

## ✨ Why FileInfra?

> **The other side doesn't need an app.** Install FileInfra on ONE device, start the server, and anyone with a browser can upload and download files.

| Feature | |
|:---|:---:|
| 📱 **One device is enough** | The rest use a browser |
| 📄 **Folder or single file** | Share a full directory or just one file |
| ⬆️⬇️ **Bidirectional** | Upload AND download, not just send |
| 🔗 **Just open a link** | QR code or URL — that's all the other side needs |
| 📋 **Shared clipboard & tools page** | Sync text with browsers on the LAN and generate QR codes offline |
| 📲 **Android quick controls** | Control the running server from the notification or Quick Settings tile |
| 🔐 **File access controls** | Optional password auth and configurable permissions |
| 🔀 **Fine-grained permissions** | Upload, delete, search, archive download — toggle each one |
| 🎨 **Customizable** | 6 color schemes + custom color wheel + dark / light mode |
| 🌐 **Multilingual** | 简体中文 · 繁體中文 · English |
| 📦 **Bundled file server** | No separate dufs installation; Linux needs desktop runtime libraries |

---

## 💡 Use Cases

| Scenario | How |
|:---|:---:|
| 🏭 **Factory / industrial offline transfer** | One PC starts → operators scan → distribute firmware / logs / docs |
| 🏠 **Home file sharing** | Phone hotspot → browser access → transfer photos / docs |
| 💼 **Office quick transfer** | One PC starts → colleagues scan → share project files |
| 🎓 **Classroom distribution** | Teacher starts → students scan → download courseware |
| 🔧 **Device debugging** | Embedded device → phone hotspot → download logs |
| 📷 **Photo dump** | Camera/phone starts → PC bulk downloads |

---

## 🚀 Quick Start

### Download

| Platform | File | |
|:---|:---|:---:|
| 🪟 **Windows x64** | `fileinfra-*-windows-x64-setup.exe` (installer) or `.zip` (portable) | Windows 10+; bundled VC++ runtime |
| 🤖 **Android** | `fileinfra-*-android-universal.apk` or `-android-arm64.apk`, `-android-armv7.apk`, `-android-x86_64.apk` | Android 7.0+ (API 24) |
| 🐧 **Linux x64** | `.AppImage`, `.deb`, or `.tar.gz`; choose `-compat` for older distributions | Desktop runtime libraries required |
| 🐧 **Linux ARM64** | `.AppImage`, `.deb`, or `.tar.gz` | Distribution/device validation varies |
| 🍎 **macOS (Apple Silicon)** | `FileInfra-*-macos-arm64.zip` | macOS 13+; device testing pending |
| 🍎 **macOS (Intel)** | `FileInfra-*-macos-x64.zip` | macOS 13+; device testing pending |

> 📥 [Download latest release](https://github.com/zocs/fileinfra/releases)

For Android updates, keep the same APK variant you previously installed. Flutter assigns higher version codes to per-ABI APKs: v0.5.13 uses `58` for universal and `2058` for arm64 (previous arm64: `2057`). Switching from a per-ABI APK to universal can be rejected as a version downgrade even when the signing certificate matches.
>
> F-Droid metadata and an unsigned build path are prepared. Submission is postponed; FileInfra is not currently available in the F-Droid catalog.

Windows packages contain the x64 GUI. The current Flutter SDK has no Windows 32-bit x86 target. Linux packages declare their actual glibc/libstdc++ requirements in the `.deb`; the x64 compat build targets glibc 2.27+ and libstdc++ 5.1+. AppImage does not remove these system requirements. Kylin/UOS compatibility depends on the distribution version and desktop libraries. macOS packages use ad-hoc signatures and are not notarized or signed with a Developer ID. iOS ZIPs are experimental unsigned build artifacts; installation and file-server operation have not been verified.

### Steps

1. Pick a folder or a single file
2. Tap "Start Server"
3. Scan QR code or enter URL in browser (port required)
4. Share files — done!

While the server is running, open the separate **Tools** URL in the app to use the LAN clipboard and offline QR generator. The clipboard endpoint starts at the file-server port + 2000 (for example, file server `5000` → tools `7000`; it may move if that port is unavailable or unsafe for browsers). On Android, **Send clipboard** opens and focuses FileInfra before reading the device clipboard once; **Pull clipboard** writes shared text to the device. A Quick Settings tile can start or stop the last successfully started share, using its saved settings. A tile start runs the native file server; open FileInfra to restore its tools listener.

> Clipboard content is shared with anyone who can reach the tools URL on your network. Do not put passwords, tokens, or other sensitive information on it.

---

## 🌐 Network

> **Simplest setup:** All devices on the same WiFi or hotspot.

| Environment | |
|:---|:---:|
| 🏠 **Same WiFi** | Just connect and share |
| 📱 **Phone hotspot** | One device creates a hotspot, others join — no router needed |
| 🌍 **Remote access** | Works with ZeroTier, Tailscale, EasyTier, or any VPN |

> All transfers happen directly between your devices. FileInfra does not send files or clipboard text to third-party services. The app currently serves HTTP, so file and clipboard contents are unencrypted unless your network/VPN supplies encryption.

---

## 🔒 Security

> ⚠️ Both the file server and tools page listen on all IPv4 interfaces (`0.0.0.0`), including Wi-Fi, hotspot and VPN interfaces. The app does not currently provide a setting to restrict the bind address.

| Network | Recommendation |
|:---|:---:|
| Home WiFi | Use only with peers you trust |
| Public WiFi | Use a trusted VPN; file passwords do not protect the tools page |
| Corporate network | ⚠️ Watch firewall policies |
| Public internet | ❌ Not recommended — use VPN instead |

**Best practices:**
1. Enable password authentication on untrusted networks; configure upload/delete permissions conservatively.
2. File-server authentication does not protect the separate clipboard/tools page. Its browser Origin checks prevent unrelated websites from using the API, but do not authenticate devices or native clients.
3. Stop the server when done and review access logs periodically.

---

## 🔧 Troubleshooting

### Android — Storage Permission

**Symptom:** Can't list files, "Need all files access permission"

**Fix:** Settings → Apps → FileInfra → Permissions → Allow "All files access"

### Android — Notification Clipboard Buttons

The notification's **Send clipboard** action opens FileInfra and waits for window focus before reading the system clipboard. This supports Android 10+ foreground clipboard restrictions. Unlock the device if needed. **Pull clipboard** writes shared text and does not need a background read. Clipboard controls can be disabled in settings; after a tile-only start, open the app to initialize the tools page.

### Port in Use

**Symptom:** Start fails, "Port XXX already in use"

**Fix:** Change port (try 8080–9000 range) or kill the occupying process

### Linux — AppImage Won't Launch

**Symptom:** Double-click does nothing

**Fix:**
```bash
chmod +x fileinfra-*.AppImage
./fileinfra-*.AppImage
```

Install the FUSE runtime required by your distribution, or use the AppImage's `--appimage-extract-and-run` option. AppImage and tar bundles also need a working graphics driver and EGL/GLES runtime libraries; on Debian/Ubuntu, install `libegl1 libgles1 libgles2` if they are missing. The deb declares these dependencies. If the error mentions `GLIBC_*` or `GLIBCXX_*`, use the x64 compat package or a newer distribution; installing FUSE cannot fix an incompatible system C library.

### macOS — Developer Verification Blocked

**Symptom:** "Can't verify developer" on open

**Fix:**
```bash
xattr -cr FileInfra.app
```

### Windows — Firewall Blocking

**Symptom:** Other devices can't connect

**Fix:** Allow FileInfra through Windows Firewall (you'll be prompted on first launch)

---

## ❓ FAQ

**Q: Does the other side need FileInfra?**
A: No! Only one device runs FileInfra. Others just open a browser.

**Q: Can I share a single file instead of a whole folder?**
A: Yes. Choose a single file and FileInfra will expose just that file through the browser.

**Q: Can I access it remotely?**
A: LAN by default. For remote access, use ZeroTier / Tailscale / EasyTier.

**Q: Is HTTPS supported?**
A: The dufs command-line server supports TLS. FileInfra's file server and tools page currently use HTTP and have no HTTPS setting.

**Q: Max file size?**
A: No hard limit. Tested with a single 70GB+ archive over gigabit LAN — sustained full bandwidth throughout. Large downloads may have a brief delay while loading file info, which is normal. Actual speed depends on filesystem, disk I/O, and Wi-Fi throughput.

**Q: How many devices can connect at once?**
A: No hard limit — depends on bandwidth and device performance.

**Q: Are files uploaded to the cloud?**
A: No! Everything stays local. Transfers are device-to-device.

---

## 🛠️ Development

### Requirements

- Flutter SDK 3.47.0 (the CI build version)
- Rust 1.99.1 (pinned in CI and F-Droid preparation)
- Windows: VS Build Tools 2022 (C++ workload)
- Android: JDK 17, Android SDK and NDK (CI expects r29)
- Linux: clang, lld, llvm, libgtk-3-dev
- macOS: Xcode

### Build

```bash
git clone https://github.com/zocs/fileinfra.git
cd fileinfra
flutter pub get

# Run (debug)
flutter run -d windows
flutter run -d android

# Build
bash scripts/build_dufs.sh windows-x86_64
flutter build windows --release
# Android: build all native ABIs before building a universal APK.
bash scripts/build_dufs.sh android-arm64
bash scripts/build_dufs.sh android-arm
bash scripts/build_dufs.sh android-x86_64
flutter build apk --release
```

Android release builds require the existing signing key via `KEYSTORE_FILE`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, and `KEY_PASSWORD`. The historical key alias defaults to `inout`; it is a keystore identifier, not the application name. For an intentionally unsigned local/F-Droid preparation build, set `FILEINFRA_UNSIGNED_RELEASE=1`. GitHub release APKs are checked against the existing signing certificate.

### Packaging Scripts

```bash
# Linux (x64 or ARM64)
bash scripts/build_linux.sh x86_64
bash scripts/build_linux.sh aarch64

# macOS (Apple Silicon arm64 or Intel x64)
bash scripts/build_macos.sh aarch64
bash scripts/build_macos.sh x86_64
```

Output: AppImage, deb, rpm, tar.gz (Linux) and zip (macOS).

### Local Docker Builds

```bash
# Android release APK (optionally pass signing env vars)
bash scripts/docker_build_android.sh

# Linux x64 packages
bash scripts/docker_build_linux.sh x86_64
```

Notes:
- The Docker workflow currently supports Android and Linux x64 only.
- Windows Docker packaging can be explored later.
- macOS and iOS remain GitHub Actions-only because they require native Apple toolchains.
- The Android Docker image generates `android/local.properties` inside the container so host SDK paths are not required.
- Outputs land under `docker_build/`: `docker_build/android/outputs/apk/` (APKs) and `docker_build/linux/x86_64/outputs/packages/` (AppImage/deb/tar.gz).

### CI/CD

GitHub Actions runs analysis, Flutter/browser regressions, native Android tests, packaging checks and builds on manual dispatch or a tag push. It also checks packaged Windows startup/native runtimes and actual deb/AppImage windows in a fresh Ubuntu 18.04 desktop. Release tags (`v*`) publish only after all required jobs pass. Verify the branch first with `gh workflow run build.yml --ref <branch> -f note="<purpose>"`; release downloads include SHA-256 checksums. See [RELEASE_CHECKLIST.md](./RELEASE_CHECKLIST.md) for the sequence and actual release verification record.

### Project Structure

```
lib/
├── main.dart                       # Entry + window init
├── app.dart                        # MaterialApp + theming
├── constants.dart                  # Reverse-domain + MethodChannel constants
├── l10n/app_localizations.dart     # i18n (zh/en/zhTW)
├── models/
│   ├── server_config.dart          # Config model + persistence
│   └── transfer_log.dart           # Transfer log parser
├── pages/
│   ├── home_page.dart              # Home: dir / perms / start / QR (multi-address default + per-address QR)
│   ├── settings_page.dart          # Settings: theme / color (incl. custom picker) / language
│   ├── setup_wizard_page.dart      # First-run wizard
│   └── log_page.dart               # Transfer log viewer
├── widgets/
│   └── color_picker_dialog.dart    # Hand-rolled HSV color wheel (no deps)
└── services/
    ├── dufs_service.dart           # dufs lifecycle (platform dispatch)
    ├── clipboard_service.dart      # LAN clipboard, tools page and QR endpoints
    └── dufs_ffi.dart               # FFI bindings (desktop)
scripts/
├── build_dufs.sh                   # Compile pinned fork source for each target/ABI
├── build_linux.sh                  # Linux packaging (AppImage/deb)
├── build_macos.sh                  # macOS packaging
└── dufs-ffi/lib.rs                 # Rust FFI wrapper
android/app/src/main/kotlin/.../DufsForegroundService.kt  # Android native service
installer/fileinfra.nsi               # Windows NSIS installer
```

Desktop builds embed `dufs` through Rust FFI; Android uses a foreground native service to survive Activity recreation on lower-memory devices.

---

## 🙏 Acknowledgments

FileInfra is built on top of [dufs](https://github.com/sigoden/dufs) — a brilliant utility file server by [sigoden](https://github.com/sigoden). Without dufs, FileInfra wouldn't exist. Thanks for making file sharing so simple.

---

## 📄 License

[MIT](LICENSE) © 2026 [zocs](https://github.com/zocs)

---

<div align="center">

**FileInfra** — file sharing made easy.

</div>
