"""Клипы Тянь Луна из Cascadeur (glb того же рига Mixamo: «mixamorig:*», арматура ×100, повёрнута −90° по X)
→ в models/heroes/tian_long/model.glb без Blender: каналы костей переносятся по имени (Spine↔Spine02, Spine1↔Spine01,
Spine2↔Spine, Neck↔neck), таз — в оси модели (см → м), его ход по горизонтали вынимается в anim.json (root_motion,
30 к/с), клип — на месте. Клипы с тем же именем в модели заменяются.
    python3 merge_casc.py <model.glb> <anim.json> Имя=<клип.glb> [...]
"""
import json
import os
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

    def __init__(self, j, bin_, ai=0):
        self.j = j
        self.par = {c: i for i, n in enumerate(j["nodes"]) for c in n.get("children", [])}
        self.tr = {}
        a = j["animations"][ai]
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


def spear_track(s, sb, j, bin_, names, tt, ai, t0=0.0):
    """Копьё в Cascadeur — отдельный объект (подброс, перехват, за спиной): его МИРОВОЕ положение в исходнике
    переносится в мир модели по тазу (Φ = таз модели · таз исходника⁻¹ в каждый кадр — модель с клипом ai, ход
    вынут) и записывается узлу Spear модели (ребёнок RightHand) как L = кисть модели⁻¹ · Φ · копьё · M.
    M — поправка осей сетки копья: единичная (сетка та же). SPEAR_CALIB=1 — по хвату модели в кадре с копьём в руке
    (SPEAR_CALIB_LAST — последний кадр), как раньше. (Было: ход копья относительно кисти исходника переносился на кисть модели
    без учёта разницы осей кистей — вдали от руки копьё поворачивалось: за спиной в Draw — поперёк талии.)"""
    global SPEAR_K
    fk = FK(s, sb)
    mk = FK(j, bin_, ai)
    sn = {n.get("name"): i for i, n in enumerate(s["nodes"])}
    if "CrimsonSpear" not in sn or "mixamorig:RightHand" not in sn or "Spear" not in names:
        return None
    gs = j["nodes"][names["Spear"]]
    gh = j["nodes"][names["Sword_Hand"]]
    rest = trs(gs.get("translation"), gs.get("rotation")) @ trs(gh.get("translation"), gh.get("rotation"))
    sh_inv = np.linalg.inv(trs(gh.get("translation"), gh.get("rotation")))
    hand = next(i for i, n in enumerate(j["nodes"]) if names["Spear"] in n.get("children", []))   # кисть — родитель Spear

    def phi(t):
        return ortho(mk.world(names["Hips"], t)) @ np.linalg.inv(ortho(fk.world(sn["mixamorig:Hips"], t + t0)))

    def spear_w(t):                              # t — время клипа модели; исходник — с t0 (вырезка @a-b)
        return phi(t) @ ortho(fk.world(sn["CrimsonSpear"], t + t0))

    if SPEAR_K is None:
        if os.environ.get("SPEAR_CALIB"):           # старое: копьё в кадре калибровки — как в хвате модели
            tc = tt[-1] if os.environ.get("SPEAR_CALIB_LAST") else tt[0]
            SPEAR_K = np.linalg.inv(spear_w(tc)) @ ortho(mk.world(hand, tc)) @ rest
        else:                                       # сетка копья та же (ось — Z, 2.1 м): как в Cascadeur, без поправок —
            SPEAR_K = np.eye(4)                     # калибровка по хвату модели поворачивала его на ~90° во всём клипе
    kc = None                                       # SPEAR_BLEND=last|first: к этому концу клипа копьё сводится к хвату
    bl = os.environ.get("SPEAR_BLEND", "")          # модели (стойка, удары) — Draw: за спиной как в Cascadeur → в хват
    if bl:                                          # both — с обоих концов (конец серии: из удара → в стойку)
        kf = np.linalg.inv(spear_w(tt[0])) @ ortho(mk.world(hand, tt[0])) @ rest
        kl = np.linalg.inv(spear_w(tt[-1])) @ ortho(mk.world(hand, tt[-1])) @ rest
        kc = kl if bl == "last" else kf
    pos, rot = [], []
    for k, t in enumerate(tt):
        K = SPEAR_K
        if kc is not None:
            u = k / max(1, len(tt) - 1)
            if bl == "both":
                kc = kf if u < 0.5 else kl
                w = float(np.clip((0.3 - u) / 0.25, 0.0, 1.0)) if u < 0.5 else float(np.clip((u - 0.7) / 0.25, 0.0, 1.0))
            else:
                w = float(np.clip((u - 0.25) / 0.6, 0.0, 1.0)) if bl == "last" else float(np.clip((0.75 - u) / 0.6, 0.0, 1.0))
            w = w * w * (3 - 2 * w)
            qa, qb = m2q(SPEAR_K[:3, :3]), m2q(kc[:3, :3])
            if np.dot(qa, qb) < 0:
                qb = -qb
            q = qa * (1 - w) + qb * w
            K = np.eye(4)
            K[:3, :3] = q2m(q / np.linalg.norm(q))
            K[:3, 3] = SPEAR_K[:3, 3] * (1 - w) + kc[:3, 3] * w
        L = np.linalg.inv(ortho(mk.world(hand, t))) @ spear_w(t) @ K @ sh_inv
        pos.append(L[:3, 3])
        q = m2q(L[:3, :3])
        if rot and np.dot(q, rot[-1]) < 0:
            q = -q
        rot.append(q)
    pos = smooth(pos, SPEAR_SIGMA, True)        # копьё: без телепортов и дрожи
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
    pairs = [p.split("=", 1) for p in sys.argv[3:]]   # Имя=клип.glb[@a-b][:mirror] — mirror: зеркально (лево↔право),
    # @a-b — только кадры a…b исходника (один glb бега → RunStart / Run / RunStop); @a-b~N — цикл: последние N
    # кадров плавно сводятся к первому (шов лупа без скачка ног)
    j, bin_ = load(model)
    meta = json.load(open(meta_p, encoding="utf-8"))
    names = {n.get("name"): i for i, n in enumerate(j["nodes"])}
    for clip, src in pairs:
        mirror = src.endswith(":mirror")
        src = src[:-7] if mirror else src
        f0 = f1 = None
        seam = 0
        if "@" in src:
            src, rng = src.rsplit("@", 1)
            seam = 0
            if "~" in rng:
                rng, seam = rng.split("~")
                seam = int(seam)
            f0, f1 = (int(x) for x in rng.split("-"))
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
            if mirror:                       # зеркало: кость левой стороны играет ход правой и наоборот
                nm = nm.replace("Left", "\0").replace("Right", "Left").replace("\0", "Right")
            path = c["target"]["path"]
            if nm not in names or path == "scale" or (path == "translation" and nm != "Hips"):
                continue
            sp = sa["samplers"][c["sampler"]]
            t = read(s, sb, sp["input"])[:, 0]
            v = read(s, sb, sp["output"])
            if f0 is not None:
                keep = (t >= f0 / FPS - 1e-4) & (t <= f1 / FPS + 1e-4)
                t, v = t[keep] - f0 / FPS, v[keep].copy()
                if seam and len(v) > seam + 1 and (path == "rotation" or (nm == "Hips" and path == "translation")):
                    n_ = len(v)
                    for i in range(n_ - seam, n_):
                        w = (i - (n_ - seam - 1)) / seam
                        w = w * w * (3 - 2 * w)
                        if path == "rotation":
                            q0 = v[0] if np.dot(v[0], v[i]) >= 0 else -v[0]
                            q = v[i] * (1 - w) + q0 * w
                            v[i] = q / np.linalg.norm(q)
                        else:
                            v[i, 2] = v[i, 2] * (1 - w) + v[0, 2] * w   # таз: качание вверх-вниз (Z исходника; ход вперёд — root)
            t_end = max(t_end, float(t[-1]))
            if nm == "Hips" and path == "rotation":
                v = qmul(QX, v)
            if mirror and path == "rotation":   # отражение через плоскость YZ: (x, y, z, w) → (x, −y, −z, w)
                v = v * np.array([1.0, -1.0, -1.0, 1.0], np.float32)
            if nm == "Hips" and path == "translation":
                hips_t = (t, rotx(v * 100.0) * (np.array([-1.0, 1.0, 1.0]) if mirror else 1.0))
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
        j["animations"] = [a for a in j["animations"] if a.get("name") != clip]
        j["animations"].append({"name": clip, "channels": ch, "samplers": samp})
        sp_ = None if mirror else spear_track(s, sb, j, bin_, names, tt, len(j["animations"]) - 1,
                                              f0 / FPS if f0 is not None else 0.0)   # зеркальный — копьё в хвате модели
        if sp_ is not None:
            ti = write(j, bin_, tt, "SCALAR")
            for path, v, typ in (("translation", sp_[0], "VEC3"), ("rotation", sp_[1], "VEC4")):
                samp.append({"input": ti, "output": write(j, bin_, v, typ), "interpolation": "LINEAR"})
                ch.append({"sampler": len(samp) - 1, "target": {"node": names["Spear"], "path": path}})
            print("  spear: max %.2f m from the hand" % float(np.linalg.norm(sp_[0], axis=1).max()))
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


if __name__ == "__main__":
    main()
