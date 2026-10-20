#!/usr/bin/env python3
"""
build_apk.py -- 手工构建 MiThermal 温控面板 APK (无需 Gradle)

工具链要求:
  JDK 17+      : 设置环境变量 JAVA_HOME, 或让 javac 在 PATH 里
  Android SDK  : 设置 ANDROID_HOME / ANDROID_SDK_ROOT, 需要
                 - build-tools/<ver>   (aapt2, d8, zipalign, apksigner)
                 - platforms/android-XX/android.jar

用法:
    python tools/build_apk.py
    python tools/build_apk.py --sdk /opt/android-sdk --jdk /usr/lib/jvm/jdk-17
    python tools/build_apk.py --out MiThermal.apk
"""
import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
import zipfile

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
APP = os.path.join(ROOT, "app")
OUT = os.path.join(ROOT, "build")
APK = os.path.join(ROOT, "MiThermal.apk")
KEYSTORE = os.path.join(APP, "mithermal.keystore")
KEY_ALIAS = "mithermal"
KEY_PASS = "android"

IS_WIN = os.name == "nt"


def exe(name):
    """按平台给出可执行文件后缀"""
    if IS_WIN:
        return name + ".exe"
    return name


def bat(name):
    if IS_WIN:
        return name + ".bat"
    return name


def version_key(s):
    """把 'android-36.1' / '36.0.0' 变成可比较的元组"""
    parts = []
    for chunk in re.split(r"[._-]", s):
        parts.append((1, int(chunk)) if chunk.isdigit() else (0, 0))
    return parts


def find_sdk(explicit=None):
    cands = []
    if explicit:
        cands.append(explicit)
    for k in ("ANDROID_HOME", "ANDROID_SDK_ROOT", "ANDROID_SDK"):
        v = os.environ.get(k)
        if v:
            cands.append(v)
    for v in cands:
        if v and os.path.isdir(os.path.join(v, "platforms")):
            return v
    # 常见安装位置
    home = os.path.expanduser("~")
    guesses = [
        os.path.join(home, "Android", "Sdk"),
        os.path.join(home, "AppData", "Local", "Android", "Sdk"),
        os.path.join(home, "Library", "Android", "sdk"),
        "/usr/local/lib/android/sdk",
        "/opt/android-sdk",
    ]
    for v in guesses:
        if os.path.isdir(os.path.join(v, "platforms")):
            return v
    raise SystemExit("找不到 Android SDK, 请设置 ANDROID_HOME 或用 --sdk 指定")


def find_jdk(explicit=None):
    cands = []
    if explicit:
        cands.append(explicit)
    v = os.environ.get("JAVA_HOME")
    if v:
        cands.append(v)
    # 某些软件自带的精简 JDK
    cands.append(os.path.expanduser("~/AppData/Local/finalshell/jre"))
    cands.append("/usr/lib/jvm/temurin-17-jdk-amd64")
    for v in cands:
        if v and os.path.isdir(os.path.join(v, "bin")) and \
                os.path.exists(os.path.join(v, "bin", exe("javac"))):
            return v
    # PATH 里的 javac
    found = shutil.which("javac")
    if found:
        return os.path.dirname(os.path.dirname(found))
    raise SystemExit("找不到 JDK, 请设置 JAVA_HOME 或用 --jdk 指定")


def pick_build_tools(sdk):
    bt = os.path.join(sdk, "build-tools")
    if not os.path.isdir(bt):
        raise SystemExit("SDK 里没有 build-tools: " + bt)
    vers = sorted([d for d in os.listdir(bt) if os.path.isdir(os.path.join(bt, d))],
                  key=version_key, reverse=True)
    if not vers:
        raise SystemExit("build-tools 是空的")
    return os.path.join(bt, vers[0])


def pick_platform(sdk):
    pf = os.path.join(sdk, "platforms")
    vers = sorted([d for d in os.listdir(pf) if os.path.isdir(os.path.join(pf, d))],
                  key=version_key, reverse=True)
    for v in vers:
        jar = os.path.join(pf, v, "android.jar")
        if os.path.exists(jar):
            return jar
    raise SystemExit("platforms 下没有可用的 android.jar")


def run(cmd, cwd=None, env=None, echo=True):
    if echo:
        print("  $", " ".join(str(c) for c in cmd[:5]), "..." if len(cmd) > 5 else "")
    r = subprocess.run(cmd, cwd=cwd, env=env, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout or "")
        print(r.stderr or "")
        raise SystemExit("FAILED: " + " ".join(str(c) for c in cmd[:3]))
    return r.stdout


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sdk", default=None)
    ap.add_argument("--jdk", default=None)
    ap.add_argument("--out", default=APK)
    args = ap.parse_args()

    sdk = find_sdk(args.sdk)
    jdk = find_jdk(args.jdk)
    bt = pick_build_tools(sdk)
    android_jar = pick_platform(sdk)

    javac = os.path.join(jdk, "bin", exe("javac"))
    keytool = os.path.join(jdk, "bin", exe("keytool"))
    aapt2 = os.path.join(bt, exe("aapt2"))
    d8 = os.path.join(bt, bat("d8"))
    zipalign = os.path.join(bt, exe("zipalign"))
    apksigner = os.path.join(bt, bat("apksigner"))

    env = dict(os.environ)
    env["JAVA_HOME"] = jdk
    env["PATH"] = os.path.join(jdk, "bin") + os.pathsep + env.get("PATH", "")

    print("SDK     :", sdk)
    print("BT      :", bt)
    print("JDK     :", jdk)
    print("android :", android_jar)

    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    for d in ("gen", "classes", "dex"):
        os.makedirs(os.path.join(OUT, d), exist_ok=True)

    # 某些精简版 JDK 读不了 jar 里的 class (缺 jar 工具), 解压成目录更稳
    CP = os.path.join(OUT, "androidcp")
    print("[0/7] 准备 android classpath")
    with zipfile.ZipFile(android_jar) as z:
        z.extractall(CP)

    print("[1/7] aapt2 compile res")
    run([aapt2, "compile", "--dir", os.path.join(APP, "res"), "-o", os.path.join(OUT, "res.zip")], env=env)

    print("[2/7] aapt2 link")
    run([aapt2, "link", "-o", os.path.join(OUT, "base.apk"),
         "-I", android_jar,
         "--manifest", os.path.join(APP, "AndroidManifest.xml"),
         "--java", os.path.join(OUT, "gen"),
         "--min-sdk-version", "26", "--target-sdk-version", "33",
         "--auto-add-overlay",
         os.path.join(OUT, "res.zip")], env=env)

    print("[3/7] javac")
    srcs = glob.glob(os.path.join(APP, "java", "**", "*.java"), recursive=True)
    srcs += glob.glob(os.path.join(OUT, "gen", "**", "*.java"), recursive=True)
    run([javac, "-source", "8", "-target", "8", "-encoding", "UTF-8", "-nowarn",
         "-classpath", CP, "-d", os.path.join(OUT, "classes")] + srcs, env=env)

    print("[4/7] d8")
    classes = glob.glob(os.path.join(OUT, "classes", "**", "*.class"), recursive=True)
    run([d8, "--release", "--min-api", "26", "--lib", CP,
         "--output", os.path.join(OUT, "dex")] + classes, env=env)

    print("[5/7] pack apk")
    with zipfile.ZipFile(os.path.join(OUT, "base.apk"), "a", zipfile.ZIP_DEFLATED) as z:
        for f in glob.glob(os.path.join(OUT, "dex", "*.dex")):
            z.write(f, "classes.dex")
        assets = os.path.join(APP, "assets")
        for root, _, files in os.walk(assets):
            for f in files:
                full = os.path.join(root, f)
                z.write(full, "assets/" + os.path.relpath(full, assets).replace("\\", "/"))

    print("[6/7] zipalign")
    run([zipalign, "-f", "-p", "4", os.path.join(OUT, "base.apk"), os.path.join(OUT, "aligned.apk")], env=env)

    print("[7/7] apksigner")
    if not os.path.exists(KEYSTORE):
        # 注意: 已提交的 app/mithermal.keystore 为了保证签名连续性保持不变,
        # 这里只影响全新克隆时自动生成的证书。
        run([keytool, "-genkeypair", "-v", "-keystore", KEYSTORE, "-storepass", KEY_PASS,
             "-alias", KEY_ALIAS, "-keypass", KEY_PASS, "-keyalg", "RSA", "-keysize", "2048",
             "-validity", "10000",
             "-dname", "CN=MiThermal, OU=Community, O=MiThermalTuner, L=, S=, C=CN"],
            env=env)
    run([apksigner, "sign", "--ks", KEYSTORE, "--ks-pass", "pass:" + KEY_PASS,
         "--key-pass", "pass:" + KEY_PASS, "--ks-key-alias", KEY_ALIAS,
         "--out", args.out, os.path.join(OUT, "aligned.apk")], env=env)
    run([apksigner, "verify", "--print-certs", args.out], env=env, echo=False)

    print("\nAPK:", args.out, os.path.getsize(args.out), "bytes")


if __name__ == "__main__":
    main()
