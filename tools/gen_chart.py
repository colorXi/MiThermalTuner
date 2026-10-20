#!/usr/bin/env python3
"""
gen_chart.py -- 生成 16 个场景的降频阶梯对比图 (SVG)

用法:
    python tools/gen_chart.py                 # 输出 docs/scene-ladder.svg
    python tools/gen_chart.py --out x.svg

数据来源: reference/decrypted/*.conf (从使用者本机解密得到)
每个场景取 device=cpu4 且 algo_type=ss 的节, 画出 温度 -> 频率 的阶梯曲线。
"""
import argparse
import glob
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
CONF = os.path.join(ROOT, "reference", "decrypted")

# ---- 配色 (与应用界面一致) ----
BG = "#0B0E14"
CARD = "#141924"
LINE = "#242C3B"
FG = "#E8EDF5"
DIM = "#8A94A6"
DIM2 = "#5C6678"
ACC = "#FF6B2C"
TEAL = "#2DD4BF"

LABELS = {
    "thermal-normal.conf": "日常 normal",
    "thermal-mgame.conf": "游戏 mgame",
    "thermal-tgame.conf": "腾讯游戏 tgame",
    "thermal-class0.conf": "极致省电 class0",
    "thermal-video.conf": "视频 video",
    "thermal-videochat.conf": "视频通话",
    "thermal-youtube.conf": "YouTube",
    "thermal-navigation.conf": "导航",
    "thermal-camera.conf": "相机",
    "thermal-4k.conf": "4K 录制",
    "thermal-8k.conf": "8K 录制",
    "thermal-huanji.conf": "环境护眼",
    "thermal-phone.conf": "通话",
    "thermal-nolimits.conf": "不限制",
    "thermal-chg-only.conf": "仅充电",
}
ORDER = [
    "thermal-normal.conf", "thermal-mgame.conf", "thermal-tgame.conf", "thermal-class0.conf",
    "thermal-video.conf", "thermal-videochat.conf", "thermal-youtube.conf", "thermal-navigation.conf",
    "thermal-camera.conf", "thermal-4k.conf", "thermal-8k.conf", "thermal-huanji.conf",
    "thermal-phone.conf", "thermal-nolimits.conf", "thermal-chg-only.conf",
]


def parse_conf(path):
    """返回 [(section, {key: value})]"""
    secs, cur = [], None
    for raw in open(path, encoding="utf-8", errors="replace"):
        line = raw.rstrip("\n")
        if not line.strip():
            continue
        m = re.match(r"^\s*\[(.+)\]\s*$", line)
        if m:
            cur = (m.group(1), {})
            secs.append(cur)
            continue
        if cur is None:
            continue
        parts = re.split(r"\s+", line.strip(), maxsplit=1)
        if len(parts) == 2:
            cur[1][parts[0]] = parts[1].strip()
        elif parts:
            cur[1][parts[0]] = ""
    return secs


def cpu4_ladder(path):
    """取 device=cpu4 且 algo_type=ss 的节, 返回 (trig, clr, target)"""
    for name, kv in parse_conf(path):
        if kv.get("algo_type") == "ss" and kv.get("device", "").strip() == "cpu4":
            def nums(key):
                return [int(x) for x in re.findall(r"-?\d+", kv.get(key, ""))]
            return nums("trig"), nums("clr"), nums("target")
    return None, None, None


def mix(c1, c2, t):
    """两色线性插值"""
    return "#%02X%02X%02X" % tuple(round(a + (b - a) * t) for a, b in zip(c1, c2))


def temp_color(t):
    """温度 -> 颜色 (冷青 -> 黄 -> 红)"""
    c1 = (0x2D, 0xD4, 0xBF)
    c2 = (0xFB, 0xBF, 0x24)
    c3 = (0xF0, 0x52, 0x5B)
    if t <= 42:
        return mix(c1, c2, max(0.0, (t - 25) / 17.0))
    return mix(c2, c3, min(1.0, (t - 42) / 12.0))


def esc(s):
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=os.path.join(ROOT, "docs", "scene-ladder.svg"))
    args = ap.parse_args()

    data = []
    for name in ORDER:
        p = os.path.join(CONF, name)
        if not os.path.exists(p):
            continue
        trig, clr, target = cpu4_ladder(p)
        if not trig:
            continue
        data.append((name, trig, clr, target))
    if not data:
        sys.exit("找不到场景配置, 请先跑 mt_editor.py pull 或在设备上 mt decrypt")

    # ---- 画布 (3 列 x 5 行, 宽度贴近 README 正文宽度, 不会被缩小太多) ----
    COLS, ROWS = 3, 5
    PW, PH = 300, 196          # 面板尺寸
    GX, GY = 22, 16            # 面板间距
    ML, MTOP = 26, 74          # 左边距/标题区
    LEGEND = 96                # 底部图例高度
    W = ML + COLS * PW + (COLS - 1) * GX + 26
    H = MTOP + ROWS * PH + (ROWS - 1) * GY + LEGEND

    # 全局温度(毫摄氏度)/频率(GHz)范围
    all_t = [t for _, trig, _, _ in data for t in trig]
    all_f = [f for _, _, _, tg in data for f in tg]
    tmin, tmax = 25000, 58000   # 毫摄氏度
    fmin, fmax = 0.6, 2.5       # GHz

    o = []
    a = o.append
    a(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
      f'viewBox="0 0 {W} {H}" font-family="Noto Sans CJK SC,Source Han Sans SC,Microsoft YaHei,PingFang SC,Helvetica,Arial,sans-serif">')
    a(f'<rect width="{W}" height="{H}" fill="{BG}" rx="14"/>')

    # 标题
    a(f'<text x="{ML}" y="34" fill="{FG}" font-size="20" font-weight="700">'
      f'小米温控降频阶梯对比 · 16 个场景</text>')
    a(f'<text x="{ML}" y="55" fill="{DIM}" font-size="12">'
      f'横轴 = VIRTUAL-SENSOR 虚拟温度(°C)　纵轴 = policy4 大核频率(GHz)　'
      f'台阶 = 该温度开始触发的降频档位</text>')

    for idx, (name, trig, clr, target) in enumerate(data):
        cx = ML + (idx % COLS) * (PW + GX)
        cy = MTOP + (idx // COLS) * (PH + GY)
        a(f'<g transform="translate({cx},{cy})">')
        a(f'<rect x="0" y="0" width="{PW}" height="{PH}" rx="12" fill="{CARD}" stroke="{LINE}"/>')

        # 标题
        a(f'<text x="14" y="24" fill="{FG}" font-size="13" font-weight="600">{esc(LABELS.get(name, name))}</text>')
        if trig:
            a(f'<text x="{PW-14}" y="24" fill="{ACC}" font-size="11" text-anchor="end" '
              f'font-weight="600">起降 {trig[0]/1000:.0f}°C</text>')
        a(f'<text x="14" y="39" fill="{DIM2}" font-size="9.5">{esc(name)}</text>')

        # 绘图区 (X 收毫摄氏度, Y 收 kHz)
        px0, py0 = 42, 52
        pw, ph = PW - 56, PH - 92

        def X(t_milli):
            return px0 + (t_milli - tmin) / (tmax - tmin) * pw

        def Y(f_khz):
            f = f_khz / 1000000.0
            return py0 + ph - (f - fmin) / (fmax - fmin) * ph

        # 网格
        for gv in (1.0, 1.5, 2.0, 2.5):
            gy = Y(gv * 1000000)
            a(f'<line x1="{px0}" y1="{gy:.1f}" x2="{px0+pw}" y2="{gy:.1f}" stroke="{LINE}" stroke-width="1"/>')
            a(f'<text x="{px0-6}" y="{gy+3:.1f}" fill="{DIM2}" font-size="9" text-anchor="end">{gv:.1f}</text>')
        a(f'<text x="{px0-30}" y="{py0+ph/2:.1f}" fill="{DIM2}" font-size="9" '
          f'text-anchor="middle" transform="rotate(-90 {px0-30} {py0+ph/2:.1f})">GHz</text>')

        # 温度轴刻度
        for tv in (30, 40, 50):
            tx = X(tv * 1000)
            a(f'<line x1="{tx:.1f}" y1="{py0}" x2="{tx:.1f}" y2="{py0+ph}" stroke="{LINE}" '
              f'stroke-width="1" stroke-dasharray="2 3"/>')
            a(f'<text x="{tx:.1f}" y="{py0+ph+13}" fill="{DIM2}" font-size="9" '
              f'text-anchor="middle">{tv}°</text>')

        if trig and target:
            # 只画真正的降频阶梯: 从第一个触发点开始
            pts = []
            prev_f = target[0] if target else 691200
            for i, t in enumerate(trig):
                f = target[i] if i < len(target) else target[-1]
                if i == 0:
                    pts.append((X(t), Y(f)))          # 起点
                else:
                    pts.append((X(t), Y(prev_f)))     # 水平段
                    pts.append((X(t), Y(f)))          # 垂直跌落
                prev_f = f
            pts.append((X(tmax), Y(prev_f)))           # 末段保持

            d = " ".join(("M" if i == 0 else "L") + f"{x:.1f},{y:.1f}" for i, (x, y) in enumerate(pts))
            a(f'<path d="{d}" fill="none" stroke="{TEAL}" stroke-width="2.2" '
              f'stroke-linejoin="round" stroke-linecap="round"/>')

            # 触发点 (首尾标频率, 中间只画点)
            for i, t in enumerate(trig):
                f = target[i] if i < len(target) else target[-1]
                a(f'<circle cx="{X(t):.1f}" cy="{Y(f):.1f}" r="3.4" fill="{temp_color(t/1000)}"/>')
                if i == 0 or i == len(trig) - 1:
                    a(f'<text x="{X(t):.1f}" y="{Y(f)+15:.1f}" fill="{temp_color(t/1000)}" '
                      f'font-size="10" text-anchor="middle" font-weight="700">{f/1000000:.2f}</text>')

            # 迟滞带
            for i in range(min(len(clr), len(trig))):
                a(f'<rect x="{X(clr[i]):.1f}" y="{py0}" width="{X(trig[i])-X(clr[i]):.1f}" '
                  f'height="{ph}" fill="{ACC}" opacity="0.08"/>')
            a(f'<text x="{px0+pw}" y="{py0+ph+26}" fill="{DIM2}" font-size="9.5" text-anchor="end">'
              f'最低 {min(target)/1000000:.2f} GHz</text>')
        a("</g>")

    # ---- 图例 ----
    ly = H - LEGEND + 26
    a(f'<text x="{ML}" y="{ly}" fill="{DIM}" font-size="11.5" font-weight="600">触发温度</text>')
    lx = ML + 68
    for t in (28, 35, 42, 48, 55):
        a(f'<circle cx="{lx}" cy="{ly-4}" r="6" fill="{temp_color(t)}"/>')
        a(f'<text x="{lx}" y="{ly+14}" fill="{DIM2}" font-size="9" text-anchor="middle">{t}°C</text>')
        lx += 52
    a(f'<line x1="{lx+18}" y1="{ly-4}" x2="{lx+52}" y2="{ly-4}" stroke="{TEAL}" stroke-width="2"/>')
    a(f'<text x="{lx+60}" y="{ly}" fill="{DIM}" font-size="11">降频阶梯曲线</text>')
    a(f'<rect x="{lx+168}" y="{ly-13}" width="18" height="12" fill="{ACC}" opacity="0.18"/>')
    a(f'<text x="{lx+194}" y="{ly}" fill="{DIM}" font-size="11">迟滞区间 (clr→trig)</text>')
    a(f'<text x="{ML}" y="{H-16}" fill="{DIM2}" font-size="9.5">'
      f'数据来源: 使用者本机 /vendor/etc/thermal-*.conf 解密结果 · 每个场景取 device=cpu4 的 ss 节</text>')

    a("</svg>")

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    open(args.out, "w", encoding="utf-8", newline="\n").write("\n".join(o))
    print("wrote", args.out, os.path.getsize(args.out), "bytes,", len(data), "scenarios")


if __name__ == "__main__":
    main()
