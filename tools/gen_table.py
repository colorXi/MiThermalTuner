#!/usr/bin/env python3
"""生成 README 用的降频阶梯速查表 (Markdown)"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_chart import parse_conf, cpu4_ladder, CONF, LABELS, ORDER

rows = []
for name in ORDER:
    p = os.path.join(CONF, name)
    if not os.path.exists(p):
        continue
    trig, clr, target = cpu4_ladder(p)
    if not trig:
        continue
    rows.append((LABELS.get(name, name), name, trig, target))

out = ["| 场景 | 起降温度 | 降频阶梯 (温度 → 频率) | 最低 |",
       "|---|---|---|---|"]
for label, name, trig, target in rows:
    steps = " → ".join(f"{t/1000:.0f}°C/{f/1000000:.2f}G" for t, f in zip(trig, target))
    out.append(f"| **{label}** | {trig[0]/1000:.0f}°C | {steps} | {min(target)/1000000:.2f} GHz |")

out.append("")
out.append("> 全部场景都会降到 **0.69 GHz**，区别只在「什么时候开始降」和「降得多狠」。")
out.append("> 通话场景 27°C 就开始降，极其激进；游戏场景 46°C 才一刀切到 0.69G。")

txt = "\n".join(out)
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "docs", "scene-ladder-table.md"),
     "w", encoding="utf-8", newline="\n").write(txt + "\n")
print(txt)
