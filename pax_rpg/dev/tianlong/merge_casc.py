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
            off = [[round(float(d[i, 0]), 4), round(float(d[i, 2]), 4)] for i in range(n)]
            home = j["nodes"][names["Hips"]].get("translation", [0.0, 0.0, 0.0])
            hv[:, 0] = home[0]                      # клипы — отрезки одной серии: таз — в покое модели, ход — в json
            hv[:, 2] = home[2]
            samp.append({"input": write(j, bin_, tt, "SCALAR"), "output": write(j, bin_, hv, "VEC3"),
                         "interpolation": "LINEAR"})
            ch.append({"sampler": len(samp) - 1, "target": {"node": names["Hips"], "path": "translation"}})
        j["animations"] = [a for a in j["animations"] if a.get("name") != clip]
        j["animations"].append({"name": clip, "channels": ch, "samplers": samp})
        meta.setdefault("root_motion", {})[clip] = {"fps": FPS, "frames": n, "offset": off}
        meta.setdefault("clips", {})[clip] = {"frames": n}
        print(clip, "%.2f s" % t_end, len(ch), "channels", "path %.2f m" % (np.hypot(*off[-1]) if off else 0))
    save(model, j, bin_)
    json.dump(meta, open(meta_p, "w", encoding="utf-8"), ensure_ascii=False)


main()
