#!/usr/bin/env python3
"""
make_release.py -- 生成可提交的成品包目录 releases/

把构建好的模块 zip / apk 复制到 releases/ 并生成 SHA256 校验文件,
这样用户可以直接从仓库页面下载, 不用自己编译。
"""
import hashlib
import os
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
RELEASES = os.path.join(ROOT, "releases")

VERSION = sys.argv[1] if len(sys.argv) > 1 else "v1.1.1"

MOD_ZIP = os.path.join(ROOT, "dist", "MiThermalTuner.zip")
APK = os.path.join(ROOT, "MiThermal.apk")

os.makedirs(RELEASES, exist_ok=True)

items = []
if os.path.exists(MOD_ZIP):
    dst = os.path.join(RELEASES, f"MiThermalTuner-{VERSION}.zip")
    shutil.copy2(MOD_ZIP, dst)
    items.append(dst)
if os.path.exists(APK):
    dst = os.path.join(RELEASES, f"MiThermal-{VERSION}.apk")
    shutil.copy2(APK, dst)
    items.append(dst)

lines = []
for f in sorted(items):
    h = hashlib.sha256(open(f, "rb").read()).hexdigest()
    lines.append(f"{h}  {os.path.basename(f)}")

with open(os.path.join(RELEASES, "SHA256SUMS.txt"), "w", encoding="utf-8", newline="\n") as fp:
    fp.write("\n".join(lines) + "\n")

print("releases/ 内容:")
for f in sorted(os.listdir(RELEASES)):
    print(f"   {f:<38} {os.path.getsize(os.path.join(RELEASES, f)):>8} bytes")
print("\nSHA256SUMS.txt:")
print("\n".join(lines))
