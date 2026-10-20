# mtdec.awk -- AES-128-CBC decryption implemented in POSIX/busybox awk
#
# Companion of mtaes.awk. Used by MiThermalTuner to turn Xiaomi's encrypted
# /vendor/etc/thermal-*.conf files into editable plain text.
#
# INPUT : hex text on stdin (whitespace/newlines ignored)
# OUTPUT: hex text on stdout, 32 chars per line
#
# KEY/IV are fixed to Xiaomi's mi_thermald key (both 16 bytes):
#   key = iv = "thermalopenssl.h"

function h2d(h,   i, v, c) {
    v = 0
    for (i = 1; i <= length(h); i++) {
        c = index("0123456789abcdef", tolower(substr(h, i, 1))) - 1
        v = v * 16 + c
    }
    return v
}

# GF(2^8) multiply by x (i.e. *2)
function xtime(a) {
    t = and(lshift(a, 1), 255)
    if (and(a, 128)) t = xor(t, 27)
    return t
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
            t0 = xor(t0, rc)
            rc = xtime(rc)
        }
        W[i * 4]     = xor(W[(i - 4) * 4],     t0)
        W[i * 4 + 1] = xor(W[(i - 4) * 4 + 1], t1)
        W[i * 4 + 2] = xor(W[(i - 4) * 4 + 2], t2)
        W[i * 4 + 3] = xor(W[(i - 4) * 4 + 3], t3)
    }
}

# GF(2^8) multiply, general
function gmul(a, b,   p, i) {
    p = 0
    for (i = 0; i < 8; i++) {
        if (and(b, 1)) p = xor(p, a)
        a = xtime(a)
        b = rshift(b, 1)
    }
    return p
}

# in: 16 bytes ciphertext in IN[]  ->  out: 16 bytes plaintext in OUT[]
function decrypt_block(   i, r, c, rr, a0, a1, a2, a3, m9, mb, md) {
    for (i = 0; i < 16; i++) S[i] = xor(IN[i], W[160 + i])      # AddRoundKey(10)

    for (r = 10; r >= 1; r--) {
        # InvShiftRows: row r shifted RIGHT by r
        for (i = 0; i < 16; i++) S2[i] = S[i]
        for (c = 0; c < 4; c++)
            for (rr = 0; rr < 4; rr++)
                S[rr + 4 * c] = S2[rr + 4 *((c - rr + 4) % 4)]

        for (i = 0; i < 16; i++) S[i] = ISB[S[i]]                # InvSubBytes

        for (i = 0; i < 16; i++) S[i] = xor(S[i], W[(r - 1) * 16 + i])  # AddRoundKey(r-1)

        if (r != 1) {                                            # InvMixColumns
            for (c = 0; c < 4; c++) {
                a0 = S[4 * c]; a1 = S[4 * c + 1]
                a2 = S[4 * c + 2]; a3 = S[4 * c + 3]
                S[4 * c]     = xor(gmul(a0,14), xor(gmul(a1,11), xor(gmul(a2,13), gmul(a3,9))))
                S[4 * c + 1] = xor(gmul(a0,9),  xor(gmul(a1,14), xor(gmul(a2,11), gmul(a3,13))))
                S[4 * c + 2] = xor(gmul(a0,13), xor(gmul(a1,9),  xor(gmul(a2,14), gmul(a3,11))))
                S[4 * c + 3] = xor(gmul(a0,11), xor(gmul(a1,13), xor(gmul(a2,9),  gmul(a3,14))))
            }
        }
    }
    for (i = 0; i < 16; i++) OUT[i] = S[i]
}

BEGIN {
    ISBOX = "52096ad53036a538bf40a39e81f3d7fb7ce339829b2fff87348e4344c4dee9cb547b9432a6c2233dee4c950b42fac34e082ea16628d924b2765ba2496d8bd12572f8f66486689816d4a45ccc5d65b6926c704850fdedb9da5e154657a78d9d8490d8ab008cbcd30af7e45805b8b34506d02c1e8fca3f0f02c1afbd0301138a6b3a9111414f67dcea97f2cfcef0b4e67396ac7422e7ad3585e2f937e81c75df6e47f11a711d29c5896fb7620eaa18be1bfc563e4bc6d279209adbc0fe78cd5af41fdda8338807c731b11210592780ec5f60517fa919b54a0d2de57a9f93c99cefa0e03b4dae2af5b0c8ebbb3c83539961172b047eba77d626e169146355210c7d"
    for (i = 0; i < 256; i++) ISB[i] = h2d(substr(ISBOX, i * 2 + 1, 2))
    # S-box is needed for the key schedule
    SBOX = "637c777bf26b6fc53001672bfed7ab76ca82c97dfa5947f0add4a2af9ca472c0b7fd9326363ff7cc34a5e5f171d8311504c723c31896059a071280e2eb27b27509832c1a1b6e5aa0523bd6b329e32f8453d100ed20fcb15b6acbbe394a4c58cfd0efaafb434d338545f9027f503c9fa851a3408f929d38f5bcb6da2110fff3d2cd0c13ec5f974417c4a77e3d645d197360814fdc222a908846eeb814de5e0bdbe0323a0a4906245cc2d3ac629195e479e7c8376d8dd54ea96c56f4ea657aae08ba78252e1ca6b4c6e8dd741f4bbd8b8a703eb5664803f60e613557b986c11d9ee1f8981169d98e949b1e87e9ce5528df8ca1890dbfe6426841992d0fb054bb16"
    for (i = 0; i < 256; i++) SB[i] = h2d(substr(SBOX, i * 2 + 1, 2))

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
        for (i = 0; i < 16; i++) OUT[i] = xor(OUT[i], PREV[i])
        for (i = 0; i < 16; i++) PREV[i] = IN[i]
        for (i = 0; i < 16; i++) res = res sprintf("%02x", OUT[i])
    }
    # strip PKCS7 padding
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
