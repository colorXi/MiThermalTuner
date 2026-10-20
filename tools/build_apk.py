#!/usr/bin/env python3
"""
build_apk.py -- 手工构建 MiThermal 温控面板 APK (无需 Gradle)

工具链:
  JDK   : C:\\Users\\BUFF\\AppData\\Local\\finalshell\\jre  (javac 17 + keytool)
  SDK   : C:\\Users\\BUFF\\AppData\\Local\\Android\\Sdk
  BT    : build-tools/36.0.0  (aapt2, d8, zipalign, apksigner)
  PLAT  : platforms/android-36.1/android.jar
"""
import os, shutil, subprocess, sys, zipfile, glob

BASE = r"C:\Users\BUFF\Desktop\xiaomi_thermal"
APP = os.path.join(BASE, "app")
OUT = os.path.join(BASE, "app", "build")
APK = os.path.join(BASE, "MiThermal.apk")
KEYSTORE = os.path.join(BASE, "app", "mithermal.keystore")

JDK = r"C:\Users\BUFF\AppData\Local\finalshell\jre"
SDK = r"C:\Users\BUFF\AppData\Local\Android\Sdk"
BT = os.path.join(SDK, "build-tools", "36.0.0")
ANDROID_JAR = os.path.join(SDK, "platforms", "android-36.1", "android.jar")

JAVAC = os.path.join(JDK, "bin", "javac.exe")
KEYTOOL = os.path.join(JDK, "bin", "keytool.exe")
AAPT2 = os.path.join(BT, "aapt2.exe")
D8 = os.path.join(BT, "d8.bat")
ZIPALIGN = os.path.join(BT, "zipalign.exe")
APKSIGNER = os.path.join(BT, "apksigner.bat")

ENV = dict(os.environ)
ENV["JAVA_HOME"] = JDK
ENV["PATH"] = os.path.join(JDK, "bin") + os.pathsep + ENV.get("PATH", "")


def run(cmd, cwd=None, echo=True):
    if echo:
        print("  $", " ".join(str(c) for c in cmd[:6]), "..." if len(cmd) > 6 else "")
    r = subprocess.run(cmd, cwd=cwd, env=ENV, capture_output=True, text=True)
    if r.returncode != 0:
        print(r.stdout)
        print(r.stderr)
        raise SystemExit("FAILED: " + " ".join(str(c) for c in cmd[:3]))
    return r.stdout


def extract_android_jar():
    """这个精简版 JDK 读不了 jar 里的 class (缺 jar 工具/zip 支持异常),
    因此把 android.jar 解压成目录, javac/d8 直接读散装 .class。"""
    dst = os.path.join(OUT, "androidcp")
    if os.path.isdir(dst) and os.listdir(dst):
        return dst
    import zipfile
    with zipfile.ZipFile(ANDROID_JAR) as z:
        z.extractall(dst)
    return dst


def main():
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    for d in ("gen", "classes", "dex"):
        os.makedirs(os.path.join(OUT, d), exist_ok=True)

    print("[0/7] 解压 android.jar -> 目录")
    CP = extract_android_jar()

    # 1) 编译资源
    print("[1/7] aapt2 compile res")
    run([AAPT2, "compile", "--dir", os.path.join(APP, "res"), "-o", os.path.join(OUT, "res.zip")])

    # 2) 链接资源 + 生成 R.java
    print("[2/7] aapt2 link")
    run([AAPT2, "link", "-o", os.path.join(OUT, "base.apk"),
         "-I", ANDROID_JAR,
         "--manifest", os.path.join(APP, "AndroidManifest.xml"),
         "--java", os.path.join(OUT, "gen"),
         "--min-sdk-version", "26", "--target-sdk-version", "33",
         "--auto-add-overlay",
         os.path.join(OUT, "res.zip")])

    # 3) javac
    print("[3/7] javac")
    srcs = glob.glob(os.path.join(APP, "java", "**", "*.java"), recursive=True)
    srcs += glob.glob(os.path.join(OUT, "gen", "**", "*.java"), recursive=True)
    run([JAVAC, "-source", "8", "-target", "8", "-encoding", "UTF-8", "-nowarn",
         "-classpath", CP,
         "-d", os.path.join(OUT, "classes")] + srcs)

    # 4) d8
    print("[4/7] d8")
    classes = glob.glob(os.path.join(OUT, "classes", "**", "*.class"), recursive=True)
    run([D8, "--release", "--min-api", "26", "--lib", CP,
         "--output", os.path.join(OUT, "dex")] + classes)

    # 5) 把 assets + classes.dex 塞进 base.apk
    print("[5/7] pack apk")
    with zipfile.ZipFile(os.path.join(OUT, "base.apk"), "a", zipfile.ZIP_DEFLATED) as z:
        for f in glob.glob(os.path.join(OUT, "dex", "*.dex")):
            z.write(f, "classes.dex")
        assets = os.path.join(APP, "assets")
        for root, _, files in os.walk(assets):
            for f in files:
                full = os.path.join(root, f)
                z.write(full, "assets/" + os.path.relpath(full, assets).replace("\\", "/"))

    # 6) zipalign
    print("[6/7] zipalign")
    run([ZIPALIGN, "-f", "-p", "4", os.path.join(OUT, "base.apk"), os.path.join(OUT, "aligned.apk")])

    # 7) 签名
    print("[7/7] apksigner")
    if not os.path.exists(KEYSTORE):
        run([KEYTOOL, "-genkeypair", "-v", "-keystore", KEYSTORE, "-storepass", "android",
             "-alias", "mithermal", "-keypass", "android", "-keyalg", "RSA", "-keysize", "2048",
             "-validity", "10000", "-dname", "CN=MiThermal, OU=Dev, O=OpenCode, L=NA, S=NA, C=CN"])
    run([APKSIGNER, "sign", "--ks", KEYSTORE, "--ks-pass", "pass:android",
         "--key-pass", "pass:android", "--ks-key-alias", "mithermal",
         "--out", APK, os.path.join(OUT, "aligned.apk")])
    run([APKSIGNER, "verify", "--print-certs", APK], echo=False)

    print("\nAPK:", APK, os.path.getsize(APK), "bytes")


if __name__ == "__main__":
    main()
