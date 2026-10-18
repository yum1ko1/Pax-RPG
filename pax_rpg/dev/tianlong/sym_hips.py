"""Цикл шага: таз симметричен по двум шагам (левый = правый со сдвигом на полцикла, вбок — зеркально) и сглажен
по кругу — без «хромоты»: один шаг проседает, другой нет, и тело плывёт вбок.
    python3 sym_hips.py <model.glb> Walk [...]"""
import sys

import numpy as np

sys.path.insert(0, __import__("os").path.dirname(__file__))
from merge_casc import load, save, read  # noqa: E402

path = sys.argv[1]
j, bin_ = load(path)
hips = [n.get("name") for n in j["nodes"]].index("Hips")
for an in j["animations"]:
    if an["name"] not in sys.argv[2:]:
        continue
    for ch in an["channels"]:
        if ch["target"]["node"] != hips or ch["target"]["path"] != "translation":
            continue
        out = an["samplers"][ch["sampler"]]["output"]
        v = read(j, bin_, out).copy()
        c = v[:-1]                                   # последний кадр = первый
        n = len(c)
        h = n // 2
        s = np.roll(c, -h, axis=0)                   # тот же миг другого шага
        m = c.mean(axis=0)
        r = c.copy()
        r[:, 1] = (c[:, 1] + s[:, 1]) / 2            # вверх-вниз: оба шага одинаково
        r[:, 2] = (c[:, 2] + s[:, 2]) / 2            # вперёд-назад: так же
        r[:, 0] = m[0] + ((c[:, 0] - m[0]) - (s[:, 0] - m[0])) / 2   # вбок: зеркально, без ухода
        k = np.array([1, 4, 6, 4, 1], float) / 16    # гаусс по кругу
        r = sum(np.roll(r, i - 2, axis=0) * w for i, w in enumerate(k))
        v[:-1] = r
        v[-1] = r[0]
        print(an["name"], "таз вверх-вниз %.3f → %.3f м, вбок %.3f → %.3f" % (np.ptp(c[:, 1]), np.ptp(r[:, 1]), np.ptp(c[:, 0]), np.ptp(r[:, 0])))
        acc = j["accessors"][out]
        bv = j["bufferViews"][acc["bufferView"]]
        o = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        bin_[o:o + v.size * 4] = v.astype("<f4").tobytes()
save(path, j, bin_)
