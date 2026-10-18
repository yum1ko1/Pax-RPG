"""Цикл с неравномерным ходом (бег Cascadeur: таз то отстаёт, то догоняет средний ход до 0.7 м): таз клипа — без
качания вперёд-назад (ось хода модели), только вверх-вниз и вбок. Иначе герой, идущий ровно, на каждом круге «откатывается».
    python3 flat_root.py <model.glb> Run [...]"""
import sys

import numpy as np

sys.path.insert(0, __import__("os").path.dirname(__file__))
from merge_casc import load, save, read  # noqa: E402

path = sys.argv[1]
j, bin_ = load(path)
names = [n.get("name") for n in j["nodes"]]
hips = names.index("Hips")
home = j["nodes"][hips].get("translation", [0.0, 0.0, 0.0])
for an in j["animations"]:
    if an["name"] not in sys.argv[2:]:
        continue
    for ch in an["channels"]:
        if ch["target"]["node"] == hips and ch["target"]["path"] == "translation":
            acc = j["accessors"][an["samplers"][ch["sampler"]]["output"]]
            v = read(j, bin_, an["samplers"][ch["sampler"]]["output"]).copy()
            print(an["name"], "ход таза был %.2f м" % float(np.ptp(v[:, 2])))
            v[:, 2] = home[2]
            bv = j["bufferViews"][acc["bufferView"]]
            o = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
            bin_[o:o + v.size * 4] = v.astype("<f4").tobytes()
save(path, j, bin_)
