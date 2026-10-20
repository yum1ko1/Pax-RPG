"""Рамки HUD (Meshy, на хромакее) → PNG с прозрачностью: фон — цвет углов, альфа — по удалению от него, зелёный
отсвет снят (despill); обрезка по содержимому; поиск тёмных каналов под полосы (доли картинки)."""
import json
import sys

import numpy as np
from PIL import Image

src, dst = sys.argv[1], sys.argv[2]
mode = sys.argv[3] if len(sys.argv) > 3 else "h"
im = np.asarray(Image.open(src).convert("RGB")).astype(np.float32) / 255.0
h, w, _ = im.shape
corners = np.concatenate([im[:8, :8].reshape(-1, 3), im[:8, -8:].reshape(-1, 3), im[-8:, :8].reshape(-1, 3), im[-8:, -8:].reshape(-1, 3)])
bg = np.median(corners, axis=0)
d = np.linalg.norm(im - bg, axis=2)
# зелёность: насколько зелёный выше максимума красного и синего
gx = im[:, :, 1] - np.maximum(im[:, :, 0], im[:, :, 2])
gb = bg[1] - max(bg[0], bg[2])
a = np.clip((d - 0.12) / 0.22, 0.0, 1.0)
a = np.minimum(a, np.clip(1.0 - (gx - 0.05) / max(gb * 0.6, 0.05), 0.0, 1.0)) if gb > 0.1 else a
rgb = im.copy()
m = np.maximum(rgb[:, :, 0], rgb[:, :, 2])
rgb[:, :, 1] = np.minimum(rgb[:, :, 1], m + 0.03)            # despill
ys, xs = np.where(a > 0.05)
y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
pad = 2
y0, x0 = max(0, y0 - pad), max(0, x0 - pad)
y1, x1 = min(h, y1 + pad), min(w, x1 + pad)
rgba = np.dstack([rgb, a])[y0:y1, x0:x1]
Image.fromarray((rgba * 255).astype(np.uint8), "RGBA").save(dst)
ch, cw = rgba.shape[:2]
# тёмные каналы: непрозрачные и очень тёмные пиксели
lum = rgba[:, :, :3] @ np.array([0.3, 0.55, 0.15])
dark = (rgba[:, :, 3] > 0.9) & (lum < 0.11)
info = {"size": [cw, ch]}
if mode == "h":
    rows = dark.sum(axis=1)
    cy = int(np.argmax(rows))
    row = dark[cy]
    xs_ = np.where(row)[0]
    # самый длинный сплошной отрезок в строке
    best, cur, st = (0, 0, 0), 0, 0
    for i in range(cw):
        if row[i]:
            if cur == 0:
                st = i
            cur += 1
            if cur > best[0]:
                best = (cur, st, i)
        else:
            cur = 0
    xa, xb = best[1], best[2]
    col = dark[:, (xa + xb) // 2]
    yy = np.where(col)[0]
    # сплошной отрезок вокруг cy
    ya = cy
    while ya > 0 and col[ya - 1]:
        ya -= 1
    yb = cy
    while yb < ch - 1 and col[yb + 1]:
        yb += 1
    info["slot"] = [round(xa / cw, 4), round(ya / ch, 4), round((xb - xa) / cw, 4), round((yb - ya) / ch, 4)]
elif mode == "v2":
    cols = dark.sum(axis=0)
    # два самых тёмных столбца-канала
    order = np.argsort(-cols)
    c1 = int(order[0])
    c2 = next(int(c) for c in order if abs(int(c) - c1) > cw * 0.08)
    slots = []
    for c in sorted([c1, c2]):
        col = dark[:, c]
        cy = int(np.where(col)[0][len(np.where(col)[0]) // 2])
        ya = cy
        while ya > 0 and col[ya - 1]:
            ya -= 1
        yb = cy
        while yb < ch - 1 and col[yb + 1]:
            yb += 1
        row = dark[(ya + yb) // 2]
        xa = c
        while xa > 0 and row[xa - 1]:
            xa -= 1
        xb = c
        while xb < cw - 1 and row[xb + 1]:
            xb += 1
        slots.append([round(xa / cw, 4), round(ya / ch, 4), round((xb - xa) / cw, 4), round((yb - ya) / ch, 4)])
    info["slots"] = slots
    # медальон: самая верхняя большая непрозрачная зона — центр круга по светлой «подложке»
print(json.dumps(info))
