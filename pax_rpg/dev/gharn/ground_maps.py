"""Текстуры земли и кладки дорог Гхарна: шов → бесшовно, рельеф (нормали) и шероховатость из яркости.
Источник — картинки Meshy (text-to-image, промпты — в заметке «Гхарн — материалы и текстуры»).
    python pax_rpg/dev/gharn/ground_maps.py ground.png cobble.png
→ mods/pax_rpg/models/gharn/tex/{ground,cobble}{,_n,_r,_h}.jpg (2048², нормали — OpenGL, +Y вверх)
"""
import os
import sys
import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
OUT = os.path.join(ROOT, "mods", "pax_rpg", "models", "gharn", "tex")
SIZE = 2048


def seamless(a, zone=0.18):
    """Края — из копии со сдвигом на полтекстуры (её края — середина оригинала), плавный переход в полосе zone."""
    h, w = a.shape[:2]
    sh = np.roll(np.roll(a, h // 2, 0), w // 2, 1)
    def ramp(n):
        x = np.minimum(np.arange(n), n - 1 - np.arange(n)) / (n * zone)
        return np.clip(x, 0, 1)
    m = np.minimum.outer(ramp(h), ramp(w))
    m = m * m * (3 - 2 * m)
    return a * m[..., None] + sh * (1 - m[..., None])


def maps(name, src, strength, rough_lo, rough_hi, edge_err):
    img = np.asarray(Image.open(src).convert("RGB")).astype(np.float32)
    err = (abs(img[:, 0] - img[:, -1]).mean() + abs(img[0] - img[-1]).mean()) / 2
    inner = abs(img[:, 10] - img[:, 11]).mean()
    if err > inner * edge_err:                      # края не сходятся — сшить
        img = seamless(img)
    col = Image.fromarray(img.clip(0, 255).astype(np.uint8)).resize((SIZE, SIZE), Image.LANCZOS)
    col.save(os.path.join(OUT, name + ".jpg"), quality=92)
    lum = np.asarray(col.convert("L").filter(ImageFilter.GaussianBlur(1.6))).astype(np.float32) / 255.0
    big = np.asarray(col.convert("L").filter(ImageFilter.GaussianBlur(9))).astype(np.float32) / 255.0
    hgt = np.clip(lum - big * 0.6, 0, 1)                 # мелкий рельеф: камни выше грязи
    dx = (np.roll(hgt, -1, 1) - np.roll(hgt, 1, 1)) * strength
    dy = (np.roll(hgt, -1, 0) - np.roll(hgt, 1, 0)) * strength
    n = np.dstack([-dx, dy, np.ones_like(dx)])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    Image.fromarray(((n * 0.5 + 0.5) * 255).astype(np.uint8)).save(os.path.join(OUT, name + "_n.jpg"), quality=95)
    Image.fromarray((hgt / max(hgt.max(), 1e-3) * 255).astype(np.uint8)).save(os.path.join(OUT, name + "_h.jpg"), quality=90)
    r = rough_hi - (rough_hi - rough_lo) * (1 - lum)     # тёмное (мокрая грязь) — глаже
    Image.fromarray((np.clip(r, 0, 1) * 255).astype(np.uint8)).save(os.path.join(OUT, name + "_r.jpg"), quality=90)
    print(name, "seam err %.1f / inner %.1f" % (err, inner))


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    maps("ground", sys.argv[1], 9.0, 0.82, 0.97, 1.3)
    maps("cobble", sys.argv[2], 14.0, 0.55, 0.92, 1.3)
