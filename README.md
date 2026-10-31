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
[![F-Droid](https://img.shields.io/badge/F-Droid-pending-blue)](https://gitlab.com/fdroid/fdroiddata)

[中文文档](./README_zh.md) · [Privacy Policy](./PRIVACY.md) · [📥 Releases](https://github.com/zocs/fileinfra/releases)

</div>

---

A Dufs-based, lightweight cross-platform file distribution GUI optimized for **air-gapped LANs and restricted industrial environments**. Built on [dufs](https://github.com/sigoden/dufs). **Zero config, zero barrier** — share a folder or a single file from one device, and anyone with a browser can access and transfer it. The other side needs no app.

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
| 🔐 **Secure** | Optional password auth, CORS control |
| 🔀 **Fine-grained permissions** | Upload, delete, search, archive download — toggle each one |
| 🎨 **Customizable** | 6 color schemes + custom color wheel + dark / light mode |
| 🌐 **Multilingual** | 简体中文 · 繁體中文 · English |
| 📦 **Zero setup** | Self-contained — no external dependencies |

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
| 🪟 **Windows** | `fileinfra-*-windows-x64-setup.exe` (installer) or `.zip` (portable) | ✅ Tested |
| 🤖 **Android** | `fileinfra-*-android-universal.apk` (arm64-v8a · armeabi-v7a · x86_64) | ✅ Tested |
| 🐧 **Linux x64** | `.AppImage` (zero deps) or `.deb` | ✅ Tested |
| 🐧 **Linux ARM64** | `.AppImage` or `.deb` (Kylin/UOS compatible) | ✅ Tested |
| 🍎 **macOS** | `FileInfra-*-macos-arm64.zip` | ⚠️ Untested |

> 📥 [Download latest release](https://github.com/zocs/fileinfra/releases)
>
> 🤖 Also available on [F-Droid](https://f-droid.org/) (pending review)

### Steps

1. Pick a folder or a single file
2. Tap "Start Server"
3. Scan QR code or enter URL in browser (port required)
4. Share files — done!

While the server is running, open the separate **Tools** URL in the app to use the LAN clipboard and offline QR generator. The clipboard endpoint uses the file-server port + 2000 (for example, file server `5000` → tools `7000`; it may move up if that port is unavailable). On Android, notification actions can send the device clipboard to the shared page or pull shared text back to the device; a Quick Settings tile can start or stop the last configured share.

> Clipboard content is shared with anyone who can reach the tools URL on your network. Do not put passwords, tokens, or other sensitive information on it.

---

## 🌐 Network

> **Simplest setup:** All devices on the same WiFi or hotspot.

| Environment | |
|:---|:---:|
| 🏠 **Same WiFi** | Just connect and share |
| 📱 **Phone hotspot** | One device creates a hotspot, others join — no router needed |
| 🌍 **Remote access** | Works with ZeroTier, Tailscale, EasyTier, or any VPN |

> 🔒 **All transfers happen directly between your devices. No data passes through third-party servers.**

---

## 🔒 Security

> ⚠️ The file server and tools page are reachable on the network interfaces they bind to (the file server listens on `0.0.0.0` by default).

| Network | Recommendation |
|:---|:---:|
| Home WiFi | ✅ Safe — LAN only |
| Public WiFi | ⚠️ Enable password auth |
| Corporate network | ⚠️ Watch firewall policies |
| Public internet | ❌ Not recommended — use VPN instead |

**Best practices:**
1. Enable password authentication on untrusted networks; configure upload/delete permissions conservatively.
2. Remember that file-server authentication does not protect the separate clipboard/tools page.
3. Stop the server when done and review access logs periodically.

---

## 🔧 Troubleshooting

### Android — Storage Permission

**Symptom:** Can't list files, "Need all files access permission"

**Fix:** Settings → Apps → FileInfra → Permissions → Allow "All files access"

### Android — Notification Clipboard Buttons

The notification's "Send clipboard" button reads the system clipboard, which is **only readable by the foreground app on Android 10+** (background reads silently return empty). If the Tools page doesn't update after tapping "Send", bring FileInfra to the foreground and retry. "Pull clipboard" (writing to the system clipboard) is not affected (Android 10+ shows a clipboard-access toast).

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

### macOS — Developer Verification Blocked

**Symptom:** "Can't verify developer" on open

**Fix:**
```bash
xattr -d com.apple.quarantine FileInfra.app
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
A: Not yet. Planned for a future release.

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
- Windows: VS Build Tools 2022 (C++ workload)
- Android: Android SDK, NDK
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
flutter build windows --release
flutter build apk --release
```

### Packaging Scripts

```bash
# Linux (x64 or ARM64)
bash scripts/build_linux.sh x86_64
bash scripts/build_linux.sh aarch64

# macOS (ARM64)
bash scripts/build_macos.sh aarch64
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

GitHub Actions builds all platforms on tag push (`v*`) and creates a release automatically.

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
    └── dufs_ffi.dart               # FFI bindings (desktop)
scripts/
├── build_dufs.sh                   # Cross-compile dufs (7 platforms)
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
