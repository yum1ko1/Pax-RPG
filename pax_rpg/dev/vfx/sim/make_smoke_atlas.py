"""Кадры клуба дыма (smoke_sim.py, свет с 6 сторон) → флипбук 8×8 для частиц дыма + карта движения.
  python make_smoke_atlas.py <папка кадров> <имя> [ширина кадра]
<имя>_a.png (RGBA): R — свет справа, G — сверху, B — спереди (со стороны камеры), A — плотность;
<имя>_b.png (RGB):  R — слева, G — снизу, B — сзади. Освещённость — без альфы (сколько света дошло в эту точку).
<имя>_flow.png (RG): куда сдвигается каждая точка к следующему кадру — шейдер «дотягивает» кадр к следующему.
Результат — mods/pax_rpg/textures/vfx/sim/."""
import os, sys, glob
import numpy as np
import cv2
from PIL import Image

src, name = sys.argv[1], sys.argv[2]
CW = int(sys.argv[3]) if len(sys.argv) > 3 else 160
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
raw = []                                           # [кадр] → (6 карт света, альфа)
for f in frames:
    maps, al = [], None
    for d in DIRS:
        s = load16(os.path.join(src, "s_%s_%s.png" % (d, f)))
        a = s[..., 3]
        al = a if al is None else np.maximum(al, a)
        maps.append(np.where(a > 1e-3, (s[..., :3] @ lum_w) / np.maximum(a, 1e-3), 0.0))
    st = np.stack(maps + [al], -1)
    raw.append(cv2.resize(st, (CW, CW), interpolation=cv2.INTER_AREA))
pk = float(np.percentile(np.stack([r[..., :6] for r in raw])[np.stack([r[..., 6] for r in raw]) > 0.05], 99.5))
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
