"""Анимированный пример инвентаря: макет (inventory_v1_with_hero.jpg) + предметы из листа редкости с переливами
(rarity_shimmer.render) в слотах экипировки, серый фон в окне питомца.
    python inventory_demo.py <папка pax_rpg/reference/inventory> <выход без расширения>
→ <выход>.webp (1536 px), <выход>.gif (1024 px), <выход>.png (первый кадр).
Координаты — по inventory_v1.webp (1536×1024). Иконка из листа вписывается в слот по ширине без растяжения,
сверху и снизу — её же размытый фон; рамка редкости рисуется по краю слота.
"""
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rarity_shimmer as rs                            # noqa: E402

# слот экипировки (внутри золотой рамки) → (ряд редкости, столбец листа): 0 обычное … 5 мифическое;
# столбцы — шлем, броня, перчатки, наплечники, сапоги, плащ, кольцо, амулет
L, R = (961, 1086), (1098, 1224)
SLOTS = [((L, (210, 361)), (4, 0)), ((R, (210, 361)), (5, 1)),
         ((L, (372, 531)), (3, 2)), ((R, (372, 531)), (2, 3)),
         ((L, (542, 706)), (1, 4)), ((R, (542, 706)), (0, 5)),
         ((L, (716, 917)), (5, 6)), ((R, (716, 917)), (4, 7))]
INSET = 9                                              # рамка ячейки листа — не берём
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
    """Иконка по ширине слота, без растяжения; сверху/снизу — её размытый фон."""
    bg = cover(tile, w, h).filter(ImageFilter.GaussianBlur(9)).point(lambda v: int(v * 0.8))
    s = w / tile.width
    icon = tile.resize((w, round(tile.height * s)), Image.LANCZOS)
    bg.paste(icon, (0, (h - icon.height) // 2), feather(icon.width, icon.height, 5))
    return bg


def border(w, h, col, amp):
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    edge = np.minimum(np.minimum(xx, w - 1 - xx), np.minimum(yy, h - 1 - yy))
    return np.exp(-edge / 4.0)[..., None] * np.array(col, np.float32) * amp


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

    shimmer = rs.render(os.path.join(ref, "rarity_v2.webp"))
    out_frames = []
    for f, fr in enumerate(shimmer):
        t = f / len(shimmer)
        img = base.copy()
        for ((ax0, ax1), (ay0, ay1)), (r, c) in SLOTS:
            w, h = ax1 - ax0, ay1 - ay0
            sx0, sx1 = rs.COLS[c]
            sy0, sy1 = rs.ROWS[r]
            art = slot_art(fr.crop((sx0 + INSET, sy0 + INSET, sx1 - INSET, sy1 - INSET)), w, h)
            col, a_border = rs.RARITY[r][0], rs.RARITY[r][1]
            amp = a_border * rs.pulse_at(r, c * 0.11 + r * 0.07, t) if a_border else 0.25
            px = np.asarray(art, np.float32) / 255 + border(w, h, col, amp)
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
