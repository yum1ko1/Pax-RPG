"""Норэн над дверями лавок Гхарна: три полотнища одной ткани, через них — белый герб-мон (как у настоящих норэн:
рисунок общий, полотнища — его части). Окраска в палитре улиц (dressing.gd → PALETTE), переплетение нитей,
выцветшая кромка сверху, тёмный подрубленный низ, петли под перекладину. Пишет mods/pax_rpg/textures/noren/
noren_<цвет>_<полотнище 0..2>.png (256×432 — пропорции полотнища 0.56×0.95 м).
    python3 pax_rpg/dev/gharn/noren_tex.py"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
OUT = os.path.join(ROOT, "mods", "pax_rpg", "textures", "noren")
W, H, GAP = 256, 432, 18                       # полотнище и щель между ними (в пикселях общего рисунка)
PALETTE = [(0.62, 0.06, 0.05), (0.06, 0.05, 0.05), (0.72, 0.5, 0.12), (0.48, 0.03, 0.03), (0.1, 0.28, 0.27)]
INK = [(0.93, 0.89, 0.8), (0.86, 0.7, 0.4), (0.12, 0.07, 0.05), (0.93, 0.88, 0.78), (0.9, 0.86, 0.76)]


def mon(d, cx, cy, r, ink, kind):
    """Герб: кольцо и внутри — ромб-цветок (kind 0), три запятые-томоэ (1) или скрещённые перья (2)."""
    lw = max(4, int(r * 0.12))
    d.ellipse([cx - r, cy - r, cx + r, cy + r], outline=ink, width=lw)
    ri = r * 0.68
    if kind == 0:
        for a in range(4):
            t = math.radians(a * 90 + 45)
            px, py = cx + math.cos(t) * ri * 0.5, cy + math.sin(t) * ri * 0.5
            s = ri * 0.42
            d.polygon([(px, py - s), (px + s, py), (px, py + s), (px - s, py)], fill=ink)
    elif kind == 1:
        for a in range(3):
            t = math.radians(a * 120 - 90)
            px, py = cx + math.cos(t) * ri * 0.42, cy + math.sin(t) * ri * 0.42
            s = ri * 0.36
            d.ellipse([px - s, py - s, px + s, py + s], fill=ink)
    else:
        for sgn in (-1, 1):
            t = math.radians(90 + sgn * 28)
            x0, y0 = cx - math.cos(t) * ri, cy + math.sin(t) * ri * 0.9
            x1, y1 = cx + math.cos(t) * ri, cy - math.sin(t) * ri * 0.9
            d.line([(x0, y0), (x1, y1)], fill=ink, width=lw)
            for k in range(1, 6):
                u = k / 6
                mx, my = x0 + (x1 - x0) * u, y0 + (y1 - y0) * u
                n = (-(y1 - y0), x1 - x0)
                ln = math.hypot(*n)
                d.line([(mx, my), (mx + n[0] / ln * ri * 0.22, my + n[1] / ln * ri * 0.22)], fill=ink, width=lw // 2)


def weave(w, h, rng):
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    warp = 0.5 + 0.5 * np.sin(x * 2.3 + rng.random() * 6)
    weft = 0.5 + 0.5 * np.sin(y * 2.1 + rng.random() * 6)
    check = ((np.floor(x / 1.5) + np.floor(y / 1.5)) % 2)
    fiber = np.array(Image.effect_noise((w, h), 40).filter(ImageFilter.GaussianBlur(0.7)), np.float32) / 255.0
    return 0.86 + 0.07 * (warp * check + weft * (1 - check)) + 0.1 * (fiber - 0.5)


def main():
    os.makedirs(OUT, exist_ok=True)
    TW = 3 * W + 2 * GAP
    for ci, (base, ink) in enumerate(zip(PALETTE, INK)):
        rng = random.Random(ci * 31 + 7)
        nrng = np.random.default_rng(ci)
        art = Image.new("RGB", (TW, H), tuple(int(c * 255) for c in base))
        d = ImageDraw.Draw(art)
        mon(d, TW / 2, H * 0.52, H * 0.27, tuple(int(c * 255) for c in ink), ci % 3)
        art = art.filter(ImageFilter.GaussianBlur(0.8))    # краска впиталась в ткань — край мягкий
        a = np.asarray(art, np.float32) / 255.0
        a *= weave(TW, H, nrng)[..., None]
        yy = np.linspace(0, 1, H)[:, None, None]
        a *= 1.08 - 0.12 * yy                                # верх выцвел на солнце, низ темнее
        a[int(H * 0.94):] *= 0.62                            # подрубленный низ
        dirt = np.array(Image.effect_noise((TW, H), 60).filter(ImageFilter.GaussianBlur(6)), np.float32) / 255.0
        a *= (1.0 - 0.18 * np.clip((yy[..., 0] - 0.7) / 0.3, 0, 1) * dirt)[..., None]
        rgba = np.concatenate([np.clip(a, 0, 1), np.ones((H, TW, 1), np.float32)], axis=2)
        loops = 4                                            # петли под перекладину: верхняя кромка — зубцами
        for x in range(TW):
            local = x % (W + GAP)
            if local >= W:
                continue
            seg = int(local / W * loops)
            frac = local / W * loops - seg
            if 0.25 < frac < 0.75:
                rgba[: int(H * 0.035), x, 3] = 0.0           # между петлями — прорезь
        img = Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")
        for i in range(3):
            x0 = i * (W + GAP)
            img.crop((x0, 0, x0 + W, H)).save(os.path.join(OUT, f"noren_{ci}_{i}.png"))
    print("noren textures:", len(PALETTE) * 3, "→", OUT)


if __name__ == "__main__":
    main()
