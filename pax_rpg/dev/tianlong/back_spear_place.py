"""Копьё за спиной (узел Sword_Back) — по диагонали поверх спины, а не из кадра анимации: в концах Draw/Sheathe
Cascadeur копьё лежало поперёк талии, сквозь тело (и на бегу, вслед за позвоночником, — сквозь ноги).
Наконечник (−Z сетки) — над правым плечом, древко — к левому бедру, плашмя к спине; отступ — от самой дальней назад
точки тела (плащ, волосы) в полосе y 0.5…1.35 м плюс полтолщины копья и зазор.
    python3 back_spear_place.py <model.glb> [зазор_м=0.04] [наклон=0.5]"""
import sys

import numpy as np

sys.path.insert(0, __import__("os").path.dirname(__file__))
from merge_casc import load, save, read, trs, m2q  # noqa: E402

path = sys.argv[1]
gap = float(sys.argv[2]) if len(sys.argv) > 2 else 0.04
lean = float(sys.argv[3]) if len(sys.argv) > 3 else 0.5
j, bin_ = load(path)
N = j["nodes"]
nm = [n.get("name") for n in N]
par = {c: i for i, n in enumerate(N) for c in n.get("children", [])}


def W(i):
    n = N[i]
    m = trs(n.get("translation"), n.get("rotation")) @ np.diag(list(n.get("scale", [1, 1, 1])) + [1.0])
    return W(par[i]) @ m if i in par else m


body = N[nm.index("TianLong_Body")]
V = np.concatenate([read(j, bin_, p["attributes"]["POSITION"]) for p in j["meshes"][body["mesh"]]["primitives"]])
band = V[(V[:, 1] > 0.5) & (V[:, 1] < 1.35) & (np.abs(V[:, 0]) < 0.22)]
zback = float(band[:, 2].min())
sb = nm.index("Sword_Back")
P = read(j, bin_, j["meshes"][N[sb]["mesh"]]["primitives"][0]["attributes"]["POSITION"])
half = float(np.ptp(P[:, 1])) / 2
d = np.array([-lean, 1.0, 0.0])
d /= np.linalg.norm(d)                       # наконечник: вверх и к правому плечу (правое у героя — −X)
z = -d                                       # наконечник сетки — на −Z
x = np.cross([0.0, 0.0, 1.0], z)
x /= np.linalg.norm(x)
y = np.cross(z, x)
M = np.eye(4)
M[:3, 0], M[:3, 1], M[:3, 2] = x, y, z
M[:3, 3] = [0.0, 1.25, zback - half - gap]          # центр древка — у лопаток: низ не цепляет ноги и землю
L = np.linalg.inv(W(par[sb])) @ M
sc = np.linalg.norm(L[:3, :3], axis=0)
N[sb]["translation"] = [float(v) for v in L[:3, 3]]
N[sb]["rotation"] = [float(v) for v in m2q(L[:3, :3] / sc)]
N[sb]["scale"] = [float(v) for v in sc]
save(path, j, bin_)
print("спина z %.3f, копьё в z %.3f; Sword_Back ←" % (zback, M[2, 3]), [round(v, 3) for v in N[sb]["translation"]])
