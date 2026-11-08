# Changelog / 更新日志

> 所有版本均可在 [GitHub Releases](https://github.com/zocs/fileinfra/releases) 下载。
> All versions available at [GitHub Releases](https://github.com/zocs/fileinfra/releases).

## [Unreleased]

## [v0.5.13](https://github.com/zocs/fileinfra/releases/tag/v0.5.13) (2026-11-09)

**中文：**
- ⬆️ 合并 dufs 0.47 与上游后续修复（至 `ec4ea01`），保留旧 WebView/无 JS 页面兼容、归档修复与 FFI 接口；修复 Digest MOVE/COPY 的 nonce 重复校验、HTTP/2 与 HTTP/1 请求目标校验，以及目录 MOVE 的目标子权限检查；无 JS 文件名改用属性转义。
- 🔒 dufs 权限同时约束符号链接路由和真实目标，递归 ZIP/搜索逐项过滤；Digest 容量满时保留有效防重放记录并拒绝不支持的 auth-int；无 JS 表单校验浏览器 Origin。文件范围长度使用 u64，修复 32 位平台超过 4 GiB 的下载头/流长度；下载文件名正确转义引号与反斜杠。
- 🐛 dufs 编辑器正确设置原生只读属性，保存返回 403/500 时保留草稿、光标和焦点；FFI 启动失败清理状态、拒绝空监听配置和未实现的 TLS 参数，显式地址绑定与 CLI 一致。固定来源 `8e8cce6` 与维护 shim 同步。
- 🐛 工具页内联脚本恢复 ES5 语法，发送端收到原样文本确认，空白与末尾换行不再丢失；现代复制 API 失败后尝试旧 API，仍失败时提供可见、完整选中的多行文本供手动复制；重复快照不破坏选择。
- 🔒 剪贴板 HTTP 按 UTF-8 字节流限制 1 MiB，拒绝非法编码及超限 WebSocket 文本；浏览器 API/WS 校验 Origin，停止时隔离旧连接与未完成请求。工具页仍不提供身份认证。
- 🐛 Android 启停、Activity 恢复和通知更新按操作代次隔离；取消等待中的启动后清理工具页、地址及临时 FFI 副本，旧 worker 不再覆盖新进程或错误。通知「发送」聚焦应用后读取一次剪贴板，并验证通知动作的随机令牌。旧日志轮询/准备/截断不再回写新服务；同次服务恢复保留历史和计数。
- 🐛 配置字段类型损坏时逐项使用默认值，保留安全存储认证的优先级与迁移；设置向导完成后同步语言、主题和配色。日志打开路径使用真实文件系统边界检查，拒绝越界或失效符号链接及编码路径遍历。
- ♿ 合入经复核的小屏布局、触控目标、可读对比度、焦点与语义修复；新增实际语言切换与浏览器交互回归。
- 📦 Windows 便携包与安装包附带三个 VC++ 运行库；NSIS 必须显式传入版本。Linux deb 依赖从所有发布 ELF 导出，并显式声明动态加载的 EGL/GLES 库，RPM 同步对应 SONAME；文件归 root，修复图标、窗口标识与重复打包。Linux/macOS 每次打包都编译固定源码，避免旧库复用。AppImage FFI 临时副本使用独立 0700 目录并按所有权清理。
- 🛠 CI 固定 Rust 1.99.1，运行 Flutter/浏览器、Android 原生、脚本与打包回归，校验签名证书和真实 FFI 启停；新 checkout 先由 Flutter 生成 Gradle wrapper 再运行原生测试。证书解析兼容 SDK 37 的签名方案标签，拒绝无效签名/空值/不同证书；Ubuntu 18.04 最小桌面通过 apt 安装实际 deb，再验证 deb 和 AppImage GUI 窗口及持续启动。校验文件使用平铺下载文件名并包含带原生程序的实验性 iOS ZIP。F-Droid 配方增加明确无签名路径，预检固定源码版本/支持/可达性，上架仍推迟。
- ✨ 新增 macOS Intel（x86_64）发布包 `FileInfra-*-macos-x64.zip`，与 Apple 芯片的 `-macos-arm64.zip` 并列。Flutter 的 macOS release 本就是 arm64 + x86_64 通用二进制，此前只有 libdufs.dylib 是 arm64 单架构；现在在同一 Apple 芯片 runner 上交叉编译 x86_64 版 dufs，打包时校验包内每个 Mach-O 都含目标架构。
- 🐛 修复 `scripts/build_macos.sh x86_64` 必然失败的问题（查找 `libdufs-macos-x64.dylib`，而 `build_dufs.sh` 产出的是 `libdufs-macos-x86_64.dylib`）；未知架构参数直接报错，不再静默按 x86_64 构建；重复打包不再把 `.app` 套进旧 bundle。
- 🐛 macOS 版不再启用 App Sandbox：沙盒下 release 包缺少 `network.server` 授权，内嵌 dufs 无法接受局域网连接，重启后也无权访问之前选择的共享目录。⚠️ 沙盒内保存过的设置不会迁移（需重新走一次向导）；仍需在真机上验证。
- 📦 macOS 在放入 dylib 后重新进行 ad-hoc 签名并校验 bundle、库封装与 ZIP 解压后的签名，保留 framework 符号链接；最低版本设为 13.0，与内置 `objective_c.framework` 一致。未做 Developer ID 签名、公证或实机测试。
- 📖 README 的 macOS 去隔离命令改为 `xattr -cr FileInfra.app`（与 Release 说明一致，`-d` 只处理 bundle 顶层）。

**English:**
- ⬆️ Merged dufs 0.47 and subsequent upstream fixes through `ec4ea01`, retaining old-WebView/no-JS compatibility, archive fixes and FFI. Fixed repeated Digest nonce checks on MOVE/COPY, HTTP/2 and HTTP/1 request-target validation, directory MOVE destination child permissions, and no-JS filename attribute escaping.
- 🔒 dufs permissions constrain both symlink routes and physical targets, including each recursive ZIP/search entry. Digest capacity preserves fresh replay records and rejects unsupported auth-int; no-JS forms check browser Origins. Range lengths use u64 for downloads above 4 GiB on 32-bit targets; download filenames escape quotes and backslashes.
- 🐛 The dufs editor sets the native read-only property and retains draft, selection and focus after 403/500 saves. FFI startup failure clears state, empty listener configurations and unsupported TLS arguments are rejected, and explicit binding follows the CLI. The maintained shim matches pinned source `8e8cce6`.
- 🐛 Restored ES5 syntax in the tools page, exact sender acknowledgements, whitespace and trailing newlines. Failed modern clipboard writes try the legacy API, then show a visible, fully selected multiline field for manual copying. Duplicate snapshots preserve selection.
- 🔒 Enforced the clipboard's 1 MiB UTF-8 streaming limit, rejected invalid encoding and oversized WebSocket text, checked browser API/WS Origins, and isolated unfinished requests during stop. The tools page still has no authentication.
- 🐛 Isolated Android start/stop, Activity restoration and notifications by operation generation. Canceled startup clears tools, addresses and owned FFI staging; superseded native workers cannot replace newer process handles/errors. Notification Send waits for app focus, reads once and validates a private random action token. Superseded log polling/preparation/truncation cannot mutate a new run; restoring the same run preserves history and counts.
- 🐛 Wrongly typed configuration fields use individual defaults while preserving secure credential priority/migration. Setup completion applies language/theme/color to the root app. Log paths use real filesystem containment and reject outside/dangling symlinks and encoded traversal.
- ♿ Integrated reviewed small-screen layout, touch target, contrast, focus and semantic fixes, with actual locale-switch and browser interaction regressions.
- 📦 Windows portable/installer bundles include three VC++ runtime DLLs; NSIS requires an explicit version. Linux deb dependencies come from all shipped ELF imports plus explicitly declared dynamically loaded EGL/GLES libraries, with matching RPM SONAME requirements. Ownership is root, and icons/window matching/repeated packaging are fixed. Linux/macOS packaging always builds the pinned core. AppImage FFI staging uses independent 0700 directories and ownership-scoped cleanup.
- 🛠 CI pins Rust 1.99.1 and runs Flutter/browser, native Android, script and packaging regressions, certificate continuity and actual FFI restart checks. Flutter generates the Gradle wrapper before native tests in a fresh checkout. Certificate parsing supports SDK 37 scheme labels and rejects invalid signatures, missing digests and different certificates. A minimal Ubuntu 18.04 desktop installs the actual deb through apt and checks deb/AppImage windows and continued startup. Checksums use flat download names and include experimental iOS ZIPs with the native executable. F-Droid preparation has an explicit unsigned path and checks pinned source version/support/reachability; submission remains postponed.
- ✨ New macOS Intel (x86_64) release asset `FileInfra-*-macos-x64.zip`, alongside the Apple Silicon `-macos-arm64.zip`. Flutter's macOS release build was already a universal arm64 + x86_64 binary and only libdufs.dylib was arm64-only; dufs is now also cross-compiled for x86_64 on the same Apple Silicon runner, and packaging verifies that every Mach-O in the bundle contains the target architecture.
- 🐛 Fixed `scripts/build_macos.sh x86_64` always failing (it looked for `libdufs-macos-x64.dylib` while `build_dufs.sh` writes `libdufs-macos-x86_64.dylib`); unknown arch arguments now error out instead of silently building x86_64, and re-running no longer nests the `.app` into the previous bundle.
- 🐛 The macOS app no longer runs in the App Sandbox: the sandboxed release build lacked the `network.server` entitlement, so the embedded dufs could not accept LAN connections, nor reopen a previously chosen share directory after a relaunch. ⚠️ Settings saved inside the sandbox container are not migrated (the setup wizard runs again); still needs verification on a real Mac.
- 📦 macOS is ad-hoc signed after staging the dylib, checks the bundle/library seal and signatures after ZIP extraction, and retains framework symlinks. The minimum is now macOS 13.0, matching the embedded `objective_c.framework`. Developer ID signing, notarization and device testing remain unavailable.
- 📖 README's macOS quarantine fix is now `xattr -cr FileInfra.app` (matching the release notes; `-d` only clears the bundle's top level).

## [v0.5.12](https://github.com/zocs/fileinfra/releases/tag/v0.5.12) (2026-10)

**中文：**
- 🐛 修复工具页「复制到本机」把同步时间戳附加到共享内容的问题，并为不支持网页剪贴板 API 的 HTTP 页面增加回退。
- 📖 更新中英文 README，补充工具页、共享剪贴板、Android 快捷控制及相关安全说明。

**English:**
- 🐛 Fixed the Tools page's "Copy to device" button appending the synchronization timestamp to shared text, with a fallback for HTTP pages where the browser Clipboard API is unavailable.
- 📖 Updated the English and Chinese READMEs with the tools page, shared clipboard, Android quick controls, and security notes.

## [v0.5.11](https://github.com/zocs/fileinfra/releases/tag/v0.5.11) (2026-09)

**中文：**
- 🐛 修复 Ubuntu 18.04 兼容版「选择分享目录」仍弹出文件选择器的问题：v0.5.10 引入的 zenity/kdialog 原生选择器在该环境下因 kdialog 参数顺序、AppImage 环境变量泄漏、以及工具异常退出被误判为「已取消」而失效；现已修正参数顺序、启动原生工具前清洗子进程环境，并按退出码区分「选中/取消/异常」，异常时正确回退。目录选择器标题改走多语言。

**English：**
- 🐛 Fixed the Ubuntu 18.04 compat build still showing a file picker when choosing a share directory: the zenity/kdialog native choosers added in v0.5.10 failed there due to wrong kdialog argument order, AppImage environment leaking into the child process, and a tool erroring out being mistaken for a cancel. Argument order is fixed, the child environment is sanitized before launching a native tool, and exit codes now distinguish select/cancel/error (falling back correctly on error). The chooser title is localized.

## [v0.5.10](https://github.com/zocs/fileinfra/releases/tag/v0.5.10) (2026-09-03)

**中文：**
- 🐛 修复 Linux 上「选择目录」弹出文件选择器的问题：file_picker 的 XDG portal 路径（`OpenFile` + `directory:true`）在部分后端被忽略，改为优先调用桌面环境原生目录选择器（zenity/kdialog），file_picker 兜底；若返回文件路径则自动取父目录。
- 🔧 CI 修复：Release job 下载 artifacts 时排除 Docker Buildx 的 `*.dockerbuild` cache 产物（非 zip 容器，下载解压必失败）——v0.5.7/0.5.8/0.5.9 连续三版因此无法自动发布、需手动绕道，本次起恢复全自动。

**English:**
- 🐛 Fixed Linux "pick directory" showing a file picker: file_picker's XDG portal path (`OpenFile` + `directory:true`) is ignored by some backends; now tries native desktop directory choosers (zenity/kdialog) first, file_picker as fallback, and falls back to the parent dir if a file path was returned.
- 🔧 CI fix: the Release job now excludes Docker Buildx's `*.dockerbuild` cache artifacts from the download (raw gzip, not a zip container — extraction always failed). v0.5.7/0.5.8/0.5.9 releases had to be published manually for that reason; automatic publishing is restored.

## [v0.5.9](https://github.com/zocs/fileinfra/releases/tag/v0.5.9) (2026-09-02)

**中文：**
- 🔧 服务验证优化：启动后后台异步校验服务可用性（端口监听 + HTTP 响应），失败自动回滚；启动按钮即时翻转，不再等待验证。
- 🐛 修复停止服务后快速重启时服务假运行：Kotlin dedup 现在验证子进程存活，避免孤儿进程被 pkill 后遗留 `isRunning=true` 导致跳过启动。
- ⚡ 桌面端停止服务延迟从 ~1s 降到 ~100ms。

**English:**
- 🔧 Service health verification: async TCP + HTTP probes after startup, automatically roll back on failure; the Start/Stop button flips instantly without waiting for validation.
- 🐛 Fixed fake-running state after stop+quick-restart: Kotlin dedup now checks child-process aliveness, preventing a stale `isRunning=true` from skipping the restart when the orphan was already killed by pkill.
- ⚡ Desktop stop latency reduced from ~1s to ~100ms.

## [v0.5.8](https://github.com/zocs/fileinfra/releases/tag/v0.5.8) (2026-09-01)

**中文：**
- 🐛 Ubuntu 18.04 兼容版首屏卡死：无 keyring/secret-service 环境首次启动时 `save()` 不再被 secure storage 异常阻断（向导能正常走完）；无 XDG portal 时选择目录/文件给出明确提示。
- 🐛 Android 10/EMUI 分区存储下无法启动：目录可读性探测改为**非阻断**——服务照常启动并展示警告（可改选内部存储公共目录）；仅在服务真正启动后才展示警告。
- 🔧 代码审查修复批（v0.5.7 回看）：通知栏按钮三语、QR 超长文本 400、剪贴板 POST body 1MB 上限、WS 二进制帧守卫、通知栏剪贴板开关即时生效、README 补充 Android 10 剪贴板说明。

**English:**
- 🐛 Ubuntu 18.04 compat first-run stuck: `save()` no longer blocked by secure-storage failure on keyring-less systems (wizard completes); picking a dir/file without an XDG portal now shows a clear message.
- 🐛 Android 10/EMUI could not start under scoped storage: the directory readability probe is now **non-blocking** on Android — the server starts with a warning banner (pick an internal public dir like Documents); the warning only appears after the server is confirmed running.
- 🔧 Code-review fix batch (v0.5.7 follow-up): trilingual notification buttons, QR overflow → 400, 1MB cap on clipboard POST body, WS binary-frame guard, notification clipboard toggle takes effect immediately, README notes on Android 10 clipboard access.

## [v0.5.7](https://github.com/zocs/fileinfra/releases/tag/v0.5.7) (2026-08-31)

**中文：**
- 🔳 工具页：剪贴板 + 二维码生成二合一选项卡页面；支持多行同时生成、样式选择（方块/圆角/圆点）、前景/背景色自定义、SVG 下载。
- 🔳 离线路由 `/qr?text=...`：输入文字或网址即可生成 SVG 二维码（纯本地 `qr` 包生成，不上传网络）。
- 📋 通知栏新增「发送剪贴板/拉取剪贴板」按钮（设置页可关闭），单向发送将本机剪贴板推送至工具页，拉取则将工具页共享内容写入本机剪贴板。
- 🔧 `/api/clipboard` HTTP 端点：GET 返回共享文本，POST 设置并广播。

**English:**
- 🔳 Tools page: two-tab layout (clipboard + QR generator); supports multiple QR rows, style selection (square/rounded/dots), custom fg/bg colors, SVG download.
- 🔳 Offline QR code generation at `/qr?text=...` — enter text or URL, get a QR SVG (generated locally via `qr` package).
- 📋 Notification now has "Send clipboard / Pull clipboard" buttons (toggleable in settings). Send pushes the device clipboard to the Tools page; pull writes the shared content back to the device clipboard.
- 🔧 `/api/clipboard` HTTP endpoint: GET returns the shared text, POST sets and broadcasts it.

## [v0.5.6](https://github.com/zocs/fileinfra/releases/tag/v0.5.6) (2026-08-30)

**中文：**
- ✨ 共享剪贴板：服务运行时可与局域网内所有浏览器实时同步剪贴板（独立端口 = dufs 端口 + 2000，默认 7000；同一端口 HTTP 页面 + WebSocket 双向推送，零第三方依赖）。
- 🔧 剪贴板端口避开浏览器不安全端口（6000=X11 等，浏览器直接拒绝访问）。
- 🌐 无 JS 分享页（`?noscript`，供旧 WebView / 文本浏览器）支持上传文件、新建文件夹、删除条目（dufs 核心 v0.46.0-fix5）。

**English:**
- ✨ Shared clipboard: while the server is running, all LAN browsers can sync clipboard content in real time (separate port = dufs port + 2000, default 7000; HTTP page + WebSocket push on the same port, zero third-party deps).
- 🔧 Clipboard port avoids browser-unsafe ports (6000=X11 etc., browsers refuse to open them).
- 🌐 The no-JS fallback page (`?noscript`, for old WebViews / text browsers) can now upload files, create folders, and delete items (dufs core v0.46.0-fix5).

## [v0.5.5](https://github.com/zocs/fileinfra/releases/tag/v0.5.5) (2026-08-30)

**中文：**
- ✨ 通知栏显示完整访问地址（如 `http://192.168.1.5:5000`）；切换默认地址时通知栏同步更新；磁贴重启后仍能恢复地址显示。
- 🐛 修复自定义主题色色盘空白、指示点无法拖动的问题（`_SvPanel` 两个渐变由父子嵌套改为 `Positioned.fill` 平级兄弟，内层 `DecoratedBox` 无 child 时尺寸折叠为 0 导致色盘不渲染）。

**English:**
- ✨ Notification now shows the full access address (e.g. `http://192.168.1.5:5000`); it follows the default address switch and survives tile restarts.
- 🐛 Fixed blank SV color panel and unmovable marker in the custom theme color picker (gradients were parent-child nested; inner DecoratedBox collapsed to zero size — now siblings filling the Stack).

## [v0.5.4](https://github.com/zocs/fileinfra/releases/tag/v0.5.4) (2026-08-30)

**中文：**
- ✨ 多网络地址：每个地址可设为默认，主显示地址与二维码跟随切换；每个地址带独立二维码弹窗。
- 🎨 自定义主题色：设置页色盘选任意颜色（自绘 HSV，无第三方依赖）。
- 🔧 快捷设置磁贴 API 兼容守卫（`tile.subtitle` API 29+ / `startForegroundService` API 26+，minSdk 24）。
- 🔧 dufs 网页 assets 语法门禁（ES2017 / Chromium 55+），防白屏修复回归。

**English:**
- ✨ Multiple network addresses: each can be set as default, the primary address and QR follow; each address has its own QR popup.
- 🎨 Custom theme color: pick any color from a color wheel in Settings (hand-rolled HSV, no third-party dependency).
- 🔧 Quick-settings tile API guards (`tile.subtitle` API 29+ / `startForegroundService` API 26+, minSdk 24).
- 🔧 dufs web asset syntax gate (ES2017 / Chromium 55+), preventing blank-page fix regressions.

## [v0.5.3](https://github.com/zocs/fileinfra/releases/tag/v0.5.3) (2026-08-30)

**中文：**
- 🐛 点击传输记录打开文件：由无响应优化为给出明确提示（如文件已被移动或删除、没有可用的打开应用）；不再弹出多余的媒体权限申请。
- 🐛 修复部分设备上分享目录不可读导致无法访问文件的问题：启动时给出明确原因。
- ✨ 传输记录保留访问失败的请求（如 403），便于远程排查。
- 📦 新增 Android universal 与分架构安装包（arm64 / armv7 / x86_64）。
- 🌐 为旧版 WebView（Chromium 55-79）设备访问提供基础分享页面入口。

**English:**
- 🐛 Opening a file from the transfer log no longer does nothing: a clear message is shown when the file has been moved or deleted, or when no app can open it. Extra media-permission prompts are gone as well.
- 🐛 Fixed file access failing on devices where the shared folder is not readable: startup now shows a clear reason.
- ✨ The transfer log keeps failed requests (e.g. 403) for easier remote troubleshooting.
- 📦 Added Android universal and per-ABI installers (arm64 / armv7 / x86_64).
- 🌐 Added a basic sharing page entry for devices with older WebViews (Chromium 55-79).

## [v0.5.2](https://github.com/zocs/fileinfra/releases/tag/v0.5.2) (2026-08-23)

**中文：**
- 🐛 修复打包下载大目录时压缩包不完整的问题：以照片、视频为主的 GB 级目录，下载的 zip 会在中途无声结束、无法打开；小目录与文本目录不受影响。升级文件服务内核（dufs v0.46.0-fix3）修复。

**English:**
- 🐛 Fixed folder zip downloads ending up incomplete: with large photo/video folders (GB-scale), the archive finished mid-download without any error and could not be opened; small and text-heavy folders were unaffected. Fixed by upgrading the file-server core (dufs v0.46.0-fix3).

## [v0.5.1](https://github.com/zocs/fileinfra/releases/tag/v0.5.1) (2026-08-22)

**中文：**
- ✨ Android 新增快捷开关磁贴：不打开应用即可启/停文件分享（在下拉快捷开关的编辑面板里添加「FileInfra」；首次使用前需在应用内配置一次）。
- ✨ Android 常驻通知增加「停止分享」按钮；并按新系统规范请求通知权限，服务运行时不再被系统从通知栏隐藏。
- 🔒 修复传输记录「点击打开」可能打开分享目录之外文件的问题。
- 🐛 Android 15+：修复长时间分享约 6 小时后应用被系统强制关闭的问题。
- ⚡ Android：启动服务期间界面不再卡顿，停止操作即时响应。
- 🐛 修复启动时可能把残留的旧服务进程误判为「已启动」、展示失效地址的问题。
- 🐛 桌面端：启动后若端口被抢占会直接报错，不再展示打不开的二维码。
- 🐛 修复配置文件损坏或系统密钥库异常时启动白屏的问题。
- 🐛 服务状态与错误提示补全英文/繁中翻译。
- 🛠 Release 下载附 checksums.txt（SHA-256）；恢复 .rpm 安装包产出；deb 包补齐运行依赖。

**English:**
- ✨ Android: new Quick Settings tile — start/stop sharing without opening the app (add "FileInfra" from the tile editor; configure once in the app first).
- ✨ Android: the persistent notification gains a "Stop sharing" action, and notification permission is now requested per current system rules, so a running server is no longer hidden from the shade.
- 🔒 Fixed tap-to-open on transfer records possibly opening files outside the shared directory.
- 🐛 Android 15+: fixed the app being force-closed by the system after about six hours of sharing.
- ⚡ Android: the UI no longer stutters while the server starts, and Stop responds immediately.
- 🐛 Fixed a leftover process from a previous run occasionally being reported as "running", advertising an address that no longer worked.
- 🐛 Desktop: a port stolen between checks now fails with an error instead of showing a QR code nobody can open.
- 🐛 A corrupt config file or broken system keyring no longer white-screens the app at launch.
- 🐛 Server status and error messages are now translated (English/Traditional Chinese).
- 🛠 Release downloads now include a checksums.txt (SHA-256); the .rpm package is back; the .deb declares its runtime dependencies.

## [v0.5.0](https://github.com/zocs/fileinfra/releases/tag/v0.5.0) (2026-08-15)

**中文：**
- 📛 **项目更名：`DufsHub` → `FileInfra`**。应用名、包名、桌面入口、安装器、启动图同步更新。
- ⚠️ applicationId 由 `cc.merr.dufshub` 变更为 `cc.merr.fileinfra`——breaking change：老版本无法覆盖升级，请卸载旧版后安装新版。
- ✨ 权限预设「允许上传」现默认附带文件夹下载；开关「允许归档下载」更名为「允许文件夹下载」；使用帮助、组网提示与设置页描述文案更新。
- ⬆️ dufs 核心升至 v0.46.0-fix2：文件夹打包下载引擎换用 async-deflate-zip v0.2.0，并纳入 `--path-prefix` 前缀边界匹配、macOS liblzma 链接等上游修复。

**English:**
- 📛 **Project renamed: `DufsHub` → `FileInfra`**. App name, package ids, desktop entries, installer, and splash updated across all platforms.
- ⚠️ applicationId changed from `cc.merr.dufshub` to `cc.merr.fileinfra` — breaking: existing installs cannot upgrade in place; uninstall the old version, then install fresh.
- ✨ The "Allow upload" permission preset now includes folder download; the toggle formerly labeled "Allow Archive Download" is now "Allow Folder Download"; help, networking-tip, and settings copy revised.
- ⬆️ dufs core bumped to v0.46.0-fix2: folder archive downloads now use async-deflate-zip v0.2.0, and upstream fixes for `--path-prefix` boundary matching and macOS liblzma linking are included.

## [v0.4.4](https://github.com/zocs/fileinfra/releases/tag/v0.4.4) (2026-08-04)

**中文：**
- 🐛 桌面端：修复关闭窗口（点右上角 X、Alt+F4 或托盘「退出」）后要等约 30 秒才真正关闭的问题，现在瞬间关闭。

**English:**
- 🐛 Desktop: fixed the app hanging ~30s before actually closing after you click the window's X (or Alt+F4, or tray Quit) — it now closes instantly.

---

## [v0.4.3](https://github.com/zocs/fileinfra/releases/tag/v0.4.3) (2026-07-31)

**中文：**
- ⚡ 大幅减少传输过程中的界面卡顿：活动日志改为批量刷新，二维码不再随统计数字变化反复重绘。
- ⚡ 桌面端：停止服务不再卡住界面（服务在后台收尾）。
- 🐛 桌面端：修复高负载下下载可能被提前截断/重置的问题（Windows 上尤为明显）。
- 🐛 修改权限前的「重启服务」确认框，现在只在最近 15 秒内有传输活动时弹出。
- ⬆️ 内核 dufs 升级到 v0.46.0：带来上游多项修复与改进（认证逻辑修正、HTTP Range 修复、符号链接安全加固、HEAD 请求提速、可自定义 404 页面等）。

**English:**
- ⚡ Much smoother UI during transfers: activity-log updates are now batched, and the QR code no longer re-renders on every stats tick.
- ⚡ Desktop: stopping the server no longer freezes the UI (shutdown finishes in the background).
- 🐛 Desktop: fixed downloads possibly being cut short / reset under heavy load (most visible on Windows).
- 🐛 The "restart server" confirmation before permission changes now only appears if there was transfer activity in the last 15 seconds.
- ⬆️ Upgraded the dufs core to v0.46.0: brings many upstream fixes and improvements (auth-logic fixes, HTTP Range fix, symlink hardening, faster HEAD requests, customizable 404 page, and more).

---

## [v0.4.2](https://github.com/zocs/fileinfra/releases/tag/v0.4.2) (2026-06-12)

**中文：**
- 🔒 增强账号密码安全：修复密码在特定情况下可能被记录到系统日志，并限制了会导致登录认证出错的特殊字符。
- 🐛 提升运行稳定性，避免个别请求出错导致应用 / 服务整体崩溃。
- 🐛 Android 通知栏文案现在跟随应用内的语言设置。
- 🐛 桌面端：通过系统方式（如 Alt+F4）关闭窗口时，现在也会遵循「关闭行为」设置。
- 🐛 桌面端：修复每次启动残留临时文件的问题。

**English:**
- 🔒 Hardened account/password security: fixed the password possibly being written to system logs, and restricted special characters that could break login.
- 🐛 Improved stability so a single failing request no longer crashes the whole app / server.
- 🐛 The Android notification text now follows the in-app language setting.
- 🐛 Desktop: closing the window via the system (e.g. Alt+F4) now also respects your "close action" setting.
- 🐛 Desktop: fixed leftover temporary files accumulating on each launch.

---

## [v0.4.1](https://github.com/zocs/fileinfra/releases/tag/v0.4.1) (2026-05-27)

**中文：**
- ✨ 启动/停止按钮内的 loading 指示器换成自定义三点跳动动画：Material 的 `CircularProgressIndicator` 每帧重绘整个 `Canvas.drawArc`，在 120Hz debug build 上肉眼可见卡顿；新组件只平移 `Offset`+`Opacity`，任何刷新率都顺滑。
- 💅 Splash 文字字号从 48 缩到 24（letterSpacing 4→2），让 Flutter splash 与 native bitmap splash（186×24px @ mdpi）起手视觉一致，消除 Flutter 接管 native 窗口时「突然变大」的跳帧。

**English:**
- ✨ Replaced the start/stop button's loading indicator with a custom three-dot bouncer: Material's `CircularProgressIndicator` redraws a full `Canvas.drawArc` every frame and visibly stutters at 120Hz in debug builds; the new widget only translates `Offset`+`Opacity`, so it stays smooth at any refresh rate.
- 💅 Shrank splash text from fontSize 48 to 24 (letterSpacing 4→2) so the Flutter splash starts visually identical to the native bitmap splash (186×24px @ mdpi), removing the "pop bigger" frame when Flutter takes over from the native window.

---

## [v0.4.0](https://github.com/zocs/fileinfra/releases/tag/v0.4.0) (2026-05-27)

**中文：**
- 🏷️ **项目改名：`inout` → `DufsHub`**（applicationId 由 `cc.merr.inout` 改为 `cc.merr.dufshub`）。这是 breaking change——老版本无法直接 OTA 升级，需要卸载老版本后安装新版本。
- 🔒 修复 Dart 侧 `--auth user:pass@/:rw` 仍会打到 logcat（v0.3.4 只修了 Kotlin 侧，Dart 侧的 `_log(args.join(...))` 仍泄漏）(C1)
- 🐛 修复 Android 14+ (API 34) 启动 foreground service 时缺少 `FOREGROUND_SERVICE_TYPE_DATA_SYNC` 参数导致的 `MissingForegroundServiceTypeException` (C2)
- 🐛 修复 macOS bundle id 仍是 Flutter 模板占位 `com.inout.inoutFlutter` (C3)
- 🐛 修复 Linux APPLICATION_ID 仍是 Flutter 模板占位 `com.inout.inout` (C4)
- 🔒 修复 release build keystore 缺失时静默 fallback 到 debug 签名——现在 fail-fast，避免发出 debug-signed APK 到 release 通道导致用户无法 OTA 升级 (C5)

**English:**
- 🏷️ **Project renamed: `inout` → `DufsHub`** (applicationId changed from `cc.merr.inout` to `cc.merr.dufshub`). This is a breaking change — existing installs cannot OTA-upgrade; users must uninstall the old version and install the new one.
- 🔒 Fixed Dart side still logging `--auth user:pass@/:rw` to logcat (v0.3.4 only fixed the Kotlin side; Dart's `_log(args.join(...))` still leaked) (C1)
- 🐛 Fixed Android 14+ (API 34) `MissingForegroundServiceTypeException` crash on service start; now passes `FOREGROUND_SERVICE_TYPE_DATA_SYNC` (C2)
- 🐛 Fixed macOS bundle id stuck on Flutter template placeholder `com.inout.inoutFlutter` (C3)
- 🐛 Fixed Linux APPLICATION_ID stuck on Flutter template placeholder `com.inout.inout` (C4)
- 🔒 Fixed release build silently falling back to the debug keystore when `KEYSTORE_FILE` is missing — now fail-fast, preventing debug-signed APKs from reaching the release channel (C5)

---

## [v0.3.4](https://github.com/zocs/inout/releases/tag/v0.3.4) (2026-05-02)

**中文：**
- 🔒 修复 Android 端 dufs 启动日志把 `--auth user:pass@/:rw` 直接打到 logcat（任何 adb client 或同 user 应用都能读取用户密码）
- 🐛 修复应用内"关于"页版本号显示与 `pubspec.yaml` 不一致——改为 runtime 从 `package_info_plus` 读，发版不再需要手动同步 `lib/app.dart::appVersion`
- 🐛 修复 secure_storage 凭据迁移逻辑：之前每次 load 都会用 SharedPreferences 里的 legacy auth 覆写 secure_storage 里更新过的凭据（用户改密码后下次启动密码被改回去）
- 🐛 修复端口冲突自动 +1 后，用户配置的原始端口被持久化覆盖：现在用户偏好端口和实际运行端口分开记录，下次启动仍尝试原端口
- 🐛 修复 Android 启动服务的 race：之前 Dart 端固定等 500ms 就查询服务状态，但 Kotlin 的 socket probe 最多需要 5s 才完成，导致服务实际跑起来但 UI 报"启动失败"。现改为最多轮询 6s
- ✨ 切换语言立即生效，无需重启 app（之前必须重启才能看到 UI 文案变化）
- 🏗️ NSIS Windows 安装包改为从 CI 命令行注入版本号（`/DAPP_VERSION=...`），下次发版不会再因为忘改 .nsi 内的硬编码版本号而上传失败

**English:**
- 🔒 Fixed Android dufs startup log writing the `--auth user:pass@/:rw` argument verbatim to logcat (any adb client or same-uid app could read user credentials)
- 🐛 Fixed in-app About page version drifting from `pubspec.yaml` — now read at runtime from `package_info_plus`, so releases no longer require manual sync of `lib/app.dart::appVersion`
- 🐛 Fixed secure_storage credential migration: previous load() would re-write the legacy SharedPreferences auth into secure_storage every run, overwriting any newer credential the user had set (effectively reverting password changes on next launch)
- 🐛 Fixed port-conflict auto-bump persisting the bumped port over the user's preferred port: user preference and actual-runtime port are now tracked separately
- 🐛 Fixed an Android start race: Dart used to wait a fixed 500ms before checking service status, but the Kotlin socket probe takes up to 5s — UI would falsely report "start failed" while the service actually came up. Now polls up to 6s
- ✨ Language switch in Settings now takes effect immediately (previously required app restart)
- 🏗️ NSIS Windows installer now reads APP_VERSION from the CI command line (`/DAPP_VERSION=...`) instead of a hardcoded `.nsi` constant — no more silent missing setup.exe when the .nsi version isn't manually bumped

---

## [v0.3.3](https://github.com/zocs/inout/releases/tag/v0.3.3) (2026-05-01)

**中文：**
- 🐛 修复 Android < 15 设备点击启动后立即报"服务启动失败：dufs did not start listening on port 5000"——NDK r28 默认 16KB 页对齐让旧设备 dynamic linker bind() 异常 + 服务主线程上 `Socket.connect()` 被 `NetworkOnMainThreadException` 静默吞掉，两个 bug 叠加把已经在 listen 的 dufs 误报为启动失败
- 🐛 修复 AppImage 升级后偶发使用旧版本 libdufs 的提取冲突（提取路径加 mtime+pid 唯一化）
- ✨ 端口冲突自动恢复：5000 被占时先尝试接管同 user 的残留 dufs/inout 进程；接管不了则自动切到 5001+，UI SnackBar 提示
- ✨ Auth 凭据从 SharedPreferences 迁移到平台 keychain（flutter_secure_storage）
- ✨ 传输日志条目支持点击复制完整路径
- 🏗️ 新增 Docker 化本地构建支持（Linux x64 + Android arm64），与 CI 行为对齐
- 🏗️ CI 加入 libdufs.so 4KB 页对齐 hard guard、Gradle cache、独立 `flutter analyze` job
- 🏗️ Flutter 升级到 3.41.5；编译器升级到 NDK r28，但强制 4KB 页对齐保留对 Android 7.0+ 的全部兼容

**English：**
- 🐛 Fixed Android < 15 devices reporting "service failed to start: dufs did not start listening on port 5000" right after tapping Start. Two stacked bugs: NDK r28 changed default LOAD-segment alignment to 16KB which the dynamic linker on older Android mishandles, and the new socket-connect probe silently swallowed `NetworkOnMainThreadException` because it ran on the foreground service's main thread — leaving an actually-listening dufs reported as failed
- 🐛 Fixed AppImage upgrade occasionally reusing a stale extracted libdufs binary (extraction path now embeds mtime+pid)
- ✨ Auto port-conflict recovery: when :5000 is busy, app first tries to reclaim a leftover dufs/inout process owned by the same user; otherwise bumps to :5001+ and surfaces a SnackBar notice
- ✨ Auth credentials moved from SharedPreferences to the platform keychain (flutter_secure_storage)
- ✨ Tap a transfer-log entry to copy its full path to the clipboard
- 🏗️ Added Dockerized local builds for Linux x64 and Android arm64 (`scripts/docker_build_*.sh`) mirroring CI behavior
- 🏗️ CI gained a hard libdufs.so 4KB page-alignment guard, Gradle cache, and a standalone `flutter analyze` job
- 🏗️ Flutter bumped to 3.41.5; toolchain bumped to NDK r28 but forced back to 4KB page alignment so support down to Android 7.0+ is preserved

---

## [v0.3.2](https://github.com/zocs/inout/releases/tag/v0.3.2) (2026-04-27)

**中文：**
- 🐛 修复桌面端单文件分享在路径包含空格/中文/特殊字符时的 FFI 启动失败
- 🐛 修复 Android 单文件分享后切换预置目录仍按单文件模式校验导致的 `File not found`
- 🐛 修复 Android/桌面端单文件分享 working directory 处理错误
- ✨ 启动/停止服务新增过渡态进度条与忙碌文案，降低等待卡顿感知
- ✨ 退出前若需停止服务，关闭确认流程也复用同一套过渡反馈

**English：**
- 🐛 Fixed desktop single-file sharing startup failures when paths contain spaces, CJK text, or special characters
- 🐛 Fixed Android preset directories still being validated as single-file paths after previous file sharing, causing `File not found`
- 🐛 Fixed working-directory handling for single-file sharing on Android and desktop
- ✨ Added transition progress feedback for server start/stop to reduce perceived stutter
- ✨ Reused the same transition feedback when exiting while a running server must be stopped first

---

## [v0.3.1](https://github.com/zocs/inout/releases/tag/v0.3.1) (2026-04-20)

**中文：**
- 🐛 修复 Android 8/9 等 API 30 以下设备因 DT_RELR packed relocations 导致的 dufs 启动崩溃
- 🐛 修复应用内版本号显示与 `pubspec.yaml` 不一致
- 🐛 修复传输日志统计无法累计文件大小的问题
- 🏗️ 传输日志改为增量读取，避免长时间运行后反复整文件扫描
- ✨ 新增显式“选择分享文件”入口，不再只依赖桌面拖放触发单文件分享

**English：**
- 🐛 Fixed dufs startup crash on Android API < 30 caused by DT_RELR packed relocations
- 🐛 Fixed in-app version display drifting from `pubspec.yaml`
- 🐛 Fixed transfer log stats not accumulating file sizes
- 🏗️ Switched transfer log reading to incremental reads to avoid full-file rescans over long sessions
- ✨ Added an explicit "select share file" entry instead of relying only on desktop drag-and-drop

---

## [v0.3.0](https://github.com/zocs/inout/releases/tag/v0.3.0) (2026-03-31)

**中文：**
- ✨ 隐藏系统文件：自动隐藏 .git、.DS_Store、Thumbs.db、.env 等系统文件（默认开启）
- ✨ 渲染首页：目录有 index.html 时自动渲染，方便简易测试网页
- 🐛 修复 Linux/macOS 构建脚本版本号提取错误（0.2.929 → 0.2.9）
- 🏗️ CI 排除 iOS 从 release 发布（仅编译测试）

**English：**
- ✨ Hide system files: auto-hide .git, .DS_Store, Thumbs.db, .env etc. (on by default)
- ✨ Render index: auto-render index.html if present in directory for quick web testing
- 🐛 Fixed Linux/macOS build script version extraction bug (0.2.929 → 0.2.9)
- 🏗️ CI excludes iOS from release (compile-only)

---

## [v0.2.8](https://github.com/zocs/inout/releases/tag/v0.2.8) (2026-03-28)

**中文：**
- ✨ Android 正式签名发布，CI 构建统一使用 release keystore，覆盖安装不再需要先卸载旧版
- ✨ F-Droid 上架材料已提交审核（Fastlane metadata、GitLab MR）
- 🐛 修复多平台版本号不一致的问题（安装包文件名和 app 内显示版本对不上）
- 🏗️ CI 全平台版本号统一从 pubspec.yaml 读取

**English：**
- ✨ Android release signing — CI builds use a unified release keystore, no need to uninstall before updating
- ✨ F-Droid submission prepared (Fastlane metadata, GitLab MR)
- 🐛 Fixed version number inconsistency across platforms (package filename vs in-app display)
- 🏗️ CI reads version from pubspec.yaml across all platforms

---

## [v0.2.7](https://github.com/zocs/inout/releases/tag/v0.2.7) (2026-03-27)

**中文：**
- 🐛 修复 Windows NSIS 安装包路径含空格时引号处理错误
- 🐛 修复 Android FFI 重复调用导致的并发崩溃
- 🐛 修复 F-Droid 构建版本号检测
- 🐛 修复版本号同步问题

**English：**
- 🐛 Fixed NSIS installer quoting error when path contains spaces
- 🐛 Fixed Android FFI concurrent crash from re-entry
- 🐛 Fixed F-Droid build version detection
- 🐛 Fixed version number sync issues

---

## [v0.2.6](https://github.com/zocs/inout/releases/tag/v0.2.6) (2026-03-27)

### 🔧 架构重构 / Refactor: dufs FFI

**中文：**

dufs 文件服务从"作为子进程运行"改为"编译成共享库通过 FFI 加载"。解决了三个实际问题：Windows 杀毒软件误报、Linux AppImage 网络隔离、以及子进程残留。

**English：**

dufs is now compiled as a shared library (.so/.dll/.dylib) and loaded via Dart FFI instead of running as a child process. This fixes antivirus false positives on Windows, network isolation in AppImage (FUSE sandbox), and orphaned processes.

### ✨ 新功能 / Features (since v0.2.3)

**中文：**
- **传输记录** — 实时查看文件下载/上传日志
- **源码编译 dufs** — 全平台从源码编译，兼容 F-Droid 要求
- **Android 原生 Service** — dufs 跑在原生 Android Service 里，Activity 被回收后服务不中断（小米 6 等 4GB 内存设备实测修复）
- **返回键确认** — 服务运行中按返回键会弹窗确认，避免误关
- **多地址显示** — 列出所有网卡的 IP 地址和网卡名称

**English：**
- **Transfer log** — real-time download/upload history viewer
- **Source-compiled dufs** — all platforms build from source, F-Droid compatible
- **Android Native Service** — dufs runs in a native Service, survives Activity destruction (fixes low-memory devices like Mi 6)
- **Back key confirmation** — prompts before exiting while server is running
- **Multi-address display** — shows all network interfaces with names

### 🐛 修复 / Fixes

**中文：**
- Windows 杀毒软件不再误报（dufs 从 .exe 改为 .dll）
- AppImage 内文件服务无法访问的问题
- 部分 Linux 发行版打包时的权限报错
- Android API 级别调整以兼容旧设备

**English：**
- Windows antivirus no longer flags dufs (changed from .exe to .dll)
- Fixed dufs unreachable inside AppImage
- Fixed CMAKE_INSTALL_PREFIX permission error on some distros
- Adjusted Android target API for older device compatibility

---

## [v0.2.3](https://github.com/zocs/inout/releases/tag/v0.2.3) (2026-03-25)

**中文：**
- ✨ Android 文件服务改用原生 Kotlin Service 管理，低内存设备不再假死
- ✨ 新增传输记录功能，查看文件传输历史
- ✨ 返回键双重确认：服务运行中按返回会弹窗询问
- ✨ 地址列表始终显示所有网卡地址
- 🐛 修复低内存设备上 dufs 进程丢失的问题
- 🐛 修复端口冲突检测

**English：**
- ✨ Android dufs process now managed by native Kotlin Service, fixes low-memory device crashes
- ✨ Transfer log — view file transfer history
- ✨ Back key confirmation when server is running
- ✨ Address list always shows all network interfaces
- 🐛 Fixed dufs process orphaning on low-memory devices
- 🐛 Fixed port conflict detection

---

## [v0.2.2](https://github.com/zocs/inout/releases/tag/v0.2.2) (2026-03-20)

**中文：**
- 🐛 修复 Linux AppImage 内找不到 dufs 的问题
- 🐛 修复 Windows CI 构建的编码问题

**English：**
- 🐛 Fixed dufs binary not found in Linux AppImage
- 🐛 Fixed UTF-8 encoding issue in Windows CI builds

---

## [v0.2.1](https://github.com/zocs/inout/releases/tag/v0.2.1) (2026-03-18)

**中文：**
- ✨ 全新铅笔手绘风格图标（应用图标 + 系统托盘图标）

**English：**
- ✨ New hand-drawn pencil sketch icon (app + system tray)

---

## [v0.2.0](https://github.com/zocs/inout/releases/tag/v0.2.0) (2026-03-15)

**中文：**
- ✨ 桌面端拖放共享——直接拖文件/文件夹到窗口设置共享目录
- ✨ 系统托盘——最小化到托盘，右键菜单操作
- ✨ 关闭行为可选——最小化到托盘还是直接退出
- ✨ 多网卡地址列表——显示所有网络接口 IP
- ✨ 修复 Android 8 存储权限问题
- ✨ 启动动画——像素风 inout + 原生到 Flutter 无缝过渡
- ✨ 启动时自动清理残留的 dufs 孤儿进程

**English：**
- ✨ Desktop drag & drop — drag files/folders to set share path
- ✨ System tray — minimize to tray with right-click menu
- ✨ Close behavior choice — minimize to tray or exit
- ✨ Multi-address list — shows all network interface IPs
- ✨ Fixed Android 8 storage permission
- ✨ Animated splash — pixel-art inout with smooth Flutter transition
- ✨ Auto-cleanup of orphaned dufs processes on startup

---

## [v0.1.0](https://github.com/zocs/inout/releases/tag/v0.1.0) (2026-03-01)

🎉 首个版本 / Initial Release

**中文：**
- 文件夹和单文件分享
- 权限预设（只读 / 可上传 / 完整控制）
- 密码认证、CORS 开关
- 二维码生成
- 三语支持（简中 / 繁中 / English）
- Material 3 主题 + 6 种配色
- Android + Windows + Linux 安装包

**English：**
- Directory & single-file sharing
- Permission presets (readonly / upload / full)
- Password auth, CORS toggle
- QR code generation
- Multilingual (Simplified Chinese / Traditional Chinese / English)
- Material 3 theming with 6 color schemes
- Android + Windows + Linux packages
