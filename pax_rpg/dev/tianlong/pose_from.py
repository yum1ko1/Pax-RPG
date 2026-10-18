"""Клип-поза из кадра другого клипа: все каналы — одним ключом (стойка с копьём = последний кадр Draw: доставание
кончается ровно в стойке, без скачка тела и копья).
    python3 pose_from.py <model.glb> <anim.json> IdleArmed Draw [last|first]"""
import json
import sys

import numpy as np

sys.path.insert(0, __import__("os").path.dirname(__file__))
from merge_casc import load, save, read, write  # noqa: E402

path, meta_p, dst, src = sys.argv[1:5]
fr = 0 if len(sys.argv) > 5 and sys.argv[5] == "first" else -1
j, bin_ = load(path)
an = next(a for a in j["animations"] if a["name"] == src)
ch, samp = [], []
ti = write(j, bin_, np.array([0.0], np.float32), "SCALAR")
for c in an["channels"]:
    sp = an["samplers"][c["sampler"]]
    v = read(j, bin_, sp["output"])[fr:][:1] if fr == -1 else read(j, bin_, sp["output"])[:1]
    typ = {3: "VEC3", 4: "VEC4"}[v.shape[1]]
    samp.append({"input": ti, "output": write(j, bin_, v.astype(np.float32), typ), "interpolation": "LINEAR"})
    ch.append({"sampler": len(samp) - 1, "target": dict(c["target"])})
j["animations"] = [a for a in j["animations"] if a.get("name") != dst]
j["animations"].append({"name": dst, "channels": ch, "samplers": samp})
save(path, j, bin_)
meta = json.load(open(meta_p, encoding="utf-8"))
meta.setdefault("clips", {})[dst] = {"frames": 1}
meta.get("root_motion", {}).pop(dst, None)
json.dump(meta, open(meta_p, "w", encoding="utf-8"), ensure_ascii=False)
print(dst, "←", src, "кадр", fr, len(ch), "каналов")
