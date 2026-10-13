"""Флипбуки эффектов (8×8 кадров по 128 px) → mods/pax_rpg/textures/vfx/*.png.
smoke — клуб дыма: растёт, клубится (сдвиг шума по времени), с запечённым освещением сверху-сбоку (объём);
fire — язык пламени: каплевидная маска, шум бежит вверх, цвет по жару (белый → жёлтый → оранжевый → красный);
glow — мягкий ореол. Детерминированно.  python3 pax_rpg/dev/vfx/make_flipbooks.py"""
import os
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
OUT = os.path.join(ROOT, "mods", "pax_rpg", "textures", "vfx")
N, F = 128, 8
rng = np.random.default_rng(1047)
G = rng.random((32, 32, 32))


def vnoise(x, y, z):
    xi, yi, zi = np.floor(x).astype(int), np.floor(y).astype(int), np.floor(z).astype(int)
    xf, yf, zf = x - xi, y - yi, z - zi
    s = lambda t: t * t * (3 - 2 * t)
    u, v, w = s(xf), s(yf), s(zf)
    def g(a, b, c):
        return G[(xi + a) % 32, (yi + b) % 32, (zi + c) % 32]
    l = lambda a, b, t: a + (b - a) * t
    return l(l(l(g(0, 0, 0), g(1, 0, 0), u), l(g(0, 1, 0), g(1, 1, 0), u), v),
             l(l(g(0, 0, 1), g(1, 0, 1), u), l(g(0, 1, 1), g(1, 1, 1), u), v), w)


def fbm(x, y, z, oct=5):
    r, a, f = 0.0, 0.5, 1.0
    for _ in range(oct):
        r = r + a * vnoise(x * f, y * f, z * f)
        a *= 0.5; f *= 2.03
    return r


yy, xx = np.mgrid[0:N, 0:N] / (N - 1) * 2 - 1          # -1..1, y вниз


def smoke_frame(t):
    sc = 0.7 + 0.35 * t                                  # растёт
    x, y = xx / sc, yy / sc
    wx = fbm(x * 2 + 3, y * 2, t * 1.5) - 0.5            # клубление: искривление пространства
    wy = fbm(x * 2, y * 2 + 7, t * 1.5 + 4) - 0.5
    d = np.sqrt((x + wx * 0.7) ** 2 + (y + wy * 0.7) ** 2)
    dens = np.clip((1.05 - d) * 1.5, 0, 1) * (0.55 + fbm(x * 1.7 + wx, y * 1.7 + wy, t * 1.2 + 9))
    dens = np.clip(dens - 0.22, 0, 1) * 1.5
    # запечённый свет: плотность, сдвинутая к источнику (сверху-слева) — чем больше впереди, тем темнее
    sh = np.roll(np.roll(dens, 9, 0), 9, 1)
    light = np.clip(1.0 - (sh - dens) * 1.4 - sh * 0.35, 0.35, 1.0)
    a = np.clip(dens, 0, 1) * (1 - t) ** 0.8 * np.clip(t * 6, 0, 1)
    c = 0.55 + 0.45 * light
    return np.dstack([c, c, c, a])


def fire_frame(t):
    ph = t * 2 * np.pi
    x, y = xx, yy
    # язык: шире внизу, к верху сужается; шум уходит вверх (кадры зациклены по фазе)
    up = (y + 1) / 2                                     # 0 — верх, 1 — низ
    width = 0.2 + 0.62 * up ** 0.7
    n = fbm(x * 3.2 + 0.4 * np.sin(ph), y * 2.6 + t * 4.0, 3 + 0.6 * np.cos(ph), 5)
    sway = (n - 0.5) * 0.8 * (1 - up)
    body = np.clip(1 - np.abs(x - sway) / width, 0, 1) * np.clip(up * 1.3 + 0.05, 0, 1)
    body = body * np.clip(1.2 - np.maximum(0, y - 0.6) * 3, 0, 1)
    heat = np.clip(body * (0.35 + 1.1 * n) - 0.3, 0, 1) * 1.7
    r = np.clip(heat * 2.2, 0, 1)
    g = np.clip(heat * 1.6 - 0.25, 0, 1)
    b = np.clip(heat * 1.4 - 0.85, 0, 1)
    a = np.clip(heat * 1.8, 0, 1)
    return np.dstack([r, g, b, a])


def atlas(fn, name):
    img = np.zeros((N * F, N * F, 4))
    for i in range(F * F):
        fr = fn(i / (F * F - 1) if name == "smoke" else i / (F * F))
        r, c = divmod(i, F)
        img[r * N:(r + 1) * N, c * N:(c + 1) * N] = fr
    Image.fromarray((np.clip(img, 0, 1) * 255).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + "_8x8.png"))


os.makedirs(OUT, exist_ok=True)
atlas(smoke_frame, "smoke")
atlas(fire_frame, "fire")
d = np.sqrt(xx ** 2 + yy ** 2)
gl = np.clip(1 - d, 0, 1) ** 2.2
Image.fromarray((np.dstack([np.ones_like(gl), np.ones_like(gl), np.ones_like(gl), gl]) * 255).astype(np.uint8), "RGBA").save(
    os.path.join(OUT, "glow.png"))
print("ok", OUT)
