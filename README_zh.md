<div align="center">

<h1><img src="fastlane/metadata/android/en-US/icon.png" width="48" align="absmiddle"> FileInfra</h1>

**让文件分发更轻松。** — 局域网/工业离线场景下的轻量文件快速分发工具。

<sub>曾用名 <b>DufsHub</b>（2026-08 更名）</sub>

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

[English](./README.md) · [隐私政策](./PRIVACY.md) · [📥 下载](https://github.com/zocs/fileinfra/releases)

</div>

---

基于 [dufs](https://github.com/sigoden/dufs) 的图形分发工具，专为**气密局域网 / 工业离线环境**优化。**零配置，零参数**——仅需在一台设备安装 FileInfra，分享一个文件夹或单个文件，其他设备打开浏览器访问分享页即可轻松上传下载。

最新版本 [v0.5.13](https://github.com/zocs/FileInfra/releases/tag/v0.5.13)：更新文件服务核心，修复剪贴板与 Android 启停/恢复，完善桌面打包。[发布构建与验证任务](https://github.com/zocs/FileInfra/actions/runs/42531076830) 已全部通过。

---

## 📱 截图

[![Screenshots](fastlane/metadata/android/en-US/phoneScreenshots/screenshots_overview.jpg)](fastlane/metadata/android/en-US/phoneScreenshots/screenshots_overview.jpg)

---

## ✨ 为什么用 FileInfra？

> **另一端不用额外安装任何东西** — 只需一台设备装 FileInfra，启动服务，其他人打开浏览器就可上传下载文件。

| 特性 | |
|:---|:---:|
| 📱 **一端安装就够** | 其他端只需浏览器 |
| 📄 **目录或单文件** | 整个文件夹或单个文件都能直接分享 |
| ⬆️⬇️ **能传能收** | 不只是发送，上传下载都行 |
| 🔗 **打开就用** | 扫码或输入地址，对端零门槛 |
| 📋 **共享剪贴板与工具页** | 和局域网浏览器实时同步文本，并离线生成二维码 |
| 📲 **Android 快捷控制** | 可从通知栏或快捷设置磁贴启停服务 |
| 🔐 **文件访问控制** | 可选密码认证、可配置操作权限 |
| 🔀 **权限细粒度** | 上传、删除、搜索、归档下载，逐项开关 |
| 🎨 **自由配色** | 6 种预设 + 自定义色盘（任意颜色）+ 深色/浅色模式 |
| 🌐 **三语支持** | 简体中文 · 繁體中文 · English |
| 📦 **内置文件服务** | 无需单独安装 dufs；Linux 需要桌面运行库 |

---

## 💡 能干什么？（主要为局域网应用）

| 场景 | 怎么用 |
|:---|:---:|
| 🏭 **工厂 / 工业离线分发** | 一台 PC 启动 → 操作员扫码 → 分发固件/日志/资料 |
| 🏠 **家里传文件** | 手机连上WiFi → 电脑浏览器访问 → 传照片/文档 |
| 💼 **办公室临时传** | 一台电脑启动 → 同事扫码 → 共享项目文件 |
| 🎓 **课堂发资料** | 老师启动 → 学生扫码 → 下载课件 |
| 🔧 **设备导日志** | 嵌入式设备 → 手机热点 → 拉取日志文件 |
| 📷 **照片批量导出** | 相机/手机启动 → 电脑批量下载 |

---

## 🚀 快速开始

### 下载

| 平台 | 文件 | |
|:---|:---|:---:|
| 🪟 **Windows x64** | `fileinfra-*-windows-x64-setup.exe`（安装版）或 `.zip`（便携版） | Windows 10+；附带 VC++ 运行库 |
| 🤖 **Android** | `-android-universal.apk`，或 `-android-arm64.apk`、`-android-armv7.apk`、`-android-x86_64.apk` | Android 7.0+（API 24） |
| 🐧 **Linux x64** | `.AppImage`、`.deb`、`.tar.gz`；旧发行版选择 `-compat` | 需要桌面运行库 |
| 🐧 **Linux ARM64** | `.AppImage`、`.deb`、`.tar.gz` | 需按发行版与设备验证 |
| 🍎 **macOS（Apple 芯片）** | `FileInfra-*-macos-arm64.zip` | macOS 13+；待实机验证 |
| 🍎 **macOS（Intel）** | `FileInfra-*-macos-x64.zip` | macOS 13+；待实机验证 |

> 📥 [去 Releases 下载最新版](https://github.com/zocs/fileinfra/releases)

Android 更新时请保持之前安装的 APK 类型。Flutter 为分架构 APK 增加版本码偏移：v0.5.13 的 universal 为 `58`，arm64 为 `2058`（旧版 arm64 为 `2057`）。从分架构包切换到 universal，可能因版本码更低而无法覆盖安装，即使签名证书相同。
>
> F-Droid 配方和无签名构建路径已准备，上架已推迟，目前未在 F-Droid 目录提供下载。

Windows 发布包是 x64 图形程序；当前 Flutter SDK 不支持 Windows 32 位 x86 目标。Linux `.deb` 根据实际发布的 ELF 文件声明 glibc/libstdc++ 最低版本，x64 compat 版面向 glibc 2.27+、libstdc++ 5.1+ 环境；AppImage 仍有这些系统要求。麒麟/UOS 是否可运行取决于发行版版本和桌面库。macOS 包使用 ad-hoc 签名，未经过 Developer ID 签名或公证。iOS ZIP 属于实验性无签名构建产物，尚未验证安装和文件服务运行。

### 怎么用

1. 选一个要分享的文件夹或单个文件
2. 点「启动服务」
3. 其他设备扫码或输地址
4. 开传 — 就这么简单！

服务运行后，可在应用中打开独立的「工具页」地址，使用局域网共享剪贴板和离线二维码生成器。工具端口从文件服务端口 + 2000 开始选择（例如 `5000` → `7000`；被占用或属于浏览器禁用端口时会调整）。Android 通知栏「发送剪贴板」会打开并聚焦 FileInfra，再读取一次本机剪贴板；「拉取剪贴板」将共享文本写入本机。快捷设置磁贴按保存的设置启停上次成功启动的文件分享；仅通过磁贴启动时，需要打开 FileInfra 恢复工具页监听。

> 共享剪贴板对能访问工具页地址的设备开放。请勿在其中粘贴密码、令牌等敏感信息。

---

## 🌐 网络要求

> **最简单：** 所有设备连同一个 WiFi 或手机热点就行。

| 网络环境 | |
|:---|:---:|
| 🏠 **同一 WiFi** | 连上就能传 |
| 📱 **手机热点** | 一台开热点，其他设备加入就能用 |
| 🌍 **远程访问** | 搭配 ZeroTier、Tailscale、EasyTier 等组网工具 |

> 文件和剪贴板文本直接传给你连接的设备，FileInfra 不会将它们发送至第三方服务。目前应用使用 HTTP，文件和剪贴板内容不加密；如需加密，应使用可信 VPN 或由网络提供保护。

---

## 🔒 安全提醒

> ⚠️ 文件服务和工具页都监听所有 IPv4 接口（`0.0.0.0`），包括 Wi-Fi、热点和 VPN 接口。目前应用没有限制绑定地址的设置。

| 网络环境 | 建议 |
|:---|:---:|
| 家庭 WiFi | 仅向可信设备开放 |
| 公共 WiFi | 使用可信 VPN；文件密码不能保护工具页 |
| 公司网络 | ⚠️ 留意防火墙策略 |
| 公网暴露 | ❌ 不推荐，远程请用 VPN |

**建议习惯：**
1. 不可信网络务必启用密码认证，并谨慎设置上传/删除权限。
2. 文件密码不保护独立的剪贴板/工具页。工具 API 的浏览器 Origin 检查用于阻止其他网站调用，不是设备或原生客户端身份认证。
3. 用完及时停掉服务，并定期查看访问日志。

---

## 🔧 遇到问题？

### Android — 存储权限

**现象：** 看不到文件，提示"需要开启所有文件访问权限"

**解决：** 设置 → 应用 → FileInfra → 权限 → 开启「所有文件访问」

### Android — 通知栏剪贴板按钮

「发送剪贴板」会打开 FileInfra，等待窗口获得焦点后读取剪贴板，以适应 Android 10+ 的前台读取限制；锁屏时请先解锁。「拉取剪贴板」只写入共享文本，无需后台读取。可在设置中关闭剪贴板按钮；如果文件服务仅通过磁贴启动，请打开应用以初始化工具页。

### 端口被占用

**现象：** 启动失败，提示"端口 XXX 已被占用"

**解决：** 换个端口（8080–9000 随便挑），或者关掉占用那个端口的程序

### Linux — AppImage 双击没反应

**解决：**
```bash
chmod +x fileinfra-*.AppImage
./fileinfra-*.AppImage
```

按发行版安装 FUSE 运行库，或使用 AppImage 的 `--appimage-extract-and-run` 选项。AppImage 和 tar 包还需要可用的图形驱动与 EGL/GLES 运行库；Debian/Ubuntu 缺少这些库时安装 `libegl1 libgles1 libgles2`，deb 已声明对应依赖。若报错包含 `GLIBC_*` 或 `GLIBCXX_*`，请选择 x64 compat 包或更新发行版；安装 FUSE 不能解决系统 C 库版本不兼容。

### macOS — 提示"无法验证开发者"

**解决：**
```bash
xattr -cr FileInfra.app
```

### Windows — 其他设备连不上

**解决：** 允许 FileInfra 通过 Windows 防火墙（首次启动会弹窗提示）

---

## ❓ 常见问题

**Q: 对方要装 FileInfra 吗？**
A: 不用！一台设备装就行，其他人开浏览器就能用。

**Q: 可以只分享单个文件，不分享整个文件夹吗？**
A: 可以。选择一个单文件后，浏览器端只会暴露这个文件本身。

**Q: 能远程访问吗？**
A: 默认只能局域网。远程的话搭配 ZeroTier / Tailscale / EasyTier 之类的 VPN。

**Q: 支持 HTTPS 吗？**
A: dufs 命令行服务支持 TLS。FileInfra 的文件服务和工具页目前都使用 HTTP，尚未提供 HTTPS 设置。

**Q: 最大能传多大的文件？**
A: 理论上没有限制。实测 70GB+ 压缩包单文件在千兆局域网下全程跑满带宽，大文件下载时加载文件信息会有短暂等待，属正常现象。实际速度取决于文件系统、硬盘读写速率和 Wi-Fi 带宽。

**Q: 最多几个设备同时连？**
A: 没有硬限制，主要看网速和设备性能。

**Q: 文件会传到云端吗？**
A: 不会！文件只在设备之间传输，不经过任何服务器。

---

## 🛠️ 开发

### 环境要求

- Flutter SDK 3.47.0（与 CI 构建版本一致）
- Rust 1.99.1（CI 与 F-Droid 准备配方固定版本）
- Windows: VS Build Tools 2022 (C++ workload)
- Android: JDK 17、Android SDK、NDK（CI 预期 r29）
- Linux: clang, lld, llvm, libgtk-3-dev
- macOS: Xcode

### 构建

```bash
git clone https://github.com/zocs/fileinfra.git
cd fileinfra
flutter pub get

# 运行（调试）
flutter run -d windows
flutter run -d android

# 构建
bash scripts/build_dufs.sh windows-x86_64
flutter build windows --release
# Android universal 包需要先编译三个 ABI 的核心。
bash scripts/build_dufs.sh android-arm64
bash scripts/build_dufs.sh android-arm
bash scripts/build_dufs.sh android-x86_64
flutter build apk --release
```

Android 正常 release 构建通过 `KEYSTORE_FILE`、`KEYSTORE_PASSWORD`、`KEY_ALIAS`、`KEY_PASSWORD` 使用现有签名密钥。历史密钥别名默认是 `inout`，这是 keystore 内部标识，与应用名无关。明确需要无签名的本地/F-Droid 准备构建时，设置 `FILEINFRA_UNSIGNED_RELEASE=1`；GitHub release APK 会校验原有签名证书连续性。

### 构建脚本

```bash
# Linux (x64 或 ARM64)
bash scripts/build_linux.sh x86_64
bash scripts/build_linux.sh aarch64

# macOS（Apple 芯片 arm64 或 Intel x64）
bash scripts/build_macos.sh aarch64
bash scripts/build_macos.sh x86_64
```

输出：AppImage, deb, rpm, tar.gz（Linux）和 zip（macOS）。

### CI/CD

GitHub Actions 在手动触发或推送 tag 时运行分析、Flutter/浏览器回归、Android 原生测试、打包检查和各平台构建，也验证 Windows 实际便携启动/原生运行库，以及干净 Ubuntu 18.04 桌面中的实际 deb/AppImage 窗口。发布 tag（`v*`）只有在全部必需任务通过后才创建 release。先用 `gh workflow run build.yml --ref <branch> -f note="<用途>"` 验证分支；下载产物附带 SHA-256 校验文件。流程与实际发布记录见 [RELEASE_CHECKLIST.md](./RELEASE_CHECKLIST.md)。

### 项目结构

```
lib/
├── main.dart                       # 入口 + 窗口初始化
├── app.dart                        # MaterialApp + 主题
├── constants.dart                  # 反向域 + MethodChannel 常量
├── l10n/app_localizations.dart     # 三语国际化
├── models/
│   ├── server_config.dart          # 配置模型 + 持久化
│   └── transfer_log.dart           # 传输日志解析
├── pages/
│   ├── home_page.dart              # 主页：目录/权限/启停/二维码（多地址默认 + 每地址二维码）
│   ├── settings_page.dart          # 设置：主题/配色（含自定义色盘）/语言
│   ├── setup_wizard_page.dart      # 首次启动向导
│   └── log_page.dart               # 传输日志查看
├── widgets/
│   └── color_picker_dialog.dart    # 自绘 HSV 色盘（无依赖）
└── services/
    ├── dufs_service.dart           # dufs 生命周期（平台分发）
    ├── clipboard_service.dart      # 局域网剪贴板、工具页与二维码端点
    └── dufs_ffi.dart               # FFI 绑定（桌面端）
scripts/
├── build_dufs.sh                   # 按目标平台/ABI 编译固定 fork 源码
├── build_linux.sh                  # Linux 打包（AppImage/deb）
├── build_macos.sh                  # macOS 打包
└── dufs-ffi/lib.rs                 # Rust FFI 封装
android/.../DufsForegroundService.kt # Android 原生 Service
installer/fileinfra.nsi               # Windows NSIS 安装包
```

桌面端通过 Rust FFI 内嵌 `dufs`，Android 端通过前台原生 Service 管理文件服务，因此在低内存设备上也能更稳定地跨页面生命周期运行。

---

## 🙏 致谢

FileInfra 基于 [dufs](https://github.com/sigoden/dufs) 构建——[sigoden](https://github.com/sigoden) 写的很好用的文件服务器。没有 dufs 就没有 FileInfra，感谢让文件分享变得这么简单。

---

## 📄 许可证

[MIT](LICENSE) © 2026 [zocs](https://github.com/zocs)

---

<div align="center">

**FileInfra** — 让文件分发更轻松。

</div>
