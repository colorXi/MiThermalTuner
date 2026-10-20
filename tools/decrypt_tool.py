import os, glob
from Crypto.Cipher import AES

BASE = r"C:\Users\BUFF\AppData\Local\Temp\opencode"
CONF = os.path.join(BASE, "conf")
OUT  = os.path.join(BASE, "conf_dec")
os.makedirs(OUT, exist_ok=True)

KEY = b"thermalopenssl.h"
IV  = b"thermalopenssl.h"

for path in sorted(glob.glob(os.path.join(CONF, "thermal-*.conf"))):
    name = os.path.basename(path)
    ct = open(path, "rb").read()
    if len(ct) % 16 != 0:
        print(f"[SKIP-ODD] {name} len={len(ct)} (not multiple of 16)")
        continue
    out = AES.new(KEY, AES.MODE_CBC, IV).decrypt(ct)
    pad = out[-1]
    if 1 <= pad <= 16 and out[-pad:] == bytes([pad]) * pad:
        out = out[:-pad]
    try:
        txt = out.decode("utf-8")
    except UnicodeDecodeError:
        print(f"[FAIL-ENC] {name}")
        continue
    open(os.path.join(OUT, name), "w", encoding="utf-8", newline="\n").write(txt)
    print(f"[OK] {name}  {len(ct)} -> {len(out)} bytes, {txt.count(chr(10))+1} lines")
