#!/usr/bin/env python3
"""Окно 3:2 → картинка 16:9: фон без панелей по бокам, сам макет по центру со смягчённым краем.

    python3 build_stage_wide.py <stage.jpg> <backdrop.png> <out.jpg> [--feather 16] [--backdrop-out backdrop.jpg]

stage — макет 3:2 (inventory/stage.jpg 3072×2048), backdrop — любой фон, кладётся «cover».
Выход — ширина 16/9 от высоты stage; в игре рисуется в Rect2(-(WW - W) / 2, 0, WW, H).
"""
import argparse
from PIL import Image

ap = argparse.ArgumentParser()
ap.add_argument("stage")
ap.add_argument("backdrop")
ap.add_argument("out")
ap.add_argument("--feather", type=int, default=16, help="ширина перехода по краям stage, px исходника")
ap.add_argument("--trim", type=int, nargs=2, default=[0, 0], metavar=("L", "R"),
                help="сколько столбцов stage отбросить слева/справа (у inventory/stage.jpg справа белая полоса 14 px)")
ap.add_argument("--wide", type=int, default=16, help="переход выше и ниже панелей, px исходника")
ap.add_argument("--panels", type=int, nargs=2, default=None, metavar=("Y0", "Y1"),
                help="строки stage, где у края стоят рамки панелей (там переход --feather)")
ap.add_argument("--backdrop-out", default="", help="сохранить и сам фон 16:9 (для других окон)")
a = ap.parse_args()

st = Image.open(a.stage).convert("RGB")
sw, sh = st.size
ww = round(sh * 16 / 9 / 4) * 4
bd = Image.open(a.backdrop).convert("RGB")
k = max(ww / bd.width, sh / bd.height)
bd = bd.resize((round(bd.width * k), round(bd.height * k)), Image.LANCZOS)
x0, y0 = (bd.width - ww) // 2, (bd.height - sh) // 2
bd = bd.crop((x0, y0, x0 + ww, y0 + sh))
if a.backdrop_out:
    bd.save(a.backdrop_out, quality=90)

# маска: 1 внутри, плавно к 0 у левого и правого края stage
tl, tr = a.trim
y0p, y1p = a.panels if a.panels else (sh, sh)
data = []
for y in range(sh):
    # вдоль панелей переход узкий (рамки у самого края), выше/ниже — широкий, чтобы не резать сакуру
    g = min(1.0, max(0.0, max(y0p - y, y - y1p) / 80.0))
    f = max(1.0, a.feather + (a.wide - a.feather) * g * g * (3 - 2 * g))
    for x in range(sw):
        t = min(1.0, max(0, min(x - tl, sw - 1 - tr - x)) / f)
        data.append(round(255 * t * t * (3 - 2 * t)))
mask = Image.new("L", (sw, sh))
mask.putdata(data)

out = bd.copy()
out.paste(st, ((ww - sw) // 2, 0), mask)
out.save(a.out, quality=90)
print(a.out, out.size)
