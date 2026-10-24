"""Убрать окно-рамку под репутацией (правый квадрат под героем): на его месте — арт героя, остаётся только круг
репутации (иконка ставится в прототипе). Узелок между окнами ранга и репутации сохраняется.
    python rep_box_remove.py <pax_rpg/reference/inventory> <inventory.jpg с окном> <hero_katana_s.jpg с окном> <выход: inventory.jpg> <выход: hero_katana_s.jpg>"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
ref, st_in, hk_in, st_out, hk_out = sys.argv[1:6]
S, L, T = 0.5095, 467, 142                    # как герой вписан в центр (weapon_swap_assets.py)
PANEL = (548, 138, 938, 928)                  # кроп hero_katana_s.jpg
BOX = (744, 765, 934, 925)                    # окно репутации с рамкой и затемнением
KNOT = (727, 805, 753, 885)                   # узелок между окнами — оставить
def place(f, size):
    h = Image.open(f"{ref}/{f}").convert("RGB"); a = h.resize((round(h.width * S), round(h.height * S)), Image.LANCZOS)
    c = Image.new("RGB", size); c.paste(a, (L, T)); return c
def patch(base, hero, off):
    m = Image.new("L", base.size, 0); d = ImageDraw.Draw(m)
    x0, y0, x1, y1 = BOX; d.rectangle((x0 - off[0], y0 - off[1], x1 - off[0], y1 - off[1]), fill=255)
    k0, k1, k2, k3 = KNOT; d.rectangle((k0 - off[0], k1 - off[1], k2 - off[0], k3 - off[1]), fill=0)
    m = m.filter(ImageFilter.GaussianBlur(2))
    return Image.composite(hero, base, m)
st = Image.open(st_in).convert("RGB")
patch(st, place("hero_center_v1.webp", st.size), (0, 0)).save(st_out, quality=92)
hk = Image.open(hk_in).convert("RGB")
full = place("hero_center_katana_v1.webp", st.size).crop(PANEL)
patch(hk, full, PANEL[:2]).save(hk_out, quality=90)
print("ok")
