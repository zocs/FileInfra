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
