"""Клипы Тянь Луна из Cascadeur (glb того же рига Mixamo: «mixamorig:*», арматура ×100, повёрнута −90° по X)
→ в models/heroes/tian_long/model.glb без Blender: каналы костей переносятся по имени (Spine↔Spine02, Spine1↔Spine01,
Spine2↔Spine, Neck↔neck), таз — в оси модели (см → м), его ход по горизонтали вынимается в anim.json (root_motion,
30 к/с), клип — на месте. Клипы с тем же именем в модели заменяются.
    python3 merge_casc.py <model.glb> <anim.json> Имя=<клип.glb> [...]
"""
import json
import struct
import sys

import numpy as np

MAP = {"Spine": "Spine02", "Spine1": "Spine01", "Spine2": "Spine", "Neck": "neck"}
FPS = 30
QX = np.array([-0.70710678, 0.0, 0.0, 0.70710678])      # −90° по X (x, y, z, w)


def load(path):
    b = open(path, "rb").read()
    n = struct.unpack_from("<I", b, 12)[0]
    j = json.loads(b[20:20 + n])
    rest = b[20 + n:]
    m = struct.unpack_from("<I", rest, 0)[0]
    return j, bytearray(rest[8:8 + m])


def save(path, j, bin_):
    while len(bin_) % 4:
        bin_ += b"\0"
    j["buffers"][0]["byteLength"] = len(bin_)
    js = json.dumps(j, separators=(",", ":"), ensure_ascii=False).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    body = struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(bin_), 0x004E4942) + bytes(bin_)
    open(path, "wb").write(struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body)


CW = {"SCALAR": 1, "VEC3": 3, "VEC4": 4}


def read(j, bin_, ai):
    a = j["accessors"][ai]
    bv = j["bufferViews"][a["bufferView"]]
    w = CW[a["type"]]
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    stride = bv.get("byteStride", 4 * w)
    out = np.zeros((a["count"], w), np.float32)
    for i in range(a["count"]):
        out[i] = struct.unpack_from("<%df" % w, bin_, off + i * stride)
    return out


def write(j, bin_, arr, typ):
    while len(bin_) % 4:
        bin_ += b"\0"
    arr = np.ascontiguousarray(arr, np.float32)
    off = len(bin_)
    bin_ += arr.tobytes()
    j["bufferViews"].append({"buffer": 0, "byteOffset": off, "byteLength": arr.nbytes})
    acc = {"bufferView": len(j["bufferViews"]) - 1, "componentType": 5126, "count": int(arr.shape[0]), "type": typ}
    if typ == "SCALAR":
        acc["min"] = [float(arr.min())]
        acc["max"] = [float(arr.max())]
    j["accessors"].append(acc)
    return len(j["accessors"]) - 1


def qmul(a, b):
    x1, y1, z1, w1 = a.T if a.ndim > 1 else a
    x2, y2, z2, w2 = b.T
    return np.stack([w1 * x2 + x1 * w2 + y1 * z2 - z1 * y2, w1 * y2 - x1 * z2 + y1 * w2 + z1 * x2,
                     w1 * z2 + x1 * y2 - y1 * x2 + z1 * w2, w1 * w2 - x1 * x2 - y1 * y2 - z1 * z2], 1)


def rotx(v):                    # −90° по X: (x, y, z) → (x, z, −y)
    return np.stack([v[:, 0], v[:, 2], -v[:, 1]], 1)


def q2m(q):
    x, y, z, w = q / np.linalg.norm(q)
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def m2q(m):
    t = np.trace(m)
    if t > 0:
        r = np.sqrt(1 + t) * 2
        q = [(m[2, 1] - m[1, 2]) / r, (m[0, 2] - m[2, 0]) / r, (m[1, 0] - m[0, 1]) / r, r / 4]
    else:
        i = int(np.argmax(np.diag(m)))
        j_, k = (i + 1) % 3, (i + 2) % 3
        r = np.sqrt(1 + m[i, i] - m[j_, j_] - m[k, k]) * 2
        q = [0.0, 0.0, 0.0, (m[k, j_] - m[j_, k]) / r]
        q[i] = r / 4
        q[j_] = (m[j_, i] + m[i, j_]) / r
        q[k] = (m[k, i] + m[i, k]) / r
    return np.array(q)


def trs(t=None, r=None, sc=None):
    M = np.eye(4)
    M[:3, :3] = q2m(np.array(r if r is not None else [0, 0, 0, 1.0], float)) * np.array(sc if sc is not None else [1, 1, 1.0])
    M[:3, 3] = t if t is not None else [0, 0, 0]
    return M


class FK:
    """Мировые матрицы узлов исходного glb в момент t (каналы его первой анимации)."""

    def __init__(self, j, bin_):
        self.j = j
        self.par = {c: i for i, n in enumerate(j["nodes"]) for c in n.get("children", [])}
        self.tr = {}
        a = j["animations"][0]
        for c in a["channels"]:
            sp = a["samplers"][c["sampler"]]
            self.tr[(c["target"]["node"], c["target"]["path"])] = (read(j, bin_, sp["input"])[:, 0], read(j, bin_, sp["output"]))

    def _val(self, i, path, t, d):
        k = self.tr.get((i, path))
        if k is None:
            return d
        tt, v = k
        return np.array([np.interp(t, tt, v[:, c]) for c in range(v.shape[1])])

    def world(self, i, t):
        n = self.j["nodes"][i]
        M = trs(self._val(i, "translation", t, n.get("translation")), self._val(i, "rotation", t, n.get("rotation")),
                self._val(i, "scale", t, n.get("scale")))
        return (self.world(self.par[i], t) @ M) if i in self.par else M


def ortho(M):
    R = M[:3, :3]
    R = R / np.linalg.norm(R, axis=0)
    out = np.eye(4)
    out[:3, :3] = R
    out[:3, 3] = M[:3, 3]
    return out


SPEAR_K = None                  # копьё Cascadeur → узел Spear модели: поправка по первому кадру первого клипа


def spear_track(s, sb, j, names, tt):
    """Копьё в Cascadeur — отдельный объект (подброс, перехват): его ход относительно кисти → узел Spear модели
    (ребёнок RightHand, в нём сетка Sword_Hand). Первый кадр первого клипа = копьё в руке как в модели."""
    global SPEAR_K
    fk = FK(s, sb)
    sn = {n.get("name"): i for i, n in enumerate(s["nodes"])}
    if "CrimsonSpear" not in sn or "mixamorig:RightHand" not in sn or "Spear" not in names:
        return None
    gs = j["nodes"][names["Spear"]]
    gh = j["nodes"][names["Sword_Hand"]]
    rest = trs(gs.get("translation"), gs.get("rotation")) @ trs(gh.get("translation"), gh.get("rotation"))
    sh_inv = np.linalg.inv(trs(gh.get("translation"), gh.get("rotation")))
    pos, rot = [], []
    for k, t in enumerate(tt):
        rel = np.linalg.inv(ortho(fk.world(sn["mixamorig:RightHand"], t))) @ ortho(fk.world(sn["CrimsonSpear"], t))
        if SPEAR_K is None:
            SPEAR_K = np.linalg.inv(rel) @ rest
        L = rel @ SPEAR_K @ sh_inv
        pos.append(L[:3, 3])
        q = m2q(L[:3, :3])
        if rot and np.dot(q, rot[-1]) < 0:
            q = -q
        rot.append(q)
    pos = smooth(pos, SPEAR_SIGMA, True)        # копьё: без телепортов и дрожи в руке
    rot = smooth(rot, SPEAR_SIGMA, True)
    rot /= np.linalg.norm(rot, axis=1, keepdims=True)
    return pos, rot


def smooth(v, sigma, median=False):
    """Гладкая кривая по кадрам (оси — столбцы): медиана по 3 кадрам убирает одиночные скачки (телепорт копья),
    гаусс sigma кадров — дрожь. Края не съезжают (отражение)."""
    v = np.asarray(v, float)
    if median and len(v) >= 3:
        p = np.concatenate([v[:1], v, v[-1:]])
        v = np.median(np.stack([p[:-2], p[1:-1], p[2:]]), axis=0)
    if sigma <= 0:
        return v
    r = int(np.ceil(sigma * 3))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2)
    k /= k.sum()
    p = np.concatenate([v[r:0:-1], v, v[-2:-r - 2:-1]]) if len(v) > r + 1 else np.pad(v, ((r, r), (0, 0)), "edge")
    return np.stack([np.convolve(p[:, c], k, "valid") for c in range(v.shape[1])], 1)


ROOT_SIGMA = 4.0                # кадров (30 к/с): ход героя — гладкий, качание таза остаётся в клипе
SPEAR_SIGMA = 1.2


def main():
    model, meta_p = sys.argv[1], sys.argv[2]
    pairs = [p.split("=", 1) for p in sys.argv[3:]]
    j, bin_ = load(model)
    meta = json.load(open(meta_p, encoding="utf-8"))
    names = {n.get("name"): i for i, n in enumerate(j["nodes"])}
    for clip, src in pairs:
        s, sb = load(src)
        sa = s["animations"][0]
        ch, samp = [], []
        hips_t = None
        t_end = 0.0
        for c in sa["channels"]:
            nm = s["nodes"][c["target"]["node"]].get("name", "")
            if not nm.startswith("mixamorig:"):
                continue
            nm = MAP.get(nm[10:], nm[10:])
            path = c["target"]["path"]
            if nm not in names or path == "scale" or (path == "translation" and nm != "Hips"):
                continue
            sp = sa["samplers"][c["sampler"]]
            t = read(s, sb, sp["input"])[:, 0]
            v = read(s, sb, sp["output"])
            t_end = max(t_end, float(t[-1]))
            if nm == "Hips" and path == "rotation":
                v = qmul(QX, v)
            if nm == "Hips" and path == "translation":
                hips_t = (t, rotx(v * 100.0))
                continue
            samp.append({"input": write(j, bin_, t, "SCALAR"), "output": write(j, bin_, v, "VEC4"),
                         "interpolation": sp.get("interpolation", "LINEAR")})
            ch.append({"sampler": len(samp) - 1, "target": {"node": names[nm], "path": path}})
        n = int(round(t_end * FPS)) + 1
        tt = np.linspace(0.0, t_end, n)
        off = []
        if hips_t is not None:
            t, v = hips_t
            hv = np.stack([np.interp(tt, t, v[:, k]) for k in range(3)], 1)
            d = hv - hv[0]
            road = smooth(d[:, [0, 2]], ROOT_SIGMA)   # ход героя — гладкий (без качания таза: иначе «плывёт»)
            road -= road[0]
            road += np.linspace(0.0, 1.0, n)[:, None] * (d[-1, [0, 2]] - road[-1])   # весь путь клипа — как в анимации
            off = [[round(float(road[i, 0]), 4), round(float(road[i, 1]), 4)] for i in range(n)]
            home = j["nodes"][names["Hips"]].get("translation", [0.0, 0.0, 0.0])
            hv[:, 0] = home[0] + d[:, 0] - road[:, 0]   # таз — в покое модели + качание вокруг хода (в клипе)
            hv[:, 2] = home[2] + d[:, 2] - road[:, 1]
            samp.append({"input": write(j, bin_, tt, "SCALAR"), "output": write(j, bin_, hv, "VEC3"),
                         "interpolation": "LINEAR"})
            ch.append({"sampler": len(samp) - 1, "target": {"node": names["Hips"], "path": "translation"}})
        sp_ = spear_track(s, sb, j, names, tt)
        if sp_ is not None:
            ti = write(j, bin_, tt, "SCALAR")
            for path, v, typ in (("translation", sp_[0], "VEC3"), ("rotation", sp_[1], "VEC4")):
                samp.append({"input": ti, "output": write(j, bin_, v, typ), "interpolation": "LINEAR"})
                ch.append({"sampler": len(samp) - 1, "target": {"node": names["Spear"], "path": path}})
            print("  spear: max %.2f m from the hand" % float(np.linalg.norm(sp_[0], axis=1).max()))
        j["animations"] = [a for a in j["animations"] if a.get("name") != clip]
        j["animations"].append({"name": clip, "channels": ch, "samplers": samp})
        meta.setdefault("root_motion", {})[clip] = {"fps": FPS, "frames": n, "offset": off}
        meta.setdefault("clips", {})[clip] = {"frames": n}
        print(clip, "%.2f s" % t_end, len(ch), "channels", "path %.2f m" % (np.hypot(*off[-1]) if off else 0))
    if "Spear" in names:                     # клипы без хода копья держат его в руке как в модели (иначе застынет где было)
        gs = j["nodes"][names["Spear"]]
        for a in j["animations"]:
            if any(c["target"]["node"] == names["Spear"] for c in a["channels"]):
                continue
            t_end = max(float(j["accessors"][sp["input"]]["max"][0]) for sp in a["samplers"])
            ti = write(j, bin_, np.array([0.0, t_end]), "SCALAR")
            for path, v, typ in (("translation", gs.get("translation", [0, 0, 0]), "VEC3"),
                                 ("rotation", gs.get("rotation", [0, 0, 0, 1]), "VEC4")):
                a["samplers"].append({"input": ti, "output": write(j, bin_, np.array([v, v]), typ),
                                      "interpolation": "LINEAR"})
                a["channels"].append({"sampler": len(a["samplers"]) - 1, "target": {"node": names["Spear"], "path": path}})
    save(model, j, bin_)
    json.dump(meta, open(meta_p, "w", encoding="utf-8"), ensure_ascii=False)


main()
