"""Нормали glb по углу: у Meshy вершины на изломе (обод крыши юрты — верх стены) общие, и сглаженная нормаль
усреднена между крышей и вертикальной стеной — треугольники крыши у края смотрят вбок и темнеют клиньями (вид —
как неверные тени). Здесь нормаль угла треугольника — среднее (по площади) нормалей граней вокруг той же точки,
которые отходят от этой грани не больше чем на ANGLE°; где у одной вершины выходят разные нормали — вершина
делится. Позиции, UV, материалы и картинки (с номерами DDS) — те же.
    python fix_normals.py <glb> [угол=40]
"""
import json
import struct
import sys

import numpy as np

path = sys.argv[1]
ANGLE = float(sys.argv[2]) if len(sys.argv) > 2 else 40.0
b = open(path, "rb").read()
jl = struct.unpack_from("<I", b, 12)[0]
j = json.loads(b[20:20 + jl])
bin_ = b[20 + jl + 8:20 + jl + 8 + struct.unpack_from("<I", b, 20 + jl)[0]]
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}
DT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}


def read(ai):
    a = j["accessors"][ai]
    bv = j["bufferViews"][a["bufferView"]]
    nc = NC[a["type"]]
    dt = np.dtype(DT[a["componentType"]])
    stride = bv.get("byteStride", nc * dt.itemsize)
    off = bv.get("byteOffset", 0) + a.get("byteOffset", 0)
    raw = np.frombuffer(bin_, dtype=np.uint8, count=stride * (a["count"] - 1) + nc * dt.itemsize, offset=off)
    out = np.empty((a["count"], nc), dt)
    for i in range(a["count"]):
        out[i] = np.frombuffer(raw[i * stride:i * stride + nc * dt.itemsize].tobytes(), dt)
    return out if nc > 1 else out[:, 0]


views, chunks, size = [], [], 0


def push(arr, target):
    global size
    data = np.ascontiguousarray(arr).tobytes()
    pad = (-size) % 4
    chunks.append(b"\0" * pad)
    size += pad
    views.append({"buffer": 0, "byteOffset": size, "byteLength": len(data), **({"target": target} if target else {})})
    chunks.append(data)
    size += len(data)
    return len(views) - 1


accs = []
# картинки — как были
for im in j.get("images", []):
    if "bufferView" in im:
        v = j["bufferViews"][im["bufferView"]]
        im["bufferView"] = push(np.frombuffer(bin_, np.uint8, v["byteLength"], v.get("byteOffset", 0)), None)
cos_lim = np.cos(np.radians(ANGLE))
split = 0
for m in j["meshes"]:
    for p in m["primitives"]:
        att = {k: read(v) for k, v in p["attributes"].items()}
        I = read(p["indices"]).astype(np.int64).reshape(-1, 3)
        P = att["POSITION"].astype(np.float64)
        fn = np.cross(P[I[:, 1]] - P[I[:, 0]], P[I[:, 2]] - P[I[:, 0]])     # длина — удвоенная площадь
        fu = fn / (np.linalg.norm(fn, axis=1, keepdims=True) + 1e-20)
        _, pid = np.unique(P, axis=0, return_inverse=True)
        pid = pid.ravel()
        around = {}
        for t in range(len(I)):
            for c in range(3):
                around.setdefault(pid[I[t, c]], []).append(t)
        newn = np.zeros((len(I), 3, 3))
        for t in range(len(I)):
            for c in range(3):
                ts = np.array(around[pid[I[t, c]]])
                ok = ts[(fu[ts] @ fu[t]) >= cos_lim]
                n = fn[ok].sum(0)
                newn[t, c] = n / (np.linalg.norm(n) + 1e-20)
        # вершина: одна нормаль — та же вершина, разные — копия
        out_idx = np.empty_like(I)
        keys = {}
        src = []
        nrm = []
        for t in range(len(I)):
            for c in range(3):
                v = I[t, c]
                k = (v, tuple(np.round(newn[t, c], 4)))
                if k not in keys:
                    keys[k] = len(src)
                    src.append(v)
                    nrm.append(newn[t, c])
                out_idx[t, c] = keys[k]
        split += len(src) - len(P)
        src = np.array(src)
        attrs = {}
        for k, a in att.items():
            arr = np.array(nrm, np.float32) if k == "NORMAL" else a[src]
            acc = {"bufferView": push(arr, 34962), "componentType": {np.float32: 5126, np.uint16: 5123, np.uint8: 5121}[arr.dtype.type],
                   "count": len(arr), "type": {1: "SCALAR", 2: "VEC2", 3: "VEC3", 4: "VEC4"}[arr.shape[1] if arr.ndim > 1 else 1]}
            if k == "POSITION":
                acc["min"] = arr.min(0).tolist()
                acc["max"] = arr.max(0).tolist()
            orig = j["accessors"][p["attributes"][k]]
            if orig.get("normalized"):
                acc["normalized"] = True
            accs.append(acc)
            attrs[k] = len(accs) - 1
        if "NORMAL" not in attrs:
            raise SystemExit("нет нормалей")
        idx = out_idx.astype(np.uint32 if len(src) > 65535 else np.uint16).ravel()
        accs.append({"bufferView": push(idx, 34963), "componentType": 5125 if idx.dtype == np.uint32 else 5123,
                     "count": len(idx), "type": "SCALAR"})
        p["attributes"] = attrs
        p["indices"] = len(accs) - 1
j["accessors"] = accs
j["bufferViews"] = views
body = b"".join(chunks)
body += b"\0" * ((-len(body)) % 4)
j["buffers"] = [{"byteLength": len(body)}]
js = json.dumps(j, separators=(",", ":")).encode()
js += b" " * ((-len(js)) % 4)
open(path, "wb").write(struct.pack("<III", 0x46546C67, 2, 28 + len(js) + len(body)) + struct.pack("<II", len(js), 0x4E4F534A)
                       + js + struct.pack("<II", len(body), 0x004E4942) + body)
print("%s: нормали по углу %.0f°, вершин добавлено %d" % (path.split("/")[-1], ANGLE, split))
