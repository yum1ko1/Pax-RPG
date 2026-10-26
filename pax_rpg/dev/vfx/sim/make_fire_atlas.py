"""Кадры симуляции огня (fire_sim.py) → флипбук 8×8 для игры + карта движения (motion vectors).
  python make_fire_atlas.py <папка кадров> <имя> [ширина кадра]
Петля: 64 кадра, последние 16 перехлёстом переходят в первые — огонь горит без шва.
Атлас <имя>.png (RGB): R — свечение пламени (√, точнее в тёмном), G — освещённость дыма, B — плотность дыма.
Карта <имя>_flow.png (RG): куда сдвигается каждая точка к следующему кадру (оптический поток) — шейдер «дотягивает»
кадр к следующему, и 64 кадра идут плавно даже медленно (так делают флипбуки в больших играх).
Результат — mods/pax_rpg/textures/vfx/sim/; рядом в <папка кадров>/.. — превью."""
import os, sys, glob
import numpy as np
import cv2
from PIL import Image

src, name = sys.argv[1], sys.argv[2]
CW = int(sys.argv[3]) if len(sys.argv) > 3 else 160
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))))
OUT = os.path.join(ROOT, "mods", "pax_rpg", "textures", "vfx", "sim")
os.makedirs(OUT, exist_ok=True)
L, O, G = 64, 16, 8


def load16(p):
    a = cv2.imread(p, cv2.IMREAD_UNCHANGED)
    if a is None:
        sys.exit("нет " + p)
    a = a.astype(np.float32) / 65535.0
    if a.ndim == 2:
        return a[..., None]
    return a[..., [2, 1, 0, 3][: a.shape[2]]] if a.shape[2] == 4 else a[..., ::-1]


es = sorted(glob.glob(os.path.join(src, "e_*.png")))
ss = sorted(glob.glob(os.path.join(src, "s_*.png")))
assert len(es) >= L + O and len(ss) >= L + O, (len(es), len(ss))
es, ss = es[: L + O], ss[: L + O]
h0, w0 = load16(es[0]).shape[:2]
CH = int(round(CW * h0 / w0))


def frame(i):
    e = load16(es[i])[..., 0]
    s = load16(ss[i])
    a = s[..., 3]
    lum = (s[..., :3] @ np.array([0.2126, 0.7152, 0.0722], np.float32)) / np.maximum(a, 1e-3)   # освещённость без альфы
    lum = np.where(a > 1e-3, lum, 0.0)
    st = np.stack([e, np.clip(lum, 0, 1), a], -1)
    return cv2.resize(st, (CW, CH), interpolation=cv2.INTER_AREA)


raw = [frame(i) for i in range(L + O)]
pk = float(np.percentile(np.stack([r[..., 0] for r in raw]), 99.97))   # ядро пламени — к 1.0 (масштаб рендера неважен)
print("кадр", CW, "×", CH, "пик свечения", pk)
for r in raw:
    r[..., 0] /= max(pk, 1e-4)
loop = []
for i in range(L):
    if i < O:
        w = (i + 0.5) / O
        loop.append(raw[L + i] * (1 - w) + raw[i] * w)
    else:
        loop.append(raw[i])


def enc(f):
    return np.stack([np.sqrt(np.clip(f[..., 0], 0, 1)), f[..., 1], f[..., 2]], -1)


atlas = np.zeros((CH * G, CW * G, 3), np.float32)
for i, f in enumerate(loop):
    y, x = divmod(i, G)
    atlas[y * CH:(y + 1) * CH, x * CW:(x + 1) * CW] = enc(f)
Image.fromarray((np.clip(atlas, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name + ".png"), optimize=True)


# оптический поток по «видимости» кадра: пламя + дым
def vis(f):
    v = np.sqrt(np.clip(f[..., 0], 0, 1)) * 0.8 + f[..., 2] * 0.6
    return (np.clip(v, 0, 1) * 255).astype(np.uint8)


flows = []
for i in range(L):
    a, b = vis(loop[i]), vis(loop[(i + 1) % L])
    fl = cv2.calcOpticalFlowFarneback(a, b, None, 0.5, 4, 9, 4, 5, 1.1, 0)
    flows.append(fl)
mx = max(float(np.percentile(np.abs(f), 99.5)) for f in flows) + 1e-3
FLOW_UV = 0.16                                     # 1.0 в карте = 0.16 ширины кадра (shaders/vfx_fire.gdshader → flow_uv)
K = 1.0 / (FLOW_UV * CW)                           # пиксели кадра → доли карты
print("поток: 99.5%% — %.2f px/кадр, предел карты %.2f px" % (mx, 0.5 / K))
fat = np.zeros((CH * G, CW * G, 3), np.float32)
for i, fl in enumerate(flows):
    y, x = divmod(i, G)
    fat[y * CH:(y + 1) * CH, x * CW:(x + 1) * CW, 0] = 0.5 + np.clip(fl[..., 0] * K, -0.5, 0.5)
    fat[y * CH:(y + 1) * CH, x * CW:(x + 1) * CW, 1] = 0.5 + np.clip(fl[..., 1] * K, -0.5, 0.5)
Image.fromarray((np.clip(fat, 0, 1) * 255 + 0.5).astype(np.uint8)).save(os.path.join(OUT, name + "_flow.png"), optimize=True)
# сила потока для шейдера: 1.0 в карте = столько долей кадра
print("flow_scale", round(1.0 / K / CW, 5), round(1.0 / K / CH, 5))
open(os.path.join(OUT, name + ".txt"), "w").write("flow_px_per_unit %.4f\nflow_uv %.6f %.6f\ncell %d %d\n" % (1.0 / K, 1.0 / K / CW, 1.0 / K / CH, CW, CH))
