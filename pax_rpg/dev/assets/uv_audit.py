"""Аудит развёрток: на каждый треугольник — плотность текселей (√(UV-площадь·W·H / 3D-площадь)) и растяжение
(отношение сингулярных чисел якобиана UV→3D). Доли площади: сильно растянутые (>3), сжатые в линию, плотность
вне ×0.25…×4 от медианы. python uv_audit.py <glb...>"""
import json, struct, sys, os
import numpy as np

CT = {5120: "b", 5121: "B", 5122: "h", 5123: "H", 5125: "I", 5126: "f"}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def load(p):
    b = open(p, "rb").read()
    jl = struct.unpack_from("<I", b, 12)[0]
    j = json.loads(b[20:20 + jl])
    off = 20 + jl
    binb = b[off + 8:off + 8 + struct.unpack_from("<I", b, off)[0]] if off < len(b) else b""
    return j, binb


def acc(j, binb, i):
    a = j["accessors"][i]; v = j["bufferViews"][a["bufferView"]]
    n = NC[a["type"]]; dt = np.dtype(CT[a["componentType"]]).newbyteorder("<")
    start = v.get("byteOffset", 0) + a.get("byteOffset", 0); stride = v.get("byteStride", 0) or dt.itemsize * n
    if stride == dt.itemsize * n:
        arr = np.frombuffer(binb, dtype=dt, count=a["count"] * n, offset=start).reshape(-1, n)
    else:
        raw = np.frombuffer(binb, dtype=np.uint8, count=stride * a["count"], offset=start).reshape(-1, stride)
        arr = raw[:, :dt.itemsize * n].copy().view(dt).reshape(-1, n)
    return arr.astype(np.float64)


for p in sys.argv[1:]:
    j, binb = load(p)
    A3 = []; DEN = []; STR = []
    for m in j.get("meshes", []):
        for pr in m["primitives"]:
            if "TEXCOORD_0" not in pr["attributes"]:
                continue
            P = acc(j, binb, pr["attributes"]["POSITION"]); U = acc(j, binb, pr["attributes"]["TEXCOORD_0"])
            I = acc(j, binb, pr["indices"]).astype(np.int64).reshape(-1, 3) if "indices" in pr else np.arange(len(P)).reshape(-1, 3)
            p0, p1, p2 = P[I[:, 0]], P[I[:, 1]], P[I[:, 2]]
            u0, u1, u2 = U[I[:, 0]], U[I[:, 1]], U[I[:, 2]]
            e1, e2 = p1 - p0, p2 - p0
            a3 = np.linalg.norm(np.cross(e1, e2), axis=1) / 2
            d1, d2 = u1 - u0, u2 - u0
            a2 = np.abs(d1[:, 0] * d2[:, 1] - d1[:, 1] * d2[:, 0]) / 2
            ok = (a3 > 1e-12)
            # якобиан: 3D рёбра через UV-базис
            det = d1[:, 0] * d2[:, 1] - d1[:, 1] * d2[:, 0]
            good = ok & (np.abs(det) > 1e-14)
            inv = np.zeros((len(I), 2, 2))
            inv[good, 0, 0] = d2[good, 1] / det[good]; inv[good, 0, 1] = -d2[good, 0] / det[good]
            inv[good, 1, 0] = -d1[good, 1] / det[good]; inv[good, 1, 1] = d1[good, 0] / det[good]
            E = np.stack([e1, e2], axis=2)                 # (n,3,2)
            Jm = np.einsum("nij,njk->nik", E, inv)          # dP/dUV (n,3,2)
            s = np.linalg.svd(Jm[good], compute_uv=False)
            st = np.full(len(I), 1e6); st[good] = s[:, 0] / np.maximum(s[:, 1], 1e-12)
            A3.append(a3[ok]); DEN.append(np.sqrt(a2[ok] / a3[ok])); STR.append(st[ok])
    if not A3:
        print(os.path.basename(p), "no uv"); continue
    a3 = np.concatenate(A3); den = np.concatenate(DEN); st = np.concatenate(STR)
    w = a3 / a3.sum()
    med = np.median(den[den > 0]) if (den > 0).any() else 0
    bad_str = w[st > 3].sum(); zero = w[den < 1e-6].sum()
    off = w[(den > 0) & ((den < med * 0.25) | (den > med * 4))].sum()
    print(f"{os.path.basename(p):28s} tris {len(a3):6d}  stretch>3 {bad_str*100:5.1f}%  degenerate {zero*100:5.1f}%  density_off {off*100:5.1f}%")
