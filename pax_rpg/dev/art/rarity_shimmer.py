"""Анимация листа предметов по редкости (pax_rpg/reference/inventory/rarity_v*.webp): переливы по редкости.
    python rarity_shimmer.py <лист> <выход без расширения> [v2|v3|gharn]
→ <выход>.webp (полный размер) и <выход>.gif (длинная сторона 1024 px). Редкость: обычное (без анимации), необычное и
редкое (пульс рамки), эпическое (пульс + блик), легендарное (пульс + блик + искры), мифическое (мерцание, блик, угли).
Сетки листов — в LAYOUTS (края ячеек в пикселях, найдены по перепадам яркости): v2 — 6 рядов редкости × 8 предметов,
самоцветы слева; v3 — 8 рядов предметов × 6 столбцов редкости, без рамок (под слоты инвентаря) — на анимации ячейкам
рисуется тонкая постоянная рамка цветом редкости, свечение «дышит» вокруг неё.
"""
import math
import sys

import numpy as np
from PIL import Image

LAYOUTS = {
    "v2": dict(cols=[(107, 283), (294, 465), (476, 646), (657, 827), (838, 1006), (1017, 1188), (1198, 1362), (1373, 1523)],
               rows=[(14, 149), (159, 302), (311, 457), (469, 621), (631, 793), (802, 980)], by="row", gems=True),
    "v3": dict(cols=[(16, 172), (182, 341), (350, 508), (517, 676), (684, 844), (852, 1010)],
               rows=[(16, 177), (185, 348), (357, 519), (528, 691), (701, 870), (878, 1065), (1073, 1258), (1267, 1462)],
               by="col", gems=False),
    "gharn": dict(cols=[(12, 165), (180, 335), (345, 509), (515, 679), (685, 850), (856, 1016)],
                  rows=[(8, 179), (185, 360), (366, 528), (535, 708), (714, 887), (894, 1118), (1124, 1292), (1298, 1530)],
                  by="col", gems=False),          # gharn_set_v1.webp — сет «Воитель песков Гхарна», раскладка как v3
}
GEM_X = 50                                             # центр самоцветов слева (v2)
FRAMES, MS = 48, 85                                    # ~4 с на цикл
#           цвет            рамка  блик  искры угли
RARITY = [((0.7, 0.7, 0.7), 0.0, 0.0, 0, 0),
          ((0.3, 1.0, 0.4), 0.35, 0.0, 0, 0),
          ((0.3, 0.55, 1.0), 0.45, 0.0, 0, 0),
          ((0.75, 0.35, 1.0), 0.6, 0.35, 0, 0),
          ((1.0, 0.8, 0.3), 0.7, 0.55, 6, 0),
          ((1.0, 0.22, 0.12), 0.85, 0.5, 0, 16)]


def pulse_at(r: int, ph: float, t: float) -> float:
    """Яркость свечения рамки редкости r в миг t (0..1) со сдвигом фазы ph: мягкое дыхание раз за цикл, без мигания."""
    if r == 5:                                         # мифическое — то же дыхание с лёгкой неровностью
        return 0.72 + 0.2 * math.sin(2 * math.pi * (t + ph)) + 0.08 * math.sin(2 * math.pi * (2 * t + 3 * ph))
    return 0.72 + 0.28 * math.sin(2 * math.pi * (t + ph))


def cell(layout: str, item: int, rarity: int) -> tuple:
    """Рамка ячейки (x0, y0, x1, y1) предмета item (0 шлем … 7 амулет) редкости rarity (0 обычное … 5 мифическое)."""
    L = LAYOUTS[layout]
    r, c = (rarity, item) if L["by"] == "row" else (item, rarity)
    (x0, x1), (y0, y1) = L["cols"][c], L["rows"][r]
    return x0, y0, x1, y1


def render(src: str, layout: str = "v2") -> list:
    """Кадры анимации листа (PIL RGB, размер листа)."""
    L = LAYOUTS[layout]
    base = np.asarray(Image.open(src).convert("RGB"), np.float32) / 255
    H, W, _ = base.shape
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    lum = base.mean(2)
    rng = np.random.default_rng(7)
    cells = []
    for r, (y0, y1) in enumerate(L["rows"]):
        for c, (x0, x1) in enumerate(L["cols"]):
            rar = r if L["by"] == "row" else c
            sl = (slice(y0, y1), slice(x0, x1))
            x, y = xx[sl] - x0, yy[sl] - y0
            w, h = x1 - x0, y1 - y0
            edge = np.minimum(np.minimum(x, w - x), np.minimum(y, h - y))
            cells.append(dict(r=rar, sl=sl, w=w, h=h, x=x, y=y, ph=c * 0.11 + r * 0.07,
                              border=np.exp(-edge / 7.0)[..., None],
                              line=np.clip(1.6 - edge, 0, 1)[..., None],
                              diag=(x + y) / (w + h),
                              item=np.clip((lum[sl] - 0.12) * 1.6, 0, 1)[..., None],
                              sparks=rng.uniform([0.15, 0.15, 0], [0.85, 0.85, 1], (RARITY[rar][3], 3)),
                              embers=rng.uniform([0.1, 0, 0, 1.2], [0.9, 1, 1, 2.6], (RARITY[rar][4], 4))))
    gems = [(GEM_X, (y0 + y1) / 2) for y0, y1 in L["rows"]] if L["gems"] else []
    frames = []
    for f in range(FRAMES):
        t = f / FRAMES
        img = base.copy()
        for k in cells:
            col, a_border, a_sweep, _, _ = RARITY[k["r"]]
            col = np.array(col, np.float32)
            sl, ph = k["sl"], k["ph"]
            if not L["gems"]:                            # лист без рамок — тонкая постоянная рамка цветом редкости
                img[sl] = img[sl] * (1 - k["line"] * 0.85) + k["line"] * 0.85 * col * (0.55 if a_border == 0 else 0.9)
            if a_border == 0:
                continue
            pulse = pulse_at(k["r"], ph, t)
            add = k["border"] * col * (a_border * pulse)
            if a_sweep:
                s = ((t + ph) % 1.0) * 1.6 - 0.3          # полоса света по диагонали, вне ячейки — пауза цикла
                band = np.exp(-((k["diag"] - s) / 0.06) ** 2)[..., None]
                add = add + band * k["item"] * (0.5 + 0.5 * col) * a_sweep
            x, y = k["x"], k["y"]
            for sx, sy, sp in k["sparks"]:              # легендарное — мерцающие звёздочки
                tw = max(0.0, math.sin(2 * math.pi * (t * 2 + sp))) ** 8
                if tw > 0.01:
                    d2 = (x - sx * k["w"]) ** 2 + (y - sy * k["h"]) ** 2
                    star = np.exp(-d2 / 4.0) + 0.35 * np.exp(-((x - sx * k["w"]) ** 2) / 1.5 - (y - sy * k["h"]) ** 2 / 40) \
                        + 0.35 * np.exp(-((y - sy * k["h"]) ** 2) / 1.5 - (x - sx * k["w"]) ** 2 / 40)
                    add = add + star[..., None] * tw * np.array((1, 0.92, 0.7), np.float32)
            for ex, ey, eph, size in k["embers"]:        # мифическое — угли летят вверх, целое число пролётов за цикл
                p = (ey + t) % 1.0
                cx = ex * k["w"] + 6 * math.sin(2 * math.pi * (t * 2 + eph))
                cy = k["h"] * (1 - p)
                fade = math.sin(math.pi * p)
                d2 = (x - cx) ** 2 + (y - cy) ** 2
                add = add + (np.exp(-d2 / (size * size)) * fade)[..., None] * np.array((1, 0.45, 0.15), np.float32)
            img[sl] += add
        for r, (gx, gy) in enumerate(gems):              # самоцветы рядов пульсируют своим цветом
            col, a_border = np.array(RARITY[r][0], np.float32), RARITY[r][1]
            if a_border:
                sl = (slice(int(gy - 45), int(gy + 45)), slice(0, 100))
                d2 = (xx[sl] - gx) ** 2 + (yy[sl] - gy) ** 2
                img[sl] += np.exp(-d2 / 500)[..., None] * col * a_border * 0.6 * (0.5 + 0.5 * math.sin(2 * math.pi * (t + r * 0.1)))
        frames.append(Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8)))
    return frames


def main(src: str, out: str, layout: str = "v2"):
    frames = render(src, layout)
    W, H = frames[0].size
    k = 1024 / max(W, H)
    frames[0].save(out + ".webp", save_all=True, append_images=frames[1:], duration=MS, loop=0, quality=88, method=4)
    small = [fr.resize((round(W * k), round(H * k)), Image.LANCZOS) for fr in frames]
    pal = [fr.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG) for fr in small]
    pal[0].save(out + ".gif", save_all=True, append_images=pal[1:], duration=MS, loop=0, optimize=True, disposal=1)
    print("saved", out + ".webp", out + ".gif")


if __name__ == "__main__":
    main(*sys.argv[1:4])
