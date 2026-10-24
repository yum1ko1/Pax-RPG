"""Живой арт героя для центра инвентаря (hero_center_v1.webp): волосы колышутся волной от макушки к кончикам,
полы жакета чуть развеваются, фигура едва заметно дышит; лицо неподвижно.
    python hero_idle.py <арт героя> <выход без расширения>
→ <выход>.gif (512 px) и <выход>.webp (полный размер). render() — кадры для сборки инвентаря (inventory_demo.py).
Области движения — многоугольники в пикселях арта 1024×1536 (размечены по hero_center_v1).
"""
import math
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

FRAMES, MS = 48, 85                                    # ~4 с на цикл
ROOT = (560, 190)                                      # макушка: отсюда волна идёт к кончикам
HAIR = [[(570, 240), (600, 170), (660, 200), (760, 340), (880, 460), (950, 530), (860, 580), (760, 600),
         (680, 500), (610, 400), (590, 320)],                                  # длинные пряди справа
        [(470, 160), (520, 130), (600, 140), (640, 200), (600, 240), (520, 230)],  # макушка и хвост
        [(455, 220), (500, 220), (510, 400), (470, 420)]]                     # прядь слева
COAT = [[(720, 660), (840, 760), (960, 880), (950, 1060), (860, 940), (760, 840), (700, 760)]]  # полы жакета справа
FACE = (480, 200, 580, 340)                            # лицо и шея — неподвижны
BODY = [[(440, 240), (640, 240), (720, 330), (740, 620), (640, 700), (430, 700), (390, 600), (400, 330)]]  # дыхание
SPEAR = ((940, 0), (690, 360))                         # древко копья за плечом — неподвижно


def field(size, polys, blur):
    m = Image.new("L", size, 0)
    d = ImageDraw.Draw(m)
    for p in polys:
        d.polygon(p, fill=255)
    return np.asarray(m.filter(ImageFilter.GaussianBlur(blur)), np.float32) / 255


def sample(img, x, y):
    """Билинейная выборка img (H, W, C) в точках x, y."""
    H, W, _ = img.shape
    x = np.clip(x, 0, W - 1.001)
    y = np.clip(y, 0, H - 1.001)
    x0, y0 = x.astype(np.int32), y.astype(np.int32)
    fx, fy = (x - x0)[..., None], (y - y0)[..., None]
    a, b = img[y0, x0], img[y0, x0 + 1]
    c, d = img[y0 + 1, x0], img[y0 + 1, x0 + 1]
    return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy


def render(src: str, frames: int = FRAMES) -> list:
    im = Image.open(src).convert("RGB")
    W, H = im.size
    sx, sy = W / 1024, H / 1536                         # разметка — для 1024×1536
    sc = lambda polys: [[(x * sx, y * sy) for x, y in p] for p in polys]
    base = np.asarray(im, np.float32)
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    dist = np.hypot(xx - ROOT[0] * sx, yy - ROOT[1] * sy) / (500 * sy)   # 0 у макушки → ~1 у кончиков
    face = field((W, H), sc([[(FACE[0], FACE[1]), (FACE[2], FACE[1]), (FACE[2], FACE[3]), (FACE[0], FACE[3])]]), 18 * sx)
    m = Image.new("L", (W, H), 0)
    ImageDraw.Draw(m).line([(x * sx, y * sy) for x, y in SPEAR], fill=255, width=round(46 * sx))
    spear = np.asarray(m.filter(ImageFilter.GaussianBlur(10 * sx)), np.float32) / 255
    hair = field((W, H), sc(HAIR), 22 * sx) * np.clip(dist, 0.15, 1.2) * (1 - face) * (1 - spear)
    coat = field((W, H), sc(COAT), 26 * sx) * np.clip((yy - 660 * sy) / (400 * sy), 0, 1)
    torso = field((W, H), sc(BODY), 30 * sx) * np.clip((700 * sy - yy) / (460 * sy), 0, 1) * (1 - spear)
    out = []
    for f in range(frames):
        t = f / frames
        w = 2 * math.pi * t
        phase = w - dist * 3.2                          # волна бежит от макушки к кончикам
        dx = hair * (13 * sx) * np.sin(phase) + coat * (6 * sx) * np.sin(w - 1.3 - (yy / H) * 2.5)
        dy = hair * (5 * sy) * np.cos(phase) + coat * (2 * sy) * np.cos(w - 1.3) \
            - torso * (2.2 * sy) * (0.5 - 0.5 * math.cos(w))   # вдох — плечи чуть вверх
        img = sample(base, xx - dx, yy - dy)
        out.append(Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)))
    return out


def main(src: str, out: str):
    fr = render(src)
    W, H = fr[0].size
    fr[0].save(out + ".webp", save_all=True, append_images=fr[1:], duration=MS, loop=0, quality=90, method=4)
    small = [f.resize((512, round(H * 512 / W)), Image.LANCZOS) for f in fr]
    pal = [f.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.FLOYDSTEINBERG) for f in small]
    pal[0].save(out + ".gif", save_all=True, append_images=pal[1:], duration=MS, loop=0, optimize=True, disposal=1)
    print("saved", out + ".webp/.gif")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
