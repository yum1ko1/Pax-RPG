"""Сгладить повороты костей в клипе модели (болтанка головы от автофизики Cascadeur, уже запечённая в анимацию):
кватернионы — гауссом по кадрам (по кругу для циклов), наклоны при шаге остаются, дрожь и «догоняние» уходят.
    python3 smooth_bones.py <model.glb> <клип> <кость,кость> [сигма кадров=3] [loop]"""
import sys

import numpy as np

sys.path.insert(0, __import__("os").path.dirname(__file__))
from merge_casc import load, save, read  # noqa: E402

path, clip, bones = sys.argv[1], sys.argv[2], sys.argv[3].split(",")
sigma = float(sys.argv[4]) if len(sys.argv) > 4 else 3.0
loop = len(sys.argv) > 5 and sys.argv[5] == "loop"
j, bin_ = load(path)
names = [n.get("name") for n in j["nodes"]]
an = next(a for a in j["animations"] if a["name"] == clip)
r = int(sigma * 3)
w = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
w /= w.sum()
for ch in an["channels"]:
    nm = names[ch["target"]["node"]]
    if nm not in bones or ch["target"]["path"] != "rotation":
        continue
    acc = j["accessors"][an["samplers"][ch["sampler"]]["output"]]
    q = read(j, bin_, an["samplers"][ch["sampler"]]["output"]).astype(np.float64)
    for i in range(1, len(q)):                       # один знак кватернионов — без перескоков
        if np.dot(q[i], q[i - 1]) < 0:
            q[i] = -q[i]
    n = len(q)
    if loop:
        body = q[:-1] if np.allclose(np.abs(np.dot(q[0], q[-1])), 1.0, atol=1e-3) else q
        m = len(body)
        pad = np.concatenate([body[-r:], body, body[:r]])
        sm = np.array([np.sum(pad[i:i + 2 * r + 1] * w[:, None], 0) for i in range(m)])
        sm = np.concatenate([sm, sm[:n - m]]) if n > m else sm
    else:
        pad = np.concatenate([np.repeat(q[:1], r, 0), q, np.repeat(q[-1:], r, 0)])
        sm = np.array([np.sum(pad[i:i + 2 * r + 1] * w[:, None], 0) for i in range(n)])
    sm /= np.linalg.norm(sm, axis=1, keepdims=True)
    ang = np.degrees(2 * np.arccos(np.clip(np.abs(np.sum(sm * q, 1)), 0, 1))).max()
    bv = j["bufferViews"][acc["bufferView"]]
    o = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    bin_[o:o + sm.size * 4] = sm.astype("<f4").tobytes()
    print(clip, nm, "сглажено, наибольшая правка %.1f°" % ang)
save(path, j, bin_)
