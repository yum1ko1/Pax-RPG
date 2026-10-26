"""Маски ударов (GPT-референсы в hit_src/, белое на чёрном) → mods/pax_rpg/textures/vfx/hit/*.png для vfx_hit.gdshader.
R — форма (яркость мазка), G — порядок эрозии: где G выше, там мазок живёт дольше (шейдер съедает по порогу progress).
thrust / slash — хвост тает первым, остриё последним (градиент вдоль U + шум, рвёт край); impact — гаснет от лучей
к сердцевине; ring — рвётся пятнами шума. Обрезка по рамке формы — меньше пустых пикселей. Детерминированно.
python3 pax_rpg/dev/vfx/make_hit_masks.py"""
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(os.path.dirname(HERE))
SRC = os.path.join(HERE, "hit_src")
OUT = os.path.join(os.path.dirname(ROOT), "mods", "pax_rpg", "textures", "vfx", "hit")
rng = np.random.default_rng(2077)


def fbm(h, w, base=4, oct=5):
    r, a, tot = np.zeros((h, w), np.float32), 1.0, 0.0
    for o in range(oct):
        n = base * 2 ** o
        g = (rng.random((n, n)) * 255).astype(np.uint8)
        r += a * np.asarray(Image.fromarray(g).resize((w, h), Image.BICUBIC), np.float32) / 255
        tot += a
        a *= 0.5
    r /= tot
    return (r - r.min()) / max(1e-6, r.max() - r.min())


def load(name):
    return np.asarray(Image.open(os.path.join(SRC, name)).convert("L"), np.float32) / 255


def crop(m, pad=8, thr=0.04):
    ys, xs = np.where(m > thr)
    y0, y1 = max(0, ys.min() - pad), min(m.shape[0], ys.max() + pad)
    x0, x1 = max(0, xs.min() - pad), min(m.shape[1], xs.max() + pad)
    return m[y0:y1, x0:x1]


def square(m):
    h, w = m.shape
    s = max(h, w)
    o = np.zeros((s, s), np.float32)
    o[(s - h) // 2:(s - h) // 2 + h, (s - w) // 2:(s - w) // 2 + w] = m
    return o


def save(name, shape, ero, size):
    h, w = shape.shape
    rgb = np.dstack([shape, ero, np.zeros_like(shape)])
    im = Image.fromarray((np.clip(rgb, 0, 1) * 255).astype(np.uint8), "RGB").resize(size, Image.LANCZOS)
    im.save(os.path.join(OUT, name + ".png"))
    print(name, size)


def strip(name, src, size):
    m = crop(load(src))
    h, w = m.shape
    m = m * np.clip(np.minimum(np.arange(w) / 24.0, (w - 1 - np.arange(w)) / 24.0), 0, 1)[None, :]   # без среза у края
    u = np.linspace(0.0, 1.0, w, dtype=np.float32)[None, :].repeat(h, 0)
    save(name, m, 0.62 * u + 0.38 * fbm(h, w, 6), size)


def radial(name, src, size, core_lives):
    m = square(crop(load(src)))
    s = m.shape[0]
    y, x = np.mgrid[0:s, 0:s].astype(np.float32)
    r = np.hypot(x - s / 2, y - s / 2) / (s / 2)
    edge = np.clip(np.minimum.reduce([x, y, s - 1 - x, s - 1 - y]) / 16.0, 0, 1)
    m = m * edge
    ero = (0.6 * (1.0 - np.clip(r, 0, 1)) + 0.4 * fbm(s, s, 5)) if core_lives else fbm(s, s, 6)
    save(name, m, ero, size)


os.makedirs(OUT, exist_ok=True)
strip("thrust", "mask_thrust.png", (1024, 256))
strip("slash", "mask_slash.png", (1024, 256))
radial("impact", "mask_impact.png", (512, 512), True)
radial("ring", "mask_ring.png", (512, 512), False)
