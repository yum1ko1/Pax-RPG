"""Ткани белья Гхарна (сушится над улицами): узоры Востока в палитре города — волны сэйгайха, конопляный лист
асаноха, точки сибори, полосы, грубый лён с заплатой. Переплетение нитей, подрубленная кромка, выцветание сверху,
грязь у низа, складки от прищепок. Пишет mods/pax_rpg/textures/laundry/cloth_<n>.png (256×256, тайл не нужен).
    python3 pax_rpg/dev/gharn/laundry_tex.py"""
import math
import os
import random

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
OUT = os.path.join(ROOT, "mods", "pax_rpg", "textures", "laundry")
N = 256
# палитра Гхарна: глубокий алый лак, индиго, охра, кость, умбра, выцветший зелёный чай
RED, INDIGO, OCHRE, BONE, UMBER, TEA = (0.55, 0.1, 0.09), (0.12, 0.15, 0.32), (0.66, 0.45, 0.17), \
    (0.82, 0.76, 0.62), (0.32, 0.22, 0.15), (0.36, 0.4, 0.28)


def weave(rng):
    """Переплетение: поперечные и продольные нити разной толщины + шум волокна."""
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    warp = 0.5 + 0.5 * np.sin(x * 2.1 + rng.random() * 6)
    weft = 0.5 + 0.5 * np.sin(y * 2.0 + rng.random() * 6)
    check = ((np.floor(x / 1.5) + np.floor(y / 1.5)) % 2)
    fiber = np.array(Image.effect_noise((N, N), 40).filter(ImageFilter.GaussianBlur(0.6)), np.float32) / 255.0
    return 0.86 + 0.07 * (warp * check + weft * (1 - check)) + 0.1 * (fiber - 0.5)


def folds(rng):
    """Складки: полотно висит на двух прищепках — вертикальные мягкие волны, сильнее у верха."""
    y, x = np.mgrid[0:N, 0:N].astype(np.float32) / N
    f = np.zeros((N, N), np.float32)
    for _ in range(4):
        k = rng.uniform(2.5, 7.0)
        f += np.sin(x * k * math.pi + rng.uniform(0, 6)) * rng.uniform(0.3, 1.0)
    return 1.0 + 0.07 * f / 4 * (1.2 - y)


def seigaiha(base, ink):
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    r = 32.0
    img = np.ones((N, N), np.float32)
    for row in range(-1, int(N / (r * 0.5)) + 2):
        cy = row * r * 0.5
        off = (row % 2) * r
        for cx in np.arange(-r + off, N + r, 2 * r):
            d = np.sqrt((x - cx) ** 2 + (y - cy) ** 2)
            arc = (y <= cy + 0.5) & (d < r)               # веер — верхний полукруг; нижний ряд ложится поверх
            rings = (np.sin(d / r * math.pi * 4.0 + 0.6) > 0.25) & arc
            img = np.where(arc, np.where(rings, 0.0, 1.0), img)
    return mix(base, ink, 1 - img)


def asanoha(base, ink):
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    s = 42.0
    lines = np.zeros((N, N), np.float32)
    for ang in (0, 60, 120):
        a = math.radians(ang)
        u = x * math.cos(a) + y * math.sin(a)
        lines = np.maximum(lines, (np.abs(((u / s) % 1.0) - 0.5) < 0.035).astype(np.float32))
    for ang in (30, 90, 150):                            # лучи звезды конопляного листа
        a = math.radians(ang)
        u = x * math.cos(a) + y * math.sin(a)
        lines = np.maximum(lines, 0.7 * (np.abs(((u / (s * 1.732)) % 1.0) - 0.5) < 0.02).astype(np.float32))
    return mix(base, ink, lines)


def shibori(base, ink, rng):
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    m = np.zeros((N, N), np.float32)
    step = 28
    for cy in range(step // 2, N, step):
        for cx in range(step // 2 + (cy // step % 2) * step // 2, N, step):
            jx, jy = rng.uniform(-3, 3), rng.uniform(-3, 3)
            d = np.sqrt((x - cx - jx) ** 2 + (y - cy - jy) ** 2)
            ring = np.exp(-((d - 6.5) ** 2) / 5.0)       # белое кольцо перевязки, внутри — краска
            m = np.maximum(m, ring)
    blur = np.array(Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(1.4)), np.float32) / 255
    return mix(ink, base, np.clip(blur * 1.4, 0, 1))


def stripes(base, ink, rng):
    y, x = np.mgrid[0:N, 0:N].astype(np.float32)
    w = rng.choice([10, 14, 20])
    s = ((np.floor(y / w) % 3) == 0).astype(np.float32)
    s = np.maximum(s, 0.6 * ((np.floor(y / w) % 3) == 1) * ((x // 4) % 2))
    return mix(base, ink, s)


def linen(base, patch, rng):
    out = np.repeat(np.array(base, np.float32)[None, None, :], N, 0).repeat(N, 1)
    px, py, pw, ph = rng.integers(40, 150), rng.integers(80, 170), rng.integers(40, 70), rng.integers(35, 60)
    out[py:py + ph, px:px + pw] = np.array(patch, np.float32) * rng.uniform(0.85, 1.0, (ph, pw, 1)).astype(np.float32)
    st = np.zeros((N, N), bool)                           # стежки по краю заплаты
    for t in range(0, pw, 6):
        st[py, px + t:px + t + 3] = True
        st[py + ph - 1, px + t:px + t + 3] = True
    for t in range(0, ph, 6):
        st[py + t:py + t + 3, px] = True
        st[py + t:py + t + 3, px + pw - 1] = True
    out[st] = np.array(BONE, np.float32) * 0.8
    return out


def mix(a, b, k):
    a = np.array(a, np.float32)
    b = np.array(b, np.float32)
    k = np.asarray(k, np.float32)[..., None]
    if a.ndim == 1:
        a = np.broadcast_to(a, (N, N, 3))
    if b.ndim == 1:
        b = np.broadcast_to(b, (N, N, 3))
    return a * (1 - k) + b * k


def finish(rgb, rng):
    y = np.mgrid[0:N, 0:N][0].astype(np.float32) / N
    rgb = rgb * weave(rng)[..., None] * folds(rng)[..., None]
    rgb = rgb * (1.0 + 0.1 * (1 - y))[..., None]          # верх выгорел на солнце
    dirt = np.clip((y - 0.72) / 0.28, 0, 1) ** 1.6        # низ — пыль улицы
    rgb = rgb * (1 - 0.35 * dirt)[..., None] + np.array(UMBER, np.float32) * 0.35 * dirt[..., None] * 0.3
    hem = (np.mgrid[0:N, 0:N][0] < 7) | (np.mgrid[0:N, 0:N][0] > N - 8)   # подрубленная кромка темнее
    rgb[hem] *= 0.78
    return Image.fromarray((np.clip(rgb, 0, 1) ** (1 / 1.0) * 255).astype(np.uint8))


def main():
    os.makedirs(OUT, exist_ok=True)
    rng = np.random.default_rng(7)
    kinds = [lambda: seigaiha(INDIGO, BONE), lambda: seigaiha(RED, OCHRE),
             lambda: asanoha(BONE, INDIGO), lambda: asanoha(TEA, BONE),
             lambda: shibori(BONE, INDIGO, rng), lambda: shibori(BONE, RED, rng),
             lambda: stripes(OCHRE, UMBER, rng), lambda: stripes(BONE, RED, rng),
             lambda: linen(BONE, OCHRE, rng), lambda: linen(UMBER, BONE, rng)]
    for i, k in enumerate(kinds):
        img = finish(k(), rng)
        img.save(os.path.join(OUT, "cloth_%d.png" % i))
    print(len(kinds), "тканей →", OUT)


main()
