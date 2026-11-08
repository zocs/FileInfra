# FileInfra Roadmap

## Current Status (2026-11-09)

Latest published release: [**v0.5.13**](https://github.com/zocs/FileInfra/releases/tag/v0.5.13), project build **58**. Two complete maintained-source reviews and subsequent focused fixes are complete. The tested dufs 0.47 fork/upstream merge and FileInfra changes are merged; [branch CI](https://github.com/zocs/FileInfra/actions/runs/42529814093) passed all nine required jobs, and [tag CI](https://github.com/zocs/FileInfra/actions/runs/42531076830) passed all ten build/test/release jobs. The requested Windows x64, Linux x64 compat AppImage/deb and Android arm64 ZIP was delivered to the user's LAN service and fully verified by length and SHA-256 at 07:01 Asia/Shanghai, before the 07:15 target.

Windows distribution is x64; Flutter has no Windows 32-bit x86 target. Linux x64 compat targets glibc 2.27, while normal x64/ARM64 packages declare actual ELF dependencies. macOS targets 13.0 and uses ad-hoc signatures without Developer ID/notarization. iOS is an experimental unsigned build. F-Droid preparation exists, but submission is postponed.

### v0.5.x Released
- [x] **v0.5.1** (2026-08-22): full code review batch, Android quick-settings tile, notification enhancements
- [x] **v0.5.2** (2026-08-23): dufs core v0.46.0-fix3, large-folder zip truncation fix
- [x] **v0.5.3** (2026-08-30): dufs core v0.46.0-fix4 (old WebView support), Android open-file rewrite, startup pre-check for unreadable dirs, 403 log retention, universal/per-ABI 4 APK split, release notes dual-track
- [x] **v0.5.4** (2026-08-30): multiple network addresses with per-address default + QR popup, custom theme color picker (hand-rolled HSV)
- [x] **v0.5.5** (2026-08-30): notification shows full access address (follows default address switch, survives tile restarts), SV color panel blank/marker fix
- [x] **v0.5.6** (2026-08-30): shared clipboard (port = dufs + 2000, default 7000), no-JS fallback page upload/mkdir/delete (dufs v0.46.0-fix5), browser-safe clipboard port
- [x] **v0.5.7** (2026-08-31): Tools page (clipboard + QR generator two-tab, multi-row, style/color options, SVG download), offline `/qr?text=...` route, notification clipboard buttons (toggleable), `/api/clipboard` endpoint, Ubuntu 18.04 compat builds (`*-compat-linux-x86_64.*`)
- [x] **v0.5.8** (2026-09-02): Ubuntu 18.04 compat blockers (keyring-less save + no-portal picker), Android 10 EMUI scoped-storage non-blocking startup (warning banner), v0.5.7 code-review batch (trilingual notif buttons, QR overflow 400, 1MB POST cap, WS binary guard, settings live-apply); docs alignment (ROADMAP/CHANGELOG/zh-CN fastlane backfill)
- [x] **v0.5.9** (2026-09-02): fake-running fix after stop+quick-restart (Kotlin dedup validates child-process aliveness), desktop stop latency ~1s→~100ms, startup service verification (TCP + HTTP probes, UI flips instantly, background rollback on failure)
- [x] **v0.5.10** (2026-09): native Linux directory chooser and automatic release artifact-download fix
- [x] **v0.5.11** (2026-09): Ubuntu 18.04 compat directory chooser environment/argument/exit handling
- [x] **v0.5.12** (2026-10): copied clipboard text separated from timestamps, tools/Android documentation
- [x] **v0.5.13** (2026-11-09): dufs 0.47/upstream security fixes, exact clipboard and lifecycle/configuration fixes, reviewed UI, Windows runtimes, Linux graphics dependencies/compat GUI, macOS Intel packaging and expanded CI

### v0.5.13 verification and delivery
- [x] Review the previous macOS/UI changes and preserve justified fixes
- [x] Exact clipboard text, ES5 tools page, copy fallback/manual recovery and Origin/body limits
- [x] Typed configuration recovery, real filesystem containment and setup appearance propagation
- [x] Private AppImage staging, app-local Windows runtimes, Linux dependency/ownership and macOS seal checks
- [x] Finish review follow-ups, full regression and cross-platform CI
- [x] Merge tested upstream/fork and FileInfra changes, publish fresh patch tag and verify release assets
- [x] Deliver Windows x64/Linux x64 compat/Android arm64 ZIP and record final checksums/results; Windows 32-bit x86 remains unsupported by the SDK

### Completed since last roadmap update
- [x] CI cache & checksums.txt generation
- [x] Per-ABI APK builds (--split-per-abi)
- [x] dufs web asset syntax gate (ES2017, Chromium 55+, preventing blank-page regression)
- [x] QS tile API compatibility guards (API 29/26 vs minSdk 24)
- [x] Multi-address default toggle + per-address QR popup
- [x] Custom theme color picker (HSV, no deps)
- [x] Dark mode auto-follow system
- [x] F-Droid preparation (recipe, pre-check, fastlane metadata, zh-CN)
- [x] CI run-name note mechanism (`-f note="..."` on manual triggers, shows purpose in Actions list)
- [x] Shared clipboard + notification clipboard buttons + `/api/clipboard`

### Up next (next release)
- [ ] Retest remaining device-specific behavior after the patch release
- [ ] Old tablet blank-page real-device retest (Chromium < 80 WebView + `?noscript`)
- [ ] Android 10 EMUI startup retest on device (pick internal public dir like Documents; warning should show but service starts)
- [ ] Ubuntu 18.04 compat retest on device (wizard skip + picker SnackBar + service start)

### Medium-term
- [ ] HTTPS support (self-signed or Let's Encrypt)
- [ ] Refine large-file UX after validating dufs 0.47's existing upload progress table
- [ ] Share link expiry (auto-invalidate)
- [ ] Expose the dufs core's per-directory auth rules in the GUI
- [ ] Extend existing transfer logs into traffic/connection statistics
- [ ] Additional Linux ARM64 compat build and distribution validation

### Long-term / Low-priority
- [x] WebDAV, directory archives, batch operations and file preview are already provided by the embedded dufs core; GUI configuration and device validation remain separate
- [ ] Language expansion (Japanese, Korean, etc.)
- [ ] Share statistics panel (total traffic, connections)
- [ ] Android desktop widget (quick start/stop)
- [ ] Android shortcuts (share specific dir directly)
- [ ] Windows right-click menu ("Share with FileInfra")
- [ ] macOS DMG package
- [ ] Android AAB (Play Store)
- [ ] iPad adaptation

## Known Issues

| Issue | Severity | Status |
|-------|----------|--------|
| Android 10 scoped storage limits direct-path dir listing | Medium | Workaround: probe non-blocking + warning banner; user should pick internal public dir |
| AppImage native-library staging | Medium | Private 0700 copies and ownership cleanup implemented; more distribution/device tests pending |
| macOS distribution trust | Low | Ad-hoc signed and package-checked; no Developer ID/notarization or real-device validation |
| Android 16 KB-page devices | Medium | Unverified; preserve recorded API 24/4 KB compatibility constraints pending both device classes |
| Windows 32-bit x86 GUI | Limitation | Unsupported by current Flutter SDK; released GUI is x64 |
| iOS file-server runtime | Experimental | Unsigned compile artifact; installation/process execution unverified |
| `withValues(alpha:)` requires Flutter 3.27+ | Low | Current version OK |
| NSIS `OutFile` order fragile | Low | Commented, don't touch without CI smoke |
| Linux tray left-click no signal | Low | Design decision, documented in handoff #10 |
