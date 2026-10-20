#!/usr/bin/env python3
"""
mt_editor.py -- PC 端温控配置编辑器 (配合 MiThermalTuner 面具模块使用)

  小米 mi_thermald 的场景配置是 AES-128-CBC 加密的
  (key = iv = b"thermalopenssl.h")，本脚本在电脑上直接加解密，
  方便批量查看/修改/回传。

用法:
  python mt_editor.py pull                拉取全部场景配置(解密)到 ./mt_conf
  python mt_editor.py show <scenario>     显示某个场景(解密)
  python mt_editor.py push <scenario> <local>   加密并推送到设备(自动重启 mi_thermald)
  python mt_editor.py pushall <dir>       批量推送目录下全部配置
  python mt_editor.py restore             移除设备上的全部覆写, 恢复原厂
  python mt_editor.py dump                导出设备当前实际生效的配置
"""
import os
import subprocess
import sys
import time

KEY = b"thermalopenssl.h"
CONF_DIR = "/vendor/etc"
APPLY_DIR = "/data/vendor/thermal/config"
DUMP = "/data/vendor/thermal/decrypt.txt"
LOCAL_DIR = "mt_conf"

try:
    from Crypto.Cipher import AES
except ImportError:
    sys.exit("缺少 pycryptodome:  pip install pycryptodome")


def adb(*args, binary=False):
    r = subprocess.run(["adb", *args], capture_output=True)
    return r.stdout if binary else r.stdout.decode("utf-8", "replace")


def adb_su(cmd):
    return adb("shell", "su", "-c", cmd, binary=True)


def decrypt(data: bytes) -> bytes:
    if len(data) % 16:
        return data  # clear-text scenario
    out = AES.new(KEY, AES.MODE_CBC, KEY).decrypt(data)
    pad = out[-1]
    if 1 <= pad <= 16 and out[-pad:] == bytes([pad]) * pad:
        out = out[:-pad]
    return out


def encrypt(data: bytes) -> bytes:
    if len(data) % 16 == 0 and not data.lstrip()[:1].isalpha():
        # heuristic: plain text configs start with '['
        pass
    pad = 16 - (len(data) % 16)
    return AES.new(KEY, AES.MODE_CBC, KEY).encrypt(data + bytes([pad]) * pad)


def is_plain(name: str) -> bool:
    data = adb_su(f"cat {CONF_DIR}/{name}")
    return len(data) % 16 != 0


def cmd_pull():
    os.makedirs(LOCAL_DIR, exist_ok=True)
    names = [n for n in adb_su(f"ls {CONF_DIR}").decode().split()
             if n.startswith("thermal-") and n.endswith(".conf")]
    for n in names:
        raw = adb_su(f"cat {CONF_DIR}/{n}")
        plain = decrypt(raw)
        with open(os.path.join(LOCAL_DIR, n), "wb") as f:
            f.write(plain)
        print(f"  {n:<28} {len(raw):>6} -> {len(plain):>6} bytes  (明文)")
    print(f"\n已保存到 ./{LOCAL_DIR}/")


def cmd_show(scenario):
    raw = adb_su(f"cat {CONF_DIR}/{scenario}")
    sys.stdout.write(decrypt(raw).decode("utf-8", "replace"))


def cmd_push(scenario, local):
    plain = open(local, "rb").read()
    blob = plain if is_plain(scenario) else encrypt(plain)
    tmp = "/data/local/tmp/_mt_push.bin"
    with open("_mt_push.bin", "wb") as f:
        f.write(blob)
    subprocess.run(["adb", "push", "_mt_push.bin", tmp], capture_output=True)
    os.remove("_mt_push.bin")
    adb_su(f"mkdir -p {APPLY_DIR}")
    adb_su(f"cp {tmp} {APPLY_DIR}/{scenario}")
    adb_su(f"chown root:system {APPLY_DIR}/{scenario}; chmod 644 {APPLY_DIR}/{scenario}")
    adb_su("setprop ctl.restart mi_thermald")
    time.sleep(3)
    print(f"已推送 {scenario} 并重启 mi_thermald")
    verify(scenario)


def cmd_pushall(d):
    for n in sorted(os.listdir(d)):
        if n.startswith("thermal-") and n.endswith(".conf"):
            cmd_push(n, os.path.join(d, n))


def verify(scenario):
    live = adb_su(f"cat {DUMP}")
    if not live:
        print("  (decrypt.txt 为空)")
        return
    local = adb_su(f"cat {APPLY_DIR}/{scenario}")
    got = decrypt(local)
    if got.strip() == live.strip():
        print("  校验通过: mi_thermald 已加载该配置")
    else:
        print("  注意: 当前生效配置与推送内容不一致 (可能加载的是其它场景)")


def cmd_restore():
    adb_su(f"rm -f {APPLY_DIR}/thermal-*.conf")
    adb_su("setprop ctl.restart mi_thermald")
    time.sleep(2)
    print("已移除全部覆写，恢复原厂配置")


def cmd_dump():
    live = adb_su(f"cat {DUMP}")
    sys.stdout.write(live.decode("utf-8", "replace"))


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(0)
    c = sys.argv[1]
    if c == "pull":
        cmd_pull()
    elif c == "show":
        cmd_show(sys.argv[2])
    elif c == "push":
        cmd_push(sys.argv[2], sys.argv[3])
    elif c == "pushall":
        cmd_pushall(sys.argv[2])
    elif c == "restore":
        cmd_restore()
    elif c == "dump":
        cmd_dump()
    else:
        print(__doc__)
