"""Картинки лута и прокрутки → mods/pax_rpg/textures/loot/.
    python loot_slice.py <папка с 49–56> <textures/loot>
49 — клякса-полоса (тушь на белом), 50 — тушевое кольцо с драконом (на белом), 51 — разрез + брызги влево / вправо,
52 — катана-указатель, 53 — 6 подложек под вещи, 54 — золотая сфера, 55 — розовая, 56 — радужная."""
import os
import sys
import numpy as np
from PIL import Image

src, out = sys.argv[1], sys.argv[2]


def trim(im, t=10, pad=4):
    a = np.asarray(im)[..., 3]
    ys, xs = np.where(a > t)
    return im.crop((max(xs.min() - pad, 0), max(ys.min() - pad, 0), min(xs.max() + pad + 1, im.width), min(ys.max() + pad + 1, im.height)))


def fit(im, w=None, h=None):
    s = min(1.0, (w / im.width) if w else (h / im.height))
    return im.resize((round(im.width * s), round(im.height * s)), Image.LANCZOS)


def ink(path, white=False):
    """Тушь на белом → прозрачный фон: альфа = темнота пикселя; цвет — чёрный (или белый — под окраску)."""
    g = np.asarray(Image.open(path).convert("L")).astype(np.float32)
    a = np.clip((255.0 - g) * 1.15, 0, 255).astype(np.uint8)
    c = np.full(g.shape + (3,), 255 if white else 8, np.uint8)
    return Image.fromarray(np.dstack([c, a]), "RGBA")


def save(im, name):
    im.save(os.path.join(out, name), optimize=True)
    print(name, im.size)


save(fit(trim(ink(f"{src}/49.jpg")), w=1100), "ink_strip.png")
save(fit(trim(ink(f"{src}/50.jpg", white=True)), w=420), "ink_ring.png")
sl = Image.open(f"{src}/51.webp").convert("RGBA")
save(fit(trim(sl.crop((700, 0, 840, 600))), h=520), "slash.png")
save(fit(trim(sl.crop((280, 570, 880, 800))), w=360), "splat_l.png")
save(fit(trim(sl.crop((660, 790, 1260, 1020))), w=360), "splat_r.png")
save(fit(trim(Image.open(f"{src}/52.webp").convert("RGBA")), h=520), "katana.png")
bl = Image.open(f"{src}/53.webp").convert("RGBA")
for i in range(6):
    y, x = divmod(i, 3)
    save(fit(trim(bl.crop((x * 512, y * 512, x * 512 + 512, y * 512 + 512))), w=200), f"blot_{i}.png")
save(fit(trim(Image.open(f"{src}/54.webp").convert("RGBA")), w=160), "orb_gold.png")
save(fit(trim(Image.open(f"{src}/55.webp").convert("RGBA")), w=160), "orb_pink.png")
save(fit(trim(Image.open(f"{src}/56.webp").convert("RGBA")), w=200), "orb_rainbow.png")
