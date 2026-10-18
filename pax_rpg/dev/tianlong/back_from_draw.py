"""Копьё за спиной (узел Sword_Back) — ровно там, где копьё в руке на первом кадре Draw: взятие без скачка, а
убирание (Sheathe кончается тем же положением) кладёт его на место.
    python3 back_from_draw.py <model.glb> [Draw] [first|last]
    (Sheathe last — копьё там, где его оставила анимация убирания)
"""
import sys

import numpy as np

sys.path.insert(0, __import__("os").path.dirname(__file__))
from merge_casc import load, save, read, trs, m2q  # noqa: E402

path = sys.argv[1]
clip = sys.argv[2] if len(sys.argv) > 2 else "Draw"
fr = -1 if len(sys.argv) > 3 and sys.argv[3] == "last" else 0
j, bin_ = load(path)
nodes = j["nodes"]
names = {n.get("name"): i for i, n in enumerate(nodes)}
parent = {}
for i, n in enumerate(nodes):
    for c in n.get("children", []):
        parent[c] = i
an = next(a for a in j["animations"] if a["name"] == clip)
over = {}
for ch in an["channels"]:
    v = read(j, bin_, an["samplers"][ch["sampler"]]["output"])[fr]
    over[(ch["target"]["node"], ch["target"]["path"])] = list(map(float, v))


def local(i):
    n = nodes[i]
    t = over.get((i, "translation"), n.get("translation", [0, 0, 0]))
    r = over.get((i, "rotation"), n.get("rotation", [0, 0, 0, 1]))
    s = over.get((i, "scale"), n.get("scale", [1, 1, 1]))
    return trs(t, r) @ np.diag(list(s) + [1.0])


def world(i):
    m = local(i)
    while i in parent:
        i = parent[i]
        m = local(i) @ m
    return m


hand = world(names["Sword_Hand"])
bi = names["Sword_Back"]
pw = world(parent[bi]) if bi in parent else np.eye(4)
L = np.linalg.inv(pw) @ hand
sc = np.linalg.norm(L[:3, :3], axis=0)
R = L[:3, :3] / sc
nodes[bi]["translation"] = [float(x) for x in L[:3, 3]]
nodes[bi]["rotation"] = [float(x) for x in m2q(R)]
nodes[bi]["scale"] = [float(x) for x in sc]
save(path, j, bin_)
print("Sword_Back ←", clip, "кадр", fr, ":", [round(x, 3) for x in L[:3, 3]])
