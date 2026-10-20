# mtaes.awk -- AES-128-CBC 加密 (纯算术实现, 不依赖任何 awk 扩展)
#
# 为什么要自己写位运算:
#   Android 自带的 /system/bin/awk (toybox) 没有 xor() / and() / lshift() /
#   rshift() 这些 GNU awk 扩展, 只有 Magisk 的 busybox awk 才有。
#   本模块要支持 Magisk / KernelSU / APatch 甚至无 root 环境,
#   所以这里只用四则运算实现位运算, 任何 awk 都能跑。
#
# 关键实现点:
#   1. awk 里的 ^ 是幂运算不是异或, 异或必须自己算
#   2. InvMixColumns / MixColumns 的 3*a = 2*a ^ a, 2*a 用 xtime()
#   3. 密钥扩展的 Rcon 序列同样是 GF(2^8) 乘 2
#
# INPUT : 十六进制文本 (stdin, 允许含空白)
# OUTPUT: 十六进制文本 (stdout, 每行 32 字符)
#
# KEY/IV 固定为小米 mi_thermald 的硬编码值:
#   key = iv = "thermalopenssl.h"

# ---- 纯算术位运算 --------------------------------------------------------
# 逐位循环太慢 (16 个场景加解密要十几秒), 改成 4 位查表:
# 先算好 16x16 的 4 位异或表, 之后一次 bxor 只要两次查表, 快 10 倍。
function bxor(a, b) {
    return XT4[a % 16, b % 16] + XT4[int(a / 16), int(b / 16)] * 16
}

# GF(2^8) 乘 2: (a<<1) ^ (0x1b if 高位为 1)
function xtime(a) {
    t = (a * 2) % 256
    if (a >= 128) t = bxor(t, 27)
    return t
}

function h2d(h,   i, v, c) {
    v = 0
    for (i = 1; i <= length(h); i++) {
        c = index("0123456789abcdef", tolower(substr(h, i, 1))) - 1
        v = v * 16 + c
    }
    return v
}

function keyexpand(   i, t0, t1, t2, t3, tt, rc) {
    for (i = 0; i < 16; i++) W[i] = K[i]
    rc = 1
    for (i = 4; i < 44; i++) {
        t0 = W[(i - 1) * 4]
        t1 = W[(i - 1) * 4 + 1]
        t2 = W[(i - 1) * 4 + 2]
        t3 = W[(i - 1) * 4 + 3]
        if (i % 4 == 0) {
            tt = t0; t0 = t1; t1 = t2; t2 = t3; t3 = tt      # RotWord
            t0 = SB[t0]; t1 = SB[t1]; t2 = SB[t2]; t3 = SB[t3] # SubWord
            t0 = bxor(t0, rc)                                  # Rcon
            rc = xtime(rc)
        }
        W[i * 4]     = bxor(W[(i - 4) * 4],     t0)
        W[i * 4 + 1] = bxor(W[(i - 4) * 4 + 1], t1)
        W[i * 4 + 2] = bxor(W[(i - 4) * 4 + 2], t2)
        W[i * 4 + 3] = bxor(W[(i - 4) * 4 + 3], t3)
    }
}

# in: 16 字节 (已异或过前一块密文) in T[]  ->  out: 16 字节 out OUT[]
function encrypt_block(   i, r, c, rr, a0, a1, a2, a3, m1, m2, m0) {
    for (i = 0; i < 16; i++) S[i] = bxor(T[i], W[i])              # AddRoundKey(0)

    for (r = 1; r <= 10; r++) {
        for (i = 0; i < 16; i++) S[i] = SB[S[i]]                  # SubBytes
        for (i = 0; i < 16; i++) S2[i] = S[i]
        for (c = 0; c < 4; c++)
            for (rr = 0; rr < 4; rr++)
                S[rr + 4 * c] = S2[rr + 4 * ((c + rr) % 4)]      # ShiftRows

        if (r != 10) {                                           # MixColumns
            for (c = 0; c < 4; c++) {
                a0 = S[4 * c]; a1 = S[4 * c + 1]
                a2 = S[4 * c + 2]; a3 = S[4 * c + 3]
                m1 = bxor(xtime(a1), a1)                          # 3*a1
                m2 = bxor(xtime(a2), a2)                          # 3*a2
                m0 = bxor(xtime(a0), a0)                          # 3*a0
                S[4 * c]     = bxor(xtime(a0), bxor(m1, bxor(a2, a3)))
                S[4 * c + 1] = bxor(a0, bxor(xtime(a1), bxor(m2, a3)))
                S[4 * c + 2] = bxor(a0, bxor(a1, bxor(xtime(a2), bxor(xtime(a3), a3))))
                S[4 * c + 3] = bxor(m0, bxor(a1, bxor(a2, xtime(a3))))
            }
        }
        for (i = 0; i < 16; i++) S[i] = bxor(S[i], W[r * 16 + i]) # AddRoundKey(r)
    }
    for (i = 0; i < 16; i++) OUT[i] = S[i]
}

BEGIN {
    # 4 位异或查表 (256 项)
    for (i = 0; i < 16; i++)
        for (j = 0; j < 16; j++) {
            v = 0
            for (k = 0; k < 4; k++) {
                if (int(i / (2 ^ k)) % 2 != int(j / (2 ^ k)) % 2) v += 2 ^ k
            }
            XT4[i, j] = v
        }

    SBOX = "637c777bf26b6fc53001672bfed7ab76ca82c97dfa5947f0add4a2af9ca472c0b7fd9326363ff7cc34a5e5f171d8311504c723c31896059a071280e2eb27b27509832c1a1b6e5aa0523bd6b329e32f8453d100ed20fcb15b6acbbe394a4c58cfd0efaafb434d338545f9027f503c9fa851a3408f929d38f5bcb6da2110fff3d2cd0c13ec5f974417c4a77e3d645d197360814fdc222a908846eeb814de5e0bdbe0323a0a4906245cc2d3ac629195e479e7c8376d8dd54ea96c56f4ea657aae08ba78252e1ca6b4c6e8dd741f4bbd8b8a703eb5664803f60e613557b986c11d9ee1f8981169d98e949b1e87e9ce5528df8ca1890dbfe6426841992d0fb054bb16"
    for (i = 0; i < 256; i++) SB[i] = h2d(substr(SBOX, i * 2 + 1, 2))

    KEYHEX = "746865726d616c6f70656e73736c2e68"   # "thermalopenssl.h"
    for (i = 0; i < 16; i++) {
        K[i] = h2d(substr(KEYHEX, i * 2 + 1, 2))
        PREV[i] = K[i]                             # IV == key
    }
    keyexpand()
    hex = ""
}

{ hex = hex $0 }

END {
    gsub(/[^0-9A-Fa-f]/, "", hex)
    n = int(length(hex) / 2)
    if (n == 0) exit 0
    nblk = int((n + 15) / 16)
    padlen = 16 * nblk - n
    ps = ""
    for (i = 0; i < padlen; i++) ps = ps sprintf("%02x", padlen)
    hex = hex ps

    res = ""
    for (b = 0; b < nblk; b++) {
        for (i = 0; i < 16; i++) IN[i] = h2d(substr(hex, (b * 16 + i) * 2 + 1, 2))
        for (i = 0; i < 16; i++) T[i] = bxor(IN[i], PREV[i])
        encrypt_block()
        for (i = 0; i < 16; i++) PREV[i] = OUT[i]
        for (i = 0; i < 16; i++) res = res sprintf("%02x", OUT[i])
    }
    for (i = 1; i <= length(res); i += 32) print substr(res, i, 32)
}
