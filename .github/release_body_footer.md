🤖 **Automated build & release by GitHub Actions** | **此版本由 GitHub Actions 自动化构建并发布**

> Native dufs binaries are compiled from pinned fork source. F-Droid preparation is separate; catalog submission remains postponed.

| Platform | Files | Status |
|----------|-------|--------|
| Android | universal `.apk`（全架构）+ 分架构 `.apk`（arm64-v8a / armeabi-v7a / x86_64） | ✅ |
| Windows x64 | `.zip` (portable) + `.exe` (installer) | ✅ |
| Linux x64 | `.AppImage` + `.deb` + `.tar.gz` | ✅ |
| Linux x64 (compat) | `-compat` `.AppImage` + `.deb` + `.tar.gz` — for older distributions, including Ubuntu 18.04 (glibc 2.27+) / 面向较旧发行版，包括 Ubuntu 18.04（glibc 2.27+） | ✅ |
| Linux ARM64 | `.AppImage` + `.deb` + `.tar.gz` | ✅ |
| macOS ARM64 (Apple Silicon) | `.zip` (app bundle, macOS 13+) | ⚠️ ad-hoc 签名及 CI 校验；**未公证、未实机测试** |
| macOS x64 (Intel) | `.zip` (app bundle, macOS 13+) | ⚠️ ad-hoc 签名及 CI 校验；**未公证、未实机测试** |
| iOS arm64 | `.zip` (app bundle, no codesign) | ⚠️ 仅编译测试，**未签名、未实机测试** |

> 🍎 macOS has no Developer ID signature or notarization. If Gatekeeper blocks a trusted download, extract it and run `xattr -cr FileInfra.app`. iOS is an experimental unsigned build, with installation/file-server operation unverified.
>
> Windows GUI packages are x64; Flutter does not support Windows 32-bit x86. Linux AppImage/tar bundles require compatible system libraries and working EGL/GLES graphics drivers; `.deb` declares the runtime libraries and actual ELF dependency floor. SHA-256 checksums use the release filenames and can be checked after a flat download.
