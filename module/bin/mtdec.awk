# mtdec.awk -- AES-128-CBC 解密 (纯算术实现, 不依赖任何 awk 扩展)
#
# 与 mtaes.awk 同理: 不用 xor()/and()/lshift()/rshift(), 任何 awk 都能跑。
#
# 性能优化: InvMixColumns 需要 9*a / 11*a / 13*a / 14*a,
# 启动时用 256 项查表算好, 避免每个字节都跑一遍 GF 乘法。
#
# INPUT : 十六进制文本 (stdin)
# OUTPUT: 十六进制文本 (stdout), 已去掉 PKCS#7 填充
#
# KEY/IV 固定为小米 mi_thermald 的硬编码值:
#   key = iv = "thermalopenssl.h"

# ---- 纯算术位运算 --------------------------------------------------------
# 4 位查表版异或 (比逐位循环快 10 倍)
function bxor(a, b) {
    return XT4[a % 16, b % 16] + XT4[int(a / 16), int(b / 16)] * 16
}

function xtime(a) {
    t = (a * 2) % 256
    if (a >= 128) t = bxor(t, 27)
    return t
}

# GF(2^8) 通用乘法 (只用于建表, 运行时走查表)
function gmul(a, b,   p, i) {
    p = 0
    for (i = 0; i < 8; i++) {
        if (b % 2) p = bxor(p, a)
        a = xtime(a)
        b = int(b / 2)
    }
    return p
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
            tt = t0; t0 = t1; t1 = t2; t2 = t3; t3 = tt
            t0 = SB[t0]; t1 = SB[t1]; t2 = SB[t2]; t3 = SB[t3]
            t0 = bxor(t0, rc)
            rc = xtime(rc)
        }
        W[i * 4]     = bxor(W[(i - 4) * 4],     t0)
        W[i * 4 + 1] = bxor(W[(i - 4) * 4 + 1], t1)
        W[i * 4 + 2] = bxor(W[(i - 4) * 4 + 2], t2)
        W[i * 4 + 3] = bxor(W[(i - 4) * 4 + 3], t3)
    }
}

# in: 16 字节密文 IN[]  ->  out: 16 字节明文 (未去 CBC 异或) OUT[]
function decrypt_block(   i, r, c, rr, a0, a1, a2, a3) {
    for (i = 0; i < 16; i++) S[i] = bxor(IN[i], W[160 + i])        # AddRoundKey(10)

    for (r = 10; r >= 1; r--) {
        for (i = 0; i < 16; i++) S2[i] = S[i]
        for (c = 0; c < 4; c++)
            for (rr = 0; rr < 4; rr++)
                S[rr + 4 * c] = S2[rr + 4 * ((c - rr + 4) % 4)]    # InvShiftRows

        for (i = 0; i < 16; i++) S[i] = ISB[S[i]]                  # InvSubBytes

        for (i = 0; i < 16; i++) S[i] = bxor(S[i], W[(r - 1) * 16 + i])  # AddRoundKey(r-1)

        if (r != 1) {                                             # InvMixColumns
            # 逆矩阵:
            #   b0 = 14*a0 ^ 11*a1 ^ 13*a2 ^  9*a3
            #   b1 =  9*a0 ^ 14*a1 ^ 11*a2 ^ 13*a3
            #   b2 = 13*a0 ^  9*a1 ^ 14*a2 ^ 11*a3
            #   b3 = 11*a0 ^ 13*a1 ^  9*a2 ^ 14*a3
            for (c = 0; c < 4; c++) {
                a0 = S[4 * c]; a1 = S[4 * c + 1]
                a2 = S[4 * c + 2]; a3 = S[4 * c + 3]
                S[4 * c]     = bxor(M14[a0], bxor(M11[a1], bxor(M13[a2], M9[a3])))
                S[4 * c + 1] = bxor(M9[a0],  bxor(M14[a1], bxor(M11[a2], M13[a3])))
                S[4 * c + 2] = bxor(M13[a0], bxor(M9[a1],  bxor(M14[a2], M11[a3])))
                S[4 * c + 3] = bxor(M11[a0], bxor(M13[a1], bxor(M9[a2],  M14[a3])))
            }
        }
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

    ISBOX = "52096ad53036a538bf40a39e81f3d7fb7ce339829b2fff87348e4344c4dee9cb547b9432a6c2233dee4c950b42fac34e082ea16628d924b2765ba2496d8bd12572f8f66486689816d4a45ccc5d65b6926c704850fdedb9da5e154657a78d9d8490d8ab008cbcd30af7e45805b8b34506d02c1e8fca3f0f02c1afbd0301138a6b3a9111414f67dcea97f2cfcef0b4e67396ac7422e7ad3585e2f937e81c75df6e47f11a711d29c5896fb7620eaa18be1bfc563e4bc6d279209adbc0fe78cd5af41fdda8338807c731b11210592780ec5f60517fa919b54a0d2de57a9f93c99cefa0e03b4dae2af5b0c8ebbb3c83539961172b047eba77d626e169146355210c7d"
    for (i = 0; i < 256; i++) ISB[i] = h2d(substr(ISBOX, i * 2 + 1, 2))
    SBOX = "637c777bf26b6fc53001672bfed7ab76ca82c97dfa5947f0add4a2af9ca472c0b7fd9326363ff7cc34a5e5f171d8311504c723c31896059a071280e2eb27b27509832c1a1b6e5aa0523bd6b329e32f8453d100ed20fcb15b6acbbe394a4c58cfd0efaafb434d338545f9027f503c9fa851a3408f929d38f5bcb6da2110fff3d2cd0c13ec5f974417c4a77e3d645d197360814fdc222a908846eeb814de5e0bdbe0323a0a4906245cc2d3ac629195e479e7c8376d8dd54ea96c56f4ea657aae08ba78252e1ca6b4c6e8dd741f4bbd8b8a703eb5664803f60e613557b986c11d9ee1f8981169d98e949b1e87e9ce5528df8ca1890dbfe6426841992d0fb054bb16"
    for (i = 0; i < 256; i++) SB[i] = h2d(substr(SBOX, i * 2 + 1, 2))

    # GF 乘法查表 (InvMixColumns 用)
    for (i = 0; i < 256; i++) {
        M9[i]  = gmul(i, 9)
        M11[i] = gmul(i, 11)
        M13[i] = gmul(i, 13)
        M14[i] = gmul(i, 14)
    }

    KEYHEX = "746865726d616c6f70656e73736c2e68"
    for (i = 0; i < 16; i++) {
        K[i] = h2d(substr(KEYHEX, i * 2 + 1, 2))
        PREV[i] = K[i]
    }
    keyexpand()
    hex = ""
}

{ hex = hex $0 }

END {
    gsub(/[^0-9A-Fa-f]/, "", hex)
    n = int(length(hex) / 2)
    if (n == 0) exit 0
    nblk = int(n / 16)
    hex = substr(hex, 1, nblk * 32)

    res = ""
    for (b = 0; b < nblk; b++) {
        for (i = 0; i < 16; i++) IN[i] = h2d(substr(hex, (b * 16 + i) * 2 + 1, 2))
        decrypt_block()
        for (i = 0; i < 16; i++) OUT[i] = bxor(OUT[i], PREV[i])
        for (i = 0; i < 16; i++) PREV[i] = IN[i]
        for (i = 0; i < 16; i++) res = res sprintf("%02x", OUT[i])
    }

    # 去掉 PKCS#7 填充
    if (length(res) >= 2) {
        pad = h2d(substr(res, length(res) - 1, 2))
        if (pad >= 1 && pad <= 16 && pad * 2 <= length(res)) {
            ph = ""
            for (i = 0; i < pad; i++) ph = ph sprintf("%02x", pad)
            if (substr(res, length(res) - pad * 2 + 1) == ph)
                res = substr(res, 1, length(res) - pad * 2)
        }
    }
    for (i = 1; i <= length(res); i += 32) print substr(res, i, 32)
}
