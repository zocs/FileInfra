# Release Checklist — FileInfra

每次发版先验证分支和产物，再合并并创建新的发布 tag。已发布 tag 不移动；发布后发现缺陷时提高 patch 版本和 build number。

## 1. 版本号同步

版本号: `X.Y.Z`，独立且递增的 build number: `+N`。

- [ ] `pubspec.yaml` → `version: X.Y.Z+N`
- [ ] `appVersion` 继续从 `PackageInfo.fromPlatform()` 自动读取
- [ ] NSIS 必须通过 `/DAPP_VERSION` 传入 pubspec 版本；缺少参数时明确报错，避免手工默认值漂移
- [ ] `.fdroid.yml` 的构建/当前版本与 pubspec 一致，Flutter 和 Rust 与 CI 固定版本一致
- [ ] 英文、中文 fastlane `changelogs/N.txt` 内容正确；构建使用 pubspec 默认版本，无重复 build-name/build-number
- [ ] dufs 固定到公开可获取、已测试的完整提交 SHA；上游已合并，FileInfra FFI shim 与该来源一致

## 2. CI / 构建

- [ ] `flutter analyze` 与完整 `flutter test --no-pub --reporter expanded` 通过；浏览器测试需 `npm ci --prefix test/browser` 和 Chromium
- [ ] Python 回归通过：`python3 -m unittest discover -s scripts/tests -p '*_test.py' -v` 和对应 `test/` 打包测试
- [ ] Android 原生测试通过；明确无签名路径生成未签名 APK，正常发布路径使用原有证书
- [ ] dufs 默认/无 TLS tests、Clippy、format、旧 WebView ES2017 gate 和实际 FFI 启停通过
- [ ] workflow 语法与 shell 检查通过
- [ ] 推送验证分支并真实运行 `gh workflow run build.yml --ref <branch> -f note="<用途>"`；必需平台任务全部通过，记录 run URL 与 SHA
- [ ] Windows ZIP 启动并从包内加载三个 VC++ DLL；Linux 包依赖/归属正确；macOS 符号链接、目标架构、签名及 ZIP 解压校验通过
- [ ] Android 所有发布 ABI 包含核心，API 24 linker、无 packed relocations、4 KB 对齐保持现有约束；16 KB 设备另列实测状态
- [ ] 实机验证与 CI 检查分别记录，不把编译或模拟测试当成设备验证

## 3. 文档

- [ ] `CHANGELOG.md` 已添加 X.Y.Z 版本条目
- [ ] `README.md` / `README_zh.md` 截图/功能描述是否需要更新
- [ ] `ROADMAP.md` 当前状态与实际 release 节奏一致
- [ ] `PRIVACY.md`、fastlane 描述、发布说明与实际联网/权限/存储行为一致
- [ ] `docs/` 的当前交接与历史报告追加真实跟进状态；历史证据保持可追溯
- [ ] 公开说明简洁，技术变更放在 CHANGELOG；兼容性、Windows x86 缺口、macOS ad-hoc/未公证及 iOS 实验性状态准确

## 4. Git

- [ ] 所有授权变更已提交；不包含机器本地 `.claude/`、二进制或凭据
- [ ] 验证提交祖先关系和远端状态，合并已验证的分支；保留已有工作与上游历史
- [ ] 确认 `vX.Y.Z` 不存在，创建新的 tag；仅推送本次 tag：`git push origin vX.Y.Z`
- [ ] 禁止为修复发布产物删除/重建旧 tag；需要改代码时发布下一个 patch

## 5. Release

- [ ] CI 构建全部通过
- [ ] GitHub Release 已创建（自动由 CI 触发）
- [ ] Release assets 完整（四种 APK、Windows ZIP/NSIS、Linux 正常/compat 包、macOS arm64/x64 ZIP、实验性 iOS ZIP及 checksums.txt）
- [ ] 下载实际产物并核对 SHA-256、版本、架构和签名；校验文件使用平铺下载文件名
- [ ] F-Droid 配方固定到公开可达且包含当前版本/无签名支持的源码提交；用预先存在的稳定提交避免自引用占位 SHA

## 6. 发布后

- [ ] `python3 scripts/fdroid_prep_check.py` 通过；记录其局限，F-Droid builder 和上架策略尚需外部验证
- [ ] F-Droid 上架仍推迟；仅在收到明确提交要求后创建 fdroiddata MR
- [ ] 测试安装：Android 升级安装、Windows 覆盖安装
- [ ] 若本次用户要求 LAN 交付，按指定平台打 ZIP、附校验值和架构说明，上传指定 FileInfra 服务并核对远端长度/哈希
- [ ] 发布、上传与后续审查修复结果写回所有当前文档；如有未完成项，记录具体原因与下一步

## v0.5.13 执行记录（2026-11-09）

以下是本次实际结果，上方仍作为以后发版的通用模板。

| 检查 | 实际结果 |
|---|---|
| 版本与 tag | 项目 `0.5.13+58`；新标签 `v0.5.13` 指向已验证的 `7da4eee090ac2bfa9dfd4a38cceb440b2428289a`，未移动旧 tag |
| 审查与上游 | 完整维护源码两轮 151/151、154/154，后续变更另行复核；dufs main 合并上游 `ec4ea01`，固定最终公开源码 `8e8cce6` |
| CI | [分支 CI](https://github.com/zocs/FileInfra/actions/runs/42529814093) 必需 9/9；[标签 CI](https://github.com/zocs/FileInfra/actions/runs/42531076830) 含自动 Release 10/10 |
| 回归 | Flutter 151、Android 原生 22、脚本 28、Python 打包 32；dufs 默认/无 TLS 本地 395/388，最终三系统 CI 均通过 |
| 实际运行 | Windows 便携 GUI/三个包内 VC++ DLL/FFI；macOS ARM64 与 Rosetta Intel FFI；Linux x64/ARM64 FFI；干净 Ubuntu 18.04 apt 安装实际 deb 后验证 deb/AppImage 窗口和持续运行 |
| 发布 | [正式 Release](https://github.com/zocs/FileInfra/releases/tag/v0.5.13) 于 06:48 发布，21 个附件齐全；校验文件与全部附件名及 GitHub SHA-256 一致 |
| 下载验证 | 实际下载 Windows x64 ZIP、Linux x64 compat AppImage/deb、Android arm64；核对大小/哈希/架构、原签名、API 24/核心 4 KB 对齐与 deb 依赖，下载的 compat 核心另跑 HTTP 操作和三次重启 |
| Android 版本码 | 实际四 APK 为 universal 58、armv7 1058、arm64 2058、x86_64 4058，同类型分别比旧版加 1；所有新 APK 均为原证书 `e4db9054…aed6a`。更新时保持相同 APK 类型，F-Droid 配方使用基础/universal 58 |
| F-Droid | 固定公开且含无签名支持的 `f206653`；预检 23 PASS / 3 WARN / 0 FAIL；未运行完整 builder 或提交上架 |
| LAN 交付 | ZIP 与校验文件 HTTP 201；57,186,666 字节，远端完整回读 SHA-256 一致，07:01 完成，早于 07:15；具体地址和收据保留在本地 `docs/` |

交付 ZIP SHA-256：`9cd6c8fdd79970d822b86ef639476fb553410fd6e90d8e61f4e1fab1f9ced02f`。

Windows 32 位 x86 Flutter GUI 不受 SDK 支持，未提供此包。Android 16 KB 页设备、实际升级安装、Linux 实体桌面与 macOS 真机仍需另行验证；macOS 未做 Developer ID/公证，iOS 仅实验性无签名产物。这些范围没有以源码审查或 CI 编译替代实测。
