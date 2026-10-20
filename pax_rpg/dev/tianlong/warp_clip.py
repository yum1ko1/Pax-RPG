"""Новый клип из готового с другим ходом времени (кусочно-линейно): замедлить замах, задержать миг удара, ускорить
отход — например, Кровожадная атака из укола Attack1: подход медленнее, копьё замирает в теле, рывок назад.
    python3 warp_clip.py <model.glb> <anim.json> <Новый> <Исходный> 0:0 0.4:0.55 0.533:0.75 0.56:1.65 0.833:2.2
Пары «время исходника : время нового клипа» (с), по возрастанию; root motion (anim.json) — по той же карте."""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from merge_casc import load, save, read, write  # noqa: E402

FPS = 30


def main():
    path, meta_p, dst, src = sys.argv[1:5]
    pairs = [tuple(float(x) for x in p.split(":")) for p in sys.argv[5:]]
    ts_, tn_ = np.array([p[0] for p in pairs]), np.array([p[1] for p in pairs])
    j, jb = load(path)
    an = next(a for a in j["animations"] if a["name"] == src)
    n = int(round(tn_[-1] * FPS)) + 1
    tn = np.linspace(0.0, tn_[-1], n)
    tsrc = np.interp(tn, tn_, ts_)                # для каждого кадра нового — время исходника
    ti = write(j, jb, tn.astype(np.float32), "SCALAR")
    ch, samp = [], []
    for c in an["channels"]:
        sp = an["samplers"][c["sampler"]]
        t = read(j, jb, sp["input"])[:, 0]
        v = read(j, jb, sp["output"])
        out = np.stack([np.interp(tsrc, t, v[:, k]) for k in range(v.shape[1])], 1)
        if v.shape[1] == 4:
            out /= np.linalg.norm(out, axis=1, keepdims=True)
        typ = {3: "VEC3", 4: "VEC4"}[v.shape[1]]
        samp.append({"input": ti, "output": write(j, jb, out.astype(np.float32), typ), "interpolation": "LINEAR"})
        ch.append({"sampler": len(samp) - 1, "target": dict(c["target"])})
    j["animations"] = [a for a in j["animations"] if a.get("name") != dst] + [{"name": dst, "channels": ch, "samplers": samp}]
    save(path, j, jb)
    meta = json.load(open(meta_p, encoding="utf-8"))
    rm = meta.get("root_motion", {}).get(src)
    if rm:
        off = np.array(rm["offset"], float)
        to = np.arange(len(off)) / float(rm.get("fps", FPS))
        new = np.stack([np.interp(tsrc, to, off[:, k]) for k in range(2)], 1)
        meta["root_motion"][dst] = {"fps": FPS, "frames": n, "offset": [[round(float(a), 4), round(float(b), 4)] for a, b in new]}
    meta.setdefault("clips", {})[dst] = {"frames": n}
    json.dump(meta, open(meta_p, "w", encoding="utf-8"), ensure_ascii=False)
    print(dst, "from", src, "%.2f s" % tn[-1])


if __name__ == "__main__":
    main()
