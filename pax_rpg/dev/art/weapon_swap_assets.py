"""Слои для переключения главного оружия в прототипе подсказки (координаты — по макету 1536×1024).
    python weapon_swap_assets.py <pax_rpg/reference/inventory> <inventory.jpg прототипа> <ui>
→ wpn_bg_s.jpg (серый фон окна), wpn_spear_s.png / wpn_katana_s.png (оружие без фона),
  wui_1_s.png / wui_2_s.png (кружок, гнездо навыка, перемычки и уголки окна — поверх оружия),
  hero_katana_s.jpg (центр с героем, который держит катану; плашки и рамки — с макета)."""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ref, stage_path, out = sys.argv[1:4]
st = Image.open(stage_path).convert("RGB")
WIN = [(377, 150, 522, 411), (377, 417, 522, 650)]          # арт внутри окон основного и второго оружия
UI = [dict(c=(405.7, 369), sq=(454, 327, 522, 399), bars=[(428, 361, 458, 371), (518, 358, 551, 374)], stem=(486, 396, 496, 414),
           corners=[(375, 388, 397, 411), (507, 388, 524, 411)]),
      dict(c=(405.7, 609), sq=(454, 567, 522, 640), bars=[(428, 601, 458, 612), (518, 598, 551, 615)], stem=(486, 636, 496, 653),
           corners=[])]
HERO = dict(scale=0.5095, left=467, top=142, panel=(548, 138, 938, 928), keep=[(570, 158, 640, 230)])   # «Пас» не трогаем


def trim(im, t=8):
    a = np.asarray(im)[..., 3]; ys, xs = np.where(a > t)
    return im.crop((xs.min(), ys.min(), xs.max() + 1, ys.max() + 1))


def save(im, name, **kw):
    im.save(os.path.join(out, name), **kw); print(name, im.size)


bg = Image.open(os.path.join(ref, "weapon_window_bg_v1.webp")).convert("RGB")
save(bg.resize((290, round(290 * bg.height / bg.width)), Image.LANCZOS), "wpn_bg_s.jpg", quality=88)
for name, f in [("spear", "spear_icon_v1.webp"), ("katana", "katana_icon_cut_v1.png")]:
    im = trim(Image.open(os.path.join(ref, f)).convert("RGBA"))
    save(im.resize((round(im.width * 480 / im.height), 480), Image.LANCZOS), f"wpn_{name}_s.png", optimize=True)

# детали окна поверх оружия: вырезаем из макета по маске фигур
for i, u in enumerate(UI, 1):
    x0, y0, x1, y1 = 370, u["sq"][1] - 6, 556, max(u["stem"][3], u["sq"][3]) + 4
    s = 4
    m = Image.new("L", ((x1 - x0) * s, (y1 - y0) * s), 0); d = ImageDraw.Draw(m)
    sc = lambda b: [(b[0] - x0) * s, (b[1] - y0) * s, (b[2] - x0) * s, (b[3] - y0) * s]
    cx, cy = u["c"]; r = 25.6
    d.ellipse(sc((cx - r, cy - r, cx + r, cy + r)), fill=255)
    d.rectangle(sc(u["sq"]), fill=255); d.rectangle(sc(u["stem"]), fill=255)
    for b in u["bars"] + u["corners"]: d.rectangle(sc(b), fill=255)
    m = m.resize((x1 - x0, y1 - y0), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.5))
    crop = st.crop((x0, y0, x1, y1)).convert("RGBA"); crop.putalpha(m)
    save(crop, f"wui_{i}_s.png", optimize=True)
    print(f"wui_{i} box", (x0, y0, x1, y1))

# центр: герой с катаной там, где на макете виден герой с копьём (маска — где макет совпадает с артом копья)
def place(f):
    h = Image.open(os.path.join(ref, f)).convert("RGB")
    a = h.resize((round(h.width * HERO["scale"]), round(h.height * HERO["scale"])), Image.LANCZOS)
    c = Image.new("RGB", st.size); c.paste(a, (HERO["left"], HERO["top"])); return c
sp, ka = place("hero_center_v1.webp"), place("hero_center_katana_v1.webp")
blur = lambda im: np.asarray(im.filter(ImageFilter.GaussianBlur(1.2))).astype(int)
mk = Image.fromarray(((np.abs(blur(st) - blur(sp)).max(2) < 34) * 255).astype(np.uint8))
mk = mk.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.MaxFilter(3))
P = HERO["panel"]; full = Image.new("L", st.size, 0); full.paste(mk.crop(P), P[:2])
d = ImageDraw.Draw(full)
for b in HERO["keep"]: d.rectangle(b, fill=0)
save(Image.composite(ka, st, full.filter(ImageFilter.GaussianBlur(0.8))).crop(P), "hero_katana_s.jpg", quality=90)
