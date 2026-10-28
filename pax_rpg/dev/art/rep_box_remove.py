"""Убрать окна-рамки под рангом и репутацией (два квадрата под героем) и узелок между ними: на их месте — арт героя,
остаются только круги ранга и репутации (иконки ставятся в прототипе).
    python rep_box_remove.py <pax_rpg/reference/inventory> <inventory.jpg с окном> <hero_katana_s.jpg с окном> <выход: inventory.jpg> <выход: hero_katana_s.jpg>"""
import sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter
ref, st_in, hk_in, st_out, hk_out = sys.argv[1:6]
S, L, T = 0.5095, 467, 142                    # как герой вписан в центр (weapon_swap_assets.py)
PANEL = (548, 138, 938, 928)                  # кроп hero_katana_s.jpg
BOXES = [(561, 765, 934, 925)]                # окна ранга и репутации с рамками, затемнением и узелком между ними
def place(f, size):
    h = Image.open(f"{ref}/{f}").convert("RGB"); a = h.resize((round(h.width * S), round(h.height * S)), Image.LANCZOS)
    c = Image.new("RGB", size); c.paste(a, (L, T)); return c
def patch(base, hero, off):
    m = Image.new("L", base.size, 0); d = ImageDraw.Draw(m)
    for x0, y0, x1, y1 in BOXES:
        d.rectangle((x0 - off[0], y0 - off[1], x1 - off[0], y1 - off[1]), fill=255)
    m = m.filter(ImageFilter.GaussianBlur(2))
    return Image.composite(hero, base, m)
st = Image.open(st_in).convert("RGB")
patch(st, place("hero_center_v1.webp", st.size), (0, 0)).save(st_out, quality=92)
hk = Image.open(hk_in).convert("RGB")
full = place("hero_center_katana_v1.webp", st.size).crop(PANEL)
patch(hk, full, PANEL[:2]).save(hk_out, quality=90)
print("ok")
