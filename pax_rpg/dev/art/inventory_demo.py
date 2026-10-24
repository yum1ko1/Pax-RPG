"""Анимированный пример инвентаря: макет (inventory_v1_with_hero.jpg) + предметы из листа редкости с переливами
(rarity_shimmer.render) в слотах экипировки, серый фон в окне питомца.
    python inventory_demo.py <папка pax_rpg/reference/inventory> <выход без расширения>
→ <выход>.webp (1536 px), <выход>.gif (1024 px), <выход>.png (первый кадр).
Координаты — по inventory_v1.webp (1536×1024).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import rarity_shimmer as rs                            # noqa: E402

# слот экипировки → (ряд редкости, столбец листа): 0 обычное … 5 мифическое; столбцы — шлем, броня, перчатки,
# наплечники, сапоги, плащ, кольцо, амулет
SQUARE = [((960, 210, 1087, 362), (4, 0)), ((1097, 210, 1226, 362), (5, 1)),
          ((960, 372, 1087, 532), (3, 2)), ((1097, 372, 1226, 532), (2, 3)),
          ((960, 542, 1087, 705), (1, 4)), ((1097, 542, 1226, 705), (0, 5))]
ROUND = [((1025, 845, 44), (5, 6)), ((1162, 845, 44), (4, 7))]   # кольцо и амулет — в круглых слотах
PET = (378, 658, 519, 915)                             # окно питомца и его кружок/слот навыка поверх фона
PET_UI = dict(circle=(380, 848, 432, 900), square=(454, 834, 522, 907), y=873, stem=(485, 905, 494, 920))


def cover(img, w, h):
    s = max(w / img.width, h / img.height)
    a = img.resize((round(img.width * s), round(img.height * s)), Image.LANCZOS)
    return a.crop(((a.width - w) // 2, (a.height - h) // 2, (a.width - w) // 2 + w, (a.height - h) // 2 + h))


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

    frames = rs.render(os.path.join(ref, "rarity_v2.webp"))
    disc = {}
    out_frames = []
    for fr in frames:
        img = base.copy()
        for (ax0, ay0, ax1, ay1), (r, c) in SQUARE:   # ячейка листа целиком, со своей рамкой редкости
            cx0, cx1 = rs.COLS[c]
            cy0, cy1 = rs.ROWS[r]
            img.paste(fr.crop((cx0, cy0, cx1, cy1)).resize((ax1 - ax0, ay1 - ay0), Image.LANCZOS), (ax0, ay0))
        for (cx, cy, rad), (r, c) in ROUND:            # круглый слот: середина ячейки в круге, ободок слота сохраняем
            sx0, sx1 = rs.COLS[c]
            sy0, sy1 = rs.ROWS[r]
            side = min(sx1 - sx0, sy1 - sy0) - 16
            mx, my = (sx0 + sx1) // 2, (sy0 + sy1) // 2
            tile = fr.crop((mx - side // 2, my - side // 2, mx + side // 2, my + side // 2)).resize((rad * 2, rad * 2), Image.LANCZOS)
            if rad not in disc:
                k = Image.new("L", (rad * 8, rad * 8), 0)
                ImageDraw.Draw(k).ellipse((0, 0, rad * 8 - 1, rad * 8 - 1), fill=255)
                disc[rad] = k.resize((rad * 2, rad * 2), Image.LANCZOS)
            img.paste(tile, (cx - rad, cy - rad), disc[rad])
            ring = Image.new("L", orig.size, 0)
            ImageDraw.Draw(ring).ellipse((cx - rad - 4, cy - rad - 4, cx + rad + 4, cy + rad + 4), outline=255, width=6)
            img.paste(orig, (0, 0), ring.filter(ImageFilter.GaussianBlur(0.7)))
        out_frames.append(img.convert("RGB"))
    W, H = out_frames[0].size
    out_frames[0].save(out + ".png")
    out_frames[0].save(out + ".webp", save_all=True, append_images=out_frames[1:], duration=rs.MS, loop=0, quality=88, method=4)
    small = [f.resize((1024, round(H * 1024 / W)), Image.LANCZOS) for f in out_frames]
    pal = [f.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG) for f in small]
    pal[0].save(out + ".gif", save_all=True, append_images=pal[1:], duration=rs.MS, loop=0, optimize=True, disposal=1)
    print("saved", out + ".png/.webp/.gif")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
