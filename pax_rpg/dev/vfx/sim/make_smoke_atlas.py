"""Кадры клуба дыма (smoke_sim.py, свет с 6 сторон) → флипбук 8×8 для частиц дыма + карта движения.
  python make_smoke_atlas.py <папка кадров> <имя> [ширина кадра] [доля ширины кадра симуляции]
<имя>_a.png (RGBA): R — свет справа, G — сверху, B — спереди (со стороны камеры), A — плотность;
<имя>_b.png (RGB):  R — слева, G — снизу, B — сзади. Освещённость — без альфы (сколько света дошло в эту точку).
<имя>_flow.png (RG): куда сдвигается каждая точка к следующему кадру — шейдер «дотягивает» кадр к следующему.
Клуб в симуляции всплывает — кадр вырезается квадратом во всю ширину по плавной траектории его центра
(подъём в игре даёт сама частица, а в атласе клуб стоит на месте и только клубится и растёт).
Результат — mods/pax_rpg/textures/vfx/sim/."""
import os, sys, glob
import numpy as np
import cv2
from PIL import Image

src, name = sys.argv[1], sys.argv[2]
CW = int(sys.argv[3]) if len(sys.argv) > 3 else 160
CROP = float(sys.argv[4]) if len(sys.argv) > 4 else 0.7   # сторона квадрата — доля ширины кадра симуляции
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))
OUT = os.path.join(ROOT, "mods", "pax_rpg", "textures", "vfx", "sim")
os.makedirs(OUT, exist_ok=True)
L, G = 64, 8
FLOW_UV = 0.1                                      # 1.0 в карте = 0.1 кадра (shaders/vfx_smoke.gdshader → flow_uv)
DIRS = "rtflbk"


def load16(p):
    a = cv2.imread(p, cv2.IMREAD_UNCHANGED)
    if a is None:
        sys.exit("нет " + p)
    a = a.astype(np.float32) / 65535.0
    return a[..., [2, 1, 0, 3]]


frames = sorted(set(os.path.basename(p)[4:8] for p in glob.glob(os.path.join(src, "s_r_*.png"))))
assert len(frames) >= L, len(frames)
frames = frames[:L]
lum_w = np.array([0.2126, 0.7152, 0.0722], np.float32)
full = []                                          # [кадр] → (6 карт света, альфа), кадр симуляции целиком
for f in frames:
    maps, al = [], None
    for d in DIRS:
        s = load16(os.path.join(src, "s_%s_%s.png" % (d, f)))
        a = s[..., 3]
        al = a if al is None else np.maximum(al, a)
        maps.append(np.where(a > 1e-3, (s[..., :3] @ lum_w) / np.maximum(a, 1e-3), 0.0))
    full.append(np.stack(maps + [al], -1))
h, w = full[0].shape[:2]
ys = np.arange(h, dtype=np.float32)
cy = np.array([float(((r[..., 6] ** 2).sum(1) * ys).sum() / max((r[..., 6] ** 2).sum(), 1e-6)) for r in full])  # по густой шапке клуба
t = np.arange(L)
cy = np.polyval(np.polyfit(t, cy, 3), t)            # плавная траектория — без дрожи кадра
n = int(round(w * CROP))
x0 = (w - n) // 2
e = np.linspace(0.0, 1.0, n, dtype=np.float32)
vig = np.clip(np.minimum(e, 1.0 - e) / 0.12, 0.0, 1.0)
vig = (vig * vig * (3.0 - 2.0 * vig))
vig = np.minimum(vig[:, None], vig[None, :])        # мягко к краю квадрата: хвост клуба не обрезан ножом
raw = []
for r, c in zip(full, cy):
    y0 = int(round(c - n / 2))
    pad = np.zeros((n, n, 7), np.float32)
    a0, a1 = max(y0, 0), min(y0 + n, h)
    pad[a0 - y0:a1 - y0] = r[a0:a1, x0:x0 + n]
    pad[..., 6] *= vig
    raw.append(np.stack([cv2.resize(pad[..., c], (CW, CW), interpolation=cv2.INTER_AREA) for c in range(7)], -1))
edge = max(float(np.concatenate([r[[0, -1], :, 6].ravel(), r[:, [0, -1], 6].ravel()]).max()) for r in raw)
print("центр клуба, px: %.0f → %.0f; плотность на краю кадра %.2f" % (cy[0], cy[-1], edge))
# освещённость = свет/плотность; на тонком краю деление раздувает её — норма по 98% там, где дым заметен
pk = float(np.percentile(np.stack([r[..., :6] for r in raw])[np.stack([r[..., 6] for r in raw]) > 0.15], 98.0))
print("кадр", CW, "пик света", pk)
A = np.zeros((CW * G, CW * G, 4), np.float32)
B = np.zeros((CW * G, CW * G, 3), np.float32)
for i, r in enumerate(raw):
    y, x = divmod(i, G)
    sl = (slice(y * CW, (y + 1) * CW), slice(x * CW, (x + 1) * CW))
    m = np.clip(r[..., :6] / pk, 0, 1)
    A[sl] = np.concatenate([m[..., 0:3], r[..., 6:7]], -1)
    B[sl] = m[..., 3:6]
q = lambda a: (np.clip(a, 0, 1) * 255 + 0.5).astype(np.uint8)
Image.fromarray(q(A), "RGBA").save(os.path.join(OUT, name + "_a.png"), optimize=True)
Image.fromarray(q(B), "RGB").save(os.path.join(OUT, name + "_b.png"), optimize=True)

K = 1.0 / (FLOW_UV * CW)
fat = np.full((CW * G, CW * G, 3), 0.5, np.float32)
mx = 0.0
for i in range(L - 1):                             # клуб не петля: у последнего кадра поток нулевой
    a = q(raw[i][..., 6] ** 0.5)
    b = q(raw[i + 1][..., 6] ** 0.5)
    fl = cv2.calcOpticalFlowFarneback(a, b, None, 0.5, 4, 11, 4, 5, 1.1, 0)
    mx = max(mx, float(np.percentile(np.abs(fl), 99.5)))
    y, x = divmod(i, G)
    fat[y * CW:(y + 1) * CW, x * CW:(x + 1) * CW, 0] = 0.5 + np.clip(fl[..., 0] * K, -0.5, 0.5)
    fat[y * CW:(y + 1) * CW, x * CW:(x + 1) * CW, 1] = 0.5 + np.clip(fl[..., 1] * K, -0.5, 0.5)
fat[..., 2] = 0.0
Image.fromarray(q(fat), "RGB").save(os.path.join(OUT, name + "_flow.png"), optimize=True)
print("поток: 99.5%% — %.2f px/кадр, предел карты %.2f px" % (mx, 0.5 / K))
