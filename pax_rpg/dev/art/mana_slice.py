"""Нарезка картинок маны (ui_src/mana_*.webp) → ui/mana_*_s.png для прототипа подсказки.
    python mana_slice.py <папка с 35–38.webp> <ui>
35 — рамка слота, 36 — уголки окна, 37 — ромб / полоса / плашка, 38 — 16 частиц."""
import sys, os
import numpy as np
from PIL import Image
src, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
def trim(im, t=6, pad=4):
    a = np.asarray(im)[..., 3]; ys, xs = np.where(a > t)
    return im.crop((max(xs.min() - pad, 0), max(ys.min() - pad, 0), min(xs.max() + pad + 1, im.width), min(ys.max() + pad + 1, im.height)))
def fit(im, w=None, h=None):
    s = (w / im.width) if w else (h / im.height)
    return im.resize((max(1, round(im.width * s)), max(1, round(im.height * s))), Image.LANCZOS)
def save(im, name): im.save(os.path.join(out, name), optimize=True); print(name, im.size)
# 35 — рамка слота целиком (линия рамки ≈ 10,5 % от края картинки)
save(fit(Image.open(f"{src}/35.webp").convert("RGBA"), 320), "mana_rim_s.png")
# 36 — четыре угла
im = Image.open(f"{src}/36.webp").convert("RGBA")
for name, box in [("tl", (97, 33, 675, 568)), ("tr", (816, 33, 1399, 574)), ("bl", (97, 568, 675, 1044)), ("br", (816, 574, 1399, 1044))]:
    save(fit(trim(im.crop(box)), 200), f"mana_c_{name}_s.png")
# 37 — ромб, полоса, плашка в 3 части
im = Image.open(f"{src}/37.webp").convert("RGBA")
save(fit(trim(im.crop((40, 180, 260, 470))), h=48), "mana_gem_s.png")
save(fit(trim(im.crop((280, 180, 1290, 470))), 420), "mana_strip_s.png")
# плашка: левый край с ромбом | середина | правый край — склеены в одну картинку под border-image (края 63 и 51 px)
parts = [fit(im.crop((x0, 180, x1, 460)), h=72) for x0, x1 in [(1300, 1545), (1560, 1780), (1790, 1990)]]
badge = Image.new("RGBA", (sum(p.width for p in parts), 72)); x = 0
for p in parts: badge.paste(p, (x, 0)); x += p.width
print("badge caps", parts[0].width, parts[2].width); save(badge, "mana_badge_s.png")
# 38 — 16 частиц
im = Image.open(f"{src}/38.webp").convert("RGBA"); c = im.width / 4
for i in range(16):
    y, x = divmod(i, 4)
    save(fit(trim(im.crop((round(x * c), round(y * c), round((x + 1) * c), round((y + 1) * c)))), 40), f"mana_p{i}_s.png")
