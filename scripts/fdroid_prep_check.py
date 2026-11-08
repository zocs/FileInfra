#!/usr/bin/env python3
"""fdroid_prep_check.py — F-Droid 上架前的本地预检。

只做「提交 MR 之前自己就能查出来」的那部分：配方内部一致性、配方与
CI/pubspec/fastlane 的漂移、仓库里混进预编译二进制、品牌残留。F-Droid 真正
的构建（在自己的 builder 里跑一遍）本地复现不了，那部分见 docs/fdroid-prep.md。

用法：
    python3 scripts/fdroid_prep_check.py            # 全量检查
    python3 scripts/fdroid_prep_check.py --help     # 本说明

退出码：0 = 无 FAIL（可能有 WARN）；1 = 有 FAIL；2 = 环境缺依赖导致无法检查。
"""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
FDROID = ROOT / ".fdroid.yml"
WORKFLOW = ROOT / ".github" / "workflows" / "build.yml"
PUBSPEC = ROOT / "pubspec.yaml"
FASTLANE = ROOT / "fastlane" / "metadata" / "android"

FAILS: list[str] = []
WARNS: list[str] = []
PASSES: list[str] = []


def ok(msg: str) -> None:
    PASSES.append(msg)
    print(f"  PASS  {msg}")


def fail(msg: str) -> None:
    FAILS.append(msg)
    print(f"  FAIL  {msg}")


def warn(msg: str) -> None:
    WARNS.append(msg)
    print(f"  WARN  {msg}")


def section(title: str) -> None:
    print(f"\n\033[1m{title}\033[0m")


def sh(*args: str) -> tuple[int, str]:
    try:
        p = subprocess.run(args, cwd=ROOT, capture_output=True, text=True)
        return p.returncode, p.stdout.strip()
    except FileNotFoundError:
        return 127, ""


def read(path: Path) -> str:
    try:
        return path.read_text(encoding="utf-8")
    except FileNotFoundError:
        return ""


def env_from_workflow(name: str) -> str | None:
    """取 build.yml 顶层 env: 块里的常量（只支持 `KEY: 'value'` 这种写法）。"""
    m = re.search(
        rf"^  {re.escape(name)}:\s*'?\"?'?([^'\"\n#]+)", read(WORKFLOW), re.M
    )
    return m.group(1).strip() if m else None


def pubspec_version() -> tuple[str, int] | None:
    m = re.search(r"^version:\s*(\d[\w.\-]*)\+(\d+)", read(PUBSPEC), re.M)
    return (m.group(1), int(m.group(2))) if m else None


# ---------------------------------------------------------------- 配方解析
def load_recipe():
    try:
        import yaml  # type: ignore
    except ImportError:
        warn("没有 PyYAML，跳过配方结构检查（pip install pyyaml 后重跑）")
        return None
    try:
        return yaml.safe_load(FDROID.read_text(encoding="utf-8"))
    except Exception as e:  # noqa: BLE001 - 报错本身就是结论
        fail(f".fdroid.yml 解析失败：{e}")
        return None


# ---------------------------------------------------------------- 检查项
def check_recipe(recipe: dict) -> None:
    section("配方 .fdroid.yml")
    builds = recipe.get("Builds") or []
    if not builds:
        fail("Builds 为空")
        return

    for b in builds:
        vn, vc = b.get("versionName"), b.get("versionCode")
        commit = str(b.get("commit", ""))
        label = f"{vn}({vc})"
        for key in ("versionName", "versionCode", "commit", "output"):
            if key not in b:
                fail(f"Build {label} 缺字段 {key}")
        if not re.fullmatch(r"[0-9a-f]{40}", commit):
            fail(f"Build {label} 的 commit 不是 40 位完整 sha：{commit!r}")
            continue
        rc, t = sh("git", "cat-file", "-t", commit)
        if rc != 0 or t != "commit":
            fail(
                f"Build {label} 的 commit {commit[:9]} 在仓库里不存在——"
                "多半是 history rewrite 后的悬空对象，builder 会直接 checkout 失败"
            )
            continue
        ok(f"Build {label} commit {commit[:9]} 存在")
        rc, refs = sh("git", "for-each-ref", f"--contains={commit}",
                      "--format=%(refname)", "refs/remotes/origin/")
        if rc != 0 or not refs:
            fail(f"Build {label} 的 commit 不在 origin 的已发布分支上（builder 拉不到）")
        rc, source = sh("git", "show", f"{commit}:android/app/build.gradle.kts")
        if rc != 0 or "FILEINFRA_UNSIGNED_RELEASE" not in source:
            fail(f"Build {label} 的固定源码不支持 FILEINFRA_UNSIGNED_RELEASE；仅修改配方不够")
        rc, pinned_pubspec = sh("git", "show", f"{commit}:pubspec.yaml")
        pinned_version = re.search(
            r"^version:\s*(\d[\w.\-]*)\+(\d+)", pinned_pubspec, re.M
        ) if rc == 0 else None
        if not pinned_version:
            fail(f"Build {label} 的固定源码版本无法从 pubspec.yaml 读取")
        elif (pinned_version.group(1), int(pinned_version.group(2))) != (str(vn), vc):
            fail(
                f"Build {label} 的固定源码版本为 "
                f"{pinned_version.group(1)}+{pinned_version.group(2)}，与配方不一致"
            )
        else:
            ok(f"Build {label} 固定源码版本一致")

    codes = [int(b["versionCode"]) for b in builds if b.get("versionCode")]
    if codes != sorted(codes):
        fail(f"versionCode 不是递增顺序：{codes}")
    else:
        ok(f"versionCode 递增：{codes}")

    latest = builds[-1]
    pv = pubspec_version()
    if not pv:
        fail("pubspec.yaml 里读不到 version:")
    else:
        name, code = pv
        if str(latest.get("versionName")) != name:
            fail(f"最新 Build versionName={latest.get('versionName')} ≠ pubspec {name}")
        if int(latest.get("versionCode", -1)) != code:
            fail(f"最新 Build versionCode={latest.get('versionCode')} ≠ pubspec +{code}")
        if str(recipe.get("CurrentVersion")) != name or int(
            recipe.get("CurrentVersionCode", -1)
        ) != code:
            fail(
                f"CurrentVersion/Code ({recipe.get('CurrentVersion')}/"
                f"{recipe.get('CurrentVersionCode')}) ≠ pubspec {name}+{code}"
            )
        if str(latest.get("versionCode")) <= str(
            recipe.get("CurrentVersionCode", "")
        ) and str(latest.get("versionCode")) != str(recipe.get("CurrentVersionCode")):
            fail("CurrentVersionCode 应指向最新一个 Build")
        else:
            ok(f"版本三元组一致：{name}+{code}")

        # Flutter 默认读取 pubspec 的版本。只有显式覆盖时才检查覆盖值。
        build_cmds = "\n".join(latest.get("build") or [])
        m = re.search(r"--build-name=([\w.\-]+)", build_cmds)
        n = re.search(r"--build-number=(\d+)", build_cmds)
        if not m and not n:
            ok("Flutter 从 pubspec.yaml 读取版本")
        elif not m or not n:
            fail("显式覆盖版本时必须同时指定 --build-name/--build-number")
        elif m.group(1) != name or int(n.group(1)) != code:
            fail(
                f"--build-name={m.group(1)} --build-number={n.group(1)} "
                f"与 pubspec {name}+{code} 不符"
            )
        else:
            ok("--build-name/--build-number 与 pubspec 一致")

    build_cmds = "\n".join(latest.get("build") or [])
    if not re.search(r"\bFILEINFRA_UNSIGNED_RELEASE=1\b", build_cmds):
        fail("build: 必须显式设置 FILEINFRA_UNSIGNED_RELEASE=1 供 F-Droid 签名")
    else:
        ok("F-Droid 构建显式禁用开发者签名")

    keys = recipe.get("AllowedAPKSigningKeys")
    if keys:
        if not recipe.get("Binaries"):
            fail("AllowedAPKSigningKeys 需要 Binaries 上游 APK 配合可复现构建；公钥不能代替签名私钥")
        if not isinstance(keys, list):
            keys = [keys]
        if all(re.fullmatch(r"[0-9a-fA-F]{64}", str(key)) for key in keys):
            ok("AllowedAPKSigningKeys 格式正确")
        else:
            fail("AllowedAPKSigningKeys 必须是 sha256 指纹或其列表")
    else:
        ok("使用 F-Droid 默认签名（与开发者 APK 不同）")

    data = str(recipe.get("UpdateCheckData", "")).split("|")
    if len(data) != 4:
        fail("UpdateCheckData 必须明确指定 pubspec.yaml 的版本名/版本号提取规则")
    elif pv:
        code_file, code_pattern, name_file, name_pattern = data
        if name_file == ".":
            name_file = code_file
        try:
            code_match = re.search(code_pattern, read(ROOT / code_file), re.M)
            name_match = re.search(name_pattern, read(ROOT / name_file), re.M)
            extracted = (
                name_match.group(1) if name_match else None,
                int(code_match.group(1)) if code_match else None,
            )
        except (re.error, IndexError, ValueError) as e:
            fail(f"UpdateCheckData 提取失败：{e}")
        else:
            if extracted != pv:
                fail(f"UpdateCheckData 提取 {extracted} ≠ pubspec {pv}")
            else:
                ok("UpdateCheckData 正确提取 pubspec 版本")

    if recipe.get("AutoUpdateMode") != "Version":
        warn(f"AutoUpdateMode={recipe.get('AutoUpdateMode')}（建议 Version）")
    if recipe.get("UpdateCheckMode") != "Tags":
        warn(f"UpdateCheckMode={recipe.get('UpdateCheckMode')}（建议 Tags）")
    if recipe.get("License") != "MIT":
        warn(f"License={recipe.get('License')}，需与 LICENSE 和 F-Droid 侧记录一致")


def check_drift(recipe: dict) -> None:
    section("配方 ↔ CI 漂移")
    if not recipe:
        return
    latest = (recipe.get("Builds") or [{}])[-1]

    fv = env_from_workflow("FLUTTER_VERSION")
    src = next(
        (s for s in (latest.get("srclibs") or []) if str(s).startswith("flutter@")),
        None,
    )
    if not fv:
        warn("CI 里读不到 FLUTTER_VERSION")
    elif not src:
        fail("srclibs 里没有 flutter@")
    elif src.split("@", 1)[1] != fv:
        fail(f"srclibs {src} ≠ CI FLUTTER_VERSION {fv}（builder 会用未测过的工具链出包）")
    else:
        ok(f"flutter 版本对齐：{src}")

    ndk_ci = env_from_workflow("EXPECTED_NDK_MAJOR")
    ndk_rec = str(latest.get("ndk", ""))
    m = re.match(r"r(\d+)", ndk_rec)
    if not ndk_ci:
        warn("CI 里读不到 EXPECTED_NDK_MAJOR")
    elif not m:
        fail(f"ndk 字段格式不对：{ndk_rec!r}")
    elif m.group(1) != ndk_ci:
        fail(f"ndk {ndk_rec} ≠ CI EXPECTED_NDK_MAJOR r{ndk_ci}")
    else:
        ok(f"NDK 对齐：{ndk_rec}")

    prebuild = "\n".join(latest.get("prebuild") or [])
    rust_ci = env_from_workflow("RUST_VERSION")
    rust_recipe = re.search(r"--default-toolchain\s+([\d.]+)", prebuild)
    if not rust_ci:
        fail("CI 必须显式固定 RUST_VERSION")
    elif not rust_recipe or rust_recipe.group(1) != rust_ci:
        fail(f"Rust 配方版本与 CI RUST_VERSION={rust_ci} 不一致")
    else:
        ok(f"Rust 版本对齐：{rust_ci}")

    missing = [
        abi
        for abi in ("android-arm64", "android-arm", "android-x86_64")
        if f"build_dufs.sh {abi}" not in prebuild
    ]
    if missing:
        fail(
            "prebuild 没编这些 ABI 的 libdufs.so："
            f"{', '.join(missing)} —— universal APK 里对应设备会「服务组件缺失」"
        )
    else:
        ok("三个 ABI 的 libdufs.so 都在 prebuild 里")

    # dufs pin 必须在 build_dufs.sh 里，配方不该自己另写一套版本
    pin = re.search(
        r'^DUFS_VERSION="([^"]+)"', read(ROOT / "scripts" / "build_dufs.sh"), re.M
    )
    if pin:
        ok(f"dufs pin：{pin.group(1)}（由 scripts/build_dufs.sh 单点维护）")
    else:
        fail("scripts/build_dufs.sh 里找不到 DUFS_VERSION")


def check_no_binaries() -> None:
    section("仓库内容")
    rc, out = sh("git", "ls-files")
    if rc != 0:
        warn("git ls-files 失败，跳过二进制扫描")
        return
    files = out.splitlines()
    bad = [
        f
        for f in files
        if re.search(r"\.(so|dll|dylib|apk|aab|jar|war|zip|tar\.gz|7z|exe)$", f)
    ]
    if bad:
        fail("仓库里有 tracked 二进制（F-Droid 会按 NonFreeAssets/PrebuiltLibs 拒）：")
        for f in bad:
            print(f"        {f}")
    else:
        ok(f"无 tracked 二进制（共 {len(files)} 个 tracked 文件）")

    stale = [f for f in files if re.search(r"dufshub", f, re.I)]
    if stale:
        warn(f"文件名里还有旧品牌 DufsHub：{stale}")
    else:
        ok("文件名无 DufsHub 残留")


def check_fastlane(recipe: dict) -> None:
    section("fastlane 元数据")
    pv = pubspec_version()
    code = str(pv[1]) if pv else ""
    locales = sorted(p.name for p in FASTLANE.iterdir() if p.is_dir()) if FASTLANE.is_dir() else []
    if not locales:
        fail("没有 fastlane/metadata/android —— F-Droid 列表页会缺图标/截图/文案")
        return
    if "en-US" not in locales:
        fail("缺 en-US（F-Droid 的默认回退语言）")
    ok(f"语言目录：{', '.join(locales)}")

    en = FASTLANE / "en-US"
    for f in ("title.txt", "short_description.txt", "full_description.txt", "icon.png"):
        p = en / f
        if not p.exists():
            fail(f"en-US/{f} 缺失")
            continue
        if f == "icon.png" and p.stat().st_size < 1024:
            warn("en-US/icon.png 小得可疑")
    shots = list((en / "phoneScreenshots").glob("*")) if (en / "phoneScreenshots").is_dir() else []
    if not shots:
        fail("en-US/phoneScreenshots 为空（F-Droid 列表页必须有截图）")
    else:
        ok(f"截图 {len(shots)} 张")
        named = [s.name for s in shots if re.search(r"dufshub", s.name, re.I)]
        if named:
            warn(f"截图文件名还是旧品牌（内容也可能是旧版 UI）：{named}")

    short = read(en / "short_description.txt").strip()
    if len(short) > 80:
        fail(f"short_description {len(short)} 字符，超过 F-Droid 的 80 上限")
    elif short:
        ok(f"short_description {len(short)} 字符")

    title = read(en / "title.txt").strip()
    if recipe and title != recipe.get("AutoName"):
        fail(f"fastlane title「{title}」≠ AutoName「{recipe.get('AutoName')}」")
    elif title:
        ok(f"title 与 AutoName 一致：{title}")

    if code:
        cl = en / "changelogs" / f"{code}.txt"
        if not cl.exists():
            fail(f"缺 en-US/changelogs/{code}.txt（当前 versionCode 的更新说明）")
        else:
            ok(f"changelogs/{code}.txt 存在")
        if "zh-CN" not in locales:
            warn("只有 en-US：中文用户在 F-Droid 上看到的是英文文案")


def check_license(recipe: dict) -> None:
    section("许可证")
    lic = read(ROOT / "LICENSE")
    if not lic:
        fail("仓库根目录没有 LICENSE")
        return
    head = lic.splitlines()[0]
    if "MIT" not in head:
        fail(f"LICENSE 首行不像 MIT：{head!r}")
    else:
        ok("LICENSE 是 MIT")
    pub = re.search(r"^license:\s*(\S+)", read(PUBSPEC), re.M)
    if not pub:
        warn("pubspec.yaml 没写 license: 字段")
    elif recipe and pub.group(1) != recipe.get("License"):
        fail(f"pubspec license={pub.group(1)} ≠ 配方 License={recipe.get('License')}")
    else:
        ok("pubspec 与配方许可证一致")


def check_minsdk() -> None:
    section("Android 配置")
    gradle = read(ROOT / "android" / "app" / "build.gradle.kts")
    m = re.search(r"minSdk\s*=\s*(.+)", gradle)
    if not m:
        warn("build.gradle.kts 里没有 minSdk 行")
    elif "flutter.minSdkVersion" in m.group(1):
        ok(f"minSdk 跟随 Flutter 默认（当前 24）：{m.group(1).strip()}")
    else:
        warn(f"minSdk 被显式覆盖为 {m.group(1).strip()}，确认 F-Droid builder 支持")
    perms = re.findall(
        r'uses-permission android:name="android\.permission\.([A-Z_]+)"',
        read(ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"),
    )
    removed = re.findall(
        r'uses-permission android:name="android\.permission\.([A-Z_]+)"[^>]*tools:node="remove"',
        read(ROOT / "android" / "app" / "src" / "main" / "AndroidManifest.xml"),
    )
    ok(f"自有清单声明 {len(set(perms))} 个权限；显式剥掉 {sorted(set(removed)) or '无'}")
    if "MANAGE_EXTERNAL_STORAGE" in perms:
        warn(
            "MANAGE_EXTERNAL_STORAGE 在 F-Droid 上属于需要逐案说明的权限"
            "（AllFilesAccess 反特性风险）——见 docs/fdroid-prep.md"
        )


def main() -> int:
    if any(a in ("-h", "--help") for a in sys.argv[1:]):
        print(__doc__)
        return 0

    if not FDROID.exists():
        print("找不到 .fdroid.yml", file=sys.stderr)
        return 2
    if not (ROOT / ".git").exists():
        warn("不在 git 仓库里，commit 可达性检查会失真")

    recipe = load_recipe()
    if recipe:
        check_recipe(recipe)
        check_drift(recipe)
        check_fastlane(recipe)
        check_license(recipe)
    check_no_binaries()
    check_minsdk()

    print(f"\n{'=' * 60}")
    print(f"PASS {len(PASSES)}  WARN {len(WARNS)}  FAIL {len(FAILS)}")
    if FAILS:
        print("\n必须先修：")
        for f in FAILS:
            print(f"  ✗ {f}")
    if WARNS:
        print("\n建议处理：")
        for w in WARNS:
            print(f"  ! {w}")
    if not FAILS and not WARNS:
        print("全部通过。")
    print(
        "\n注意：这只覆盖本地能查的部分。真正的构建验证要在 F-Droid 的"
        " docker builder 里跑一次，见 docs/fdroid-prep.md。"
    )
    return 1 if FAILS else 0


if __name__ == "__main__":
    sys.exit(main())
