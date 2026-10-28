"""Анимированный пример инвентаря: макет (inventory_v1_with_hero.jpg) + предметы из листа редкости с переливами
(rarity_shimmer.render) в слотах экипировки, серый фон в окне питомца.
    python inventory_demo.py <папка pax_rpg/reference/inventory> <выход без расширения>
→ <выход>.webp (1536 px), <выход>.gif (1024 px), <выход>.png (первый кадр).
Координаты — по inventory_v1.webp (1536×1024). Иконки — из rarity_v3.webp (ячейки под пропорции слотов): заполняют
слот без растяжения (по бокам срезается не больше 12 %), остаток — размытый фон ячейки; рамка редкости — по краю слота.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rarity_shimmer as rs                            # noqa: E402

# слот экипировки (внутри золотой рамки) → (предмет, редкость): предметы 0 шлем, 1 броня, 2 перчатки, 3 наплечники,
# 4 сапоги, 5 плащ, 6 кольцо, 7 амулет; редкость 0 обычное … 5 мифическое
L, R = (961, 1086), (1098, 1224)
SLOTS = [((L, (210, 361)), (0, 4)), ((R, (210, 361)), (1, 5)),
         ((L, (372, 531)), (2, 3)), ((R, (372, 531)), (3, 2)),
         ((L, (542, 706)), (4, 1)), ((R, (542, 706)), (5, 0)),
         ((L, (716, 917)), (6, 5)), ((R, (716, 917)), (7, 4))]
SHEET, LAYOUT, INSET = "rarity_v3.webp", "v3", 2
PET = (378, 658, 519, 915)                             # окно питомца и его кружок/слот навыка поверх фона
PET_UI = dict(circle=(380, 848, 432, 900), square=(454, 834, 522, 907), y=873, stem=(485, 905, 494, 920))


def cover(img, w, h):
    s = max(w / img.width, h / img.height)
    a = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    return a.crop(((a.width - w) // 2, (a.height - h) // 2, (a.width - w) // 2 + w, (a.height - h) // 2 + h))


def feather(w, h, edge):
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).rectangle((edge, edge, w - 1 - edge, h - 1 - edge), fill=255)
    return m.filter(ImageFilter.GaussianBlur(edge / 2))


def slot_art(tile, w, h):
    """Иконка на весь слот без растяжения: по бокам срезается не больше 12 %, остаток — размытый фон ячейки."""
    bg = cover(tile, w, h).filter(ImageFilter.GaussianBlur(9)).point(lambda v: int(v * 0.8))
    s = min(max(w / tile.width, h / tile.height), w / (tile.width * 0.88))
    icon = tile.resize((round(tile.width * s), round(tile.height * s)), Image.LANCZOS)
    bg.paste(icon, ((w - icon.width) // 2, (h - icon.height) // 2), feather(icon.width, icon.height, 5))
    return bg


def border(px, col, amp):
    """Тонкая постоянная рамка цветом редкости + мягкое свечение внутрь, яркость свечения — amp."""
    h, w, _ = px.shape
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    edge = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))
    col = np.array(col, np.float32)
    line = np.clip(1.6 - edge, 0, 1)[..., None] * 0.85
    px = px * (1 - line) + line * col * 0.9
    return px + np.exp(-edge / 7.0)[..., None] * col * amp


def main(ref: str, out: str):
    orig = Image.open(os.path.join(ref, "inventory_v1.webp")).convert("RGBA")
    base = Image.open(os.path.join(ref, "inventory_v1_with_hero.jpg")).convert("RGBA")
    bg = Image.open(os.path.join(ref, "weapon_window_bg_v1.webp")).convert("RGBA")
    x0, y0, x1, y1 = PET
    base.paste(cover(bg, x1 - x0, y1 - y0), (x0, y0))
    m = Image.new("L", orig.size, 0)
    d = ImageDraw.Draw(m)
    d.ellipse(PET_UI["circle"], fill=255)
    d.rounded_rectangle(PET_UI["square"], radius=6, fill=255)
    y = PET_UI["y"]
    d.rectangle((430, y - 6, 456, y + 4), fill=255)
    d.rectangle((520, y - 6, 548, y + 4), fill=255)
    d.rectangle(PET_UI["stem"], fill=255)
    base.paste(orig, (0, 0), m.filter(ImageFilter.GaussianBlur(0.8)))
    base = base.convert("RGB")

    shimmer = rs.render(os.path.join(ref, SHEET), LAYOUT)
    out_frames = []
    for f, fr in enumerate(shimmer):
        t = f / len(shimmer)
        img = base.copy()
        for ((ax0, ax1), (ay0, ay1)), (item, r) in SLOTS:
            w, h = ax1 - ax0, ay1 - ay0
            sx0, sy0, sx1, sy1 = rs.cell(LAYOUT, item, r)
            art = slot_art(fr.crop((sx0 + INSET, sy0 + INSET, sx1 - INSET, sy1 - INSET)), w, h)
            col, a_border = rs.RARITY[r][0], rs.RARITY[r][1]
            amp = a_border * 0.75 * rs.pulse_at(r, item * 0.11 + r * 0.07, t) if a_border else 0.0
            px = border(np.asarray(art, np.float32) / 255, col if a_border else (0.55, 0.55, 0.55), amp)
            img.paste(Image.fromarray((np.clip(px, 0, 1) * 255).astype(np.uint8)), (ax0, ay0))
        out_frames.append(img)
    W, H = out_frames[0].size
    out_frames[0].save(out + ".png")
    out_frames[0].save(out + ".webp", save_all=True, append_images=out_frames[1:], duration=rs.MS, loop=0, quality=88, method=4)
    small = [f.resize((1024, round(H * 1024 / W)), Image.LANCZOS) for f in out_frames]
    pal = [f.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG) for f in small]
    pal[0].save(out + ".gif", save_all=True, append_images=pal[1:], duration=rs.MS, loop=0, optimize=True, disposal=1)
    print("saved", out + ".png/.webp/.gif")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
