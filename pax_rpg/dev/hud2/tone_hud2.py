"""Рамки HUD v2 в тон игре: их рисовали по ночному GPT-макету (чёрный лак, кармин), а город днём — песок, персик,
дымка. Тон: чёрный лак → тёплый тёмно-ореховый и чуть прозрачный (сквозь панели видно мир), красный — приглушённый
лак ворот Гхарна, золото — чуть мягче, всё — с лёгкой тёплой дымкой, как у кадра игры.

    python tone_hud2.py <папка с исходными textures/hud2/*.png> <куда писать>
"""
import os, sys
import numpy as np
from PIL import Image

LIFT = np.array([0.15, 0.085, 0.075])     # чем становится чистый чёрный лак (тёмный лак столбов ворот в тени)
HAZE = np.array([0.89, 0.78, 0.67])       # тёплая дымка кадра игры (средний свет города)
HAZE_K = 0.04
SAT_RED = 0.72                            # насыщенность красного: доля от исходной
SAT_REST = 0.9
BODY_ALPHA = 0.93                         # тёмные панели — чуть прозрачные


def tone(im: Image.Image) -> Image.Image:
    a = np.asarray(im.convert('RGBA')).astype(np.float32) / 255.0
    rgb, al = a[..., :3], a[..., 3]
    lum = rgb @ np.array([0.2126, 0.7152, 0.0722])
    # насыщенность: красный приглушаем сильнее, золото и остальное — слегка
    mx, mn = rgb.max(-1), rgb.min(-1)
    red = np.clip((rgb[..., 0] - np.maximum(rgb[..., 1], rgb[..., 2])) / (mx + 1e-4) * 1.6, 0, 1) \
        * np.clip((mx - 0.18) / 0.25, 0, 1)
    k = SAT_REST + (SAT_RED - SAT_REST) * red
    rgb = lum[..., None] + (rgb - lum[..., None]) * k[..., None]
    # подъём чёрного: тёмное тянется к ореховому, светлое не трогаем
    dark = np.clip(1.0 - lum / 0.35, 0, 1) ** 1.5
    rgb = rgb + (LIFT - LIFT * np.clip(rgb / 0.35, 0, 1)) * dark[..., None]
    rgb = rgb * (1 - HAZE_K) + HAZE * HAZE_K
    # тёмные панели (не края, не золото) — чуть прозрачнее
    body = np.clip(1.0 - lum / 0.16, 0, 1)
    al = al * (1.0 - (1.0 - BODY_ALPHA) * body)
    out = np.dstack([np.clip(rgb, 0, 1), al])
    return Image.fromarray((out * 255 + 0.5).astype(np.uint8), 'RGBA')


def main(src: str, dst: str) -> None:
    os.makedirs(dst, exist_ok=True)
    for fn in sorted(os.listdir(src)):
        if fn.endswith('.png'):
            tone(Image.open(os.path.join(src, fn))).save(os.path.join(dst, fn), optimize=True)
            print(fn)


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
