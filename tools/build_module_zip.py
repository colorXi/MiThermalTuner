#!/usr/bin/env python3
"""
build_module_zip.py -- 打包 Magisk 模块 (可直接在 Magisk App 里安装的 zip)

用法:
    python tools/build_module_zip.py
输出:
    dist/MiThermalTuner.zip
"""
import argparse
import os
import shutil
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
MODULE = os.path.join(ROOT, "module")

# Magisk 会执行这些脚本, 必须是 0755
EXECUTABLE = {"service.sh", "post-fs-data.sh", "uninstall.sh", "customize.sh", "mt"}
# 这些不打包进模块 (由 CI/发布流程单独提供)
SKIP_NAMES = {"README.md", "LICENSE"}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "dist", "MiThermalTuner.zip"))
    ap.add_argument("--apk", default=os.path.join(ROOT, "MiThermal.apk"),
                    help="把构建好的 APK 一并塞进模块 (module/app/MiThermal.apk)")
    args = ap.parse_args()

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    if os.path.exists(args.out):
        os.remove(args.out)

    # 把 APK 同步进模块目录
    if os.path.exists(args.apk):
        dst = os.path.join(MODULE, "app", "MiThermal.apk")
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        shutil.copy2(args.apk, dst)
        print("APK ->", os.path.relpath(dst, ROOT))
    else:
        print("! 没找到", os.path.relpath(args.apk, ROOT), ", 模块里将没有图形界面 App")

    n = 0
    with zipfile.ZipFile(args.out, "w", zipfile.ZIP_DEFLATED) as z:
        for root, dirs, files in os.walk(MODULE):
            dirs[:] = [d for d in dirs if d not in ("__pycache__",)]
            for f in files:
                full = os.path.join(root, f)
                rel = os.path.relpath(full, MODULE).replace("\\", "/")
                if os.path.basename(rel) in SKIP_NAMES:
                    continue
                zi = zipfile.ZipInfo(rel)
                zi.compress_type = zipfile.ZIP_DEFLATED
                mode = 0o755 if f in EXECUTABLE else 0o644
                zi.external_attr = (mode & 0xFFFF) << 16
                z.writestr(zi, open(full, "rb").read())
                n += 1

    print("built:", args.out, os.path.getsize(args.out), "bytes,", n, "files")


if __name__ == "__main__":
    main()
