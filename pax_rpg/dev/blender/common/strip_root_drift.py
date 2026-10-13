"""Убирает «уезжание» корня (root motion) из клипов glb: из перевода кости Hips вычитается скользящее среднее (поступь).
Покачивание и подпрыгивание остаются, персонаж стоит на месте — двигает его код игры.
Правит данные прямо в бинарнике (размер не меняется, картинки и материалы не трогаются).
python3 strip_root_drift.py <in.glb> <out.glb> Clip1 Clip2 ... [--bone Hips]"""
import json, struct, sys

def main():
    a = sys.argv[1:]
    bone = "Hips"
    if "--bone" in a:
        i = a.index("--bone"); bone = a[i + 1]; del a[i:i + 2]
    src, dst, clips = a[0], a[1], set(a[2:])
    raw = bytearray(open(src, "rb").read())
    jlen = struct.unpack_from("<I", raw, 12)[0]
    g = json.loads(raw[20:20 + jlen])
    bin_off = 20 + jlen + 8
    node = next(i for i, n in enumerate(g["nodes"]) if n.get("name") == bone)
    for an in g["animations"]:
        if an["name"] not in clips:
            continue
        for ch in an["channels"]:
            if ch["target"].get("node") != node or ch["target"]["path"] != "translation":
                continue
            s = an["samplers"][ch["sampler"]]
            acc = g["accessors"][s["output"]]
            bv = g["bufferViews"][acc["bufferView"]]
            off = bin_off + bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
            stride = bv.get("byteStride", 12)
            n = acc["count"]
            assert acc["componentType"] == 5126 and acc["type"] == "VEC3"
            vals = [list(struct.unpack_from("<3f", raw, off + k * stride)) for k in range(n)]
            for c in (0, 2):                                # горизонталь (Y — вверх, его не трогаем)
                ys = [v[c] for v in vals]
                k = (ys[-1] - ys[0]) / max(n - 1, 1)
                ys = [y - k * j for j, y in enumerate(ys)]       # сперва убрать уезд от начала к концу
                w = 7                                            # ±7 ключей ≈ полшага: среднее = поступь
                avg = [sum(ys[(j + d) % n] for d in range(-w, w + 1)) / (2 * w + 1) for j in range(n)]
                base = avg[0]
                for j in range(n):
                    vals[j][c] = ys[0] + (ys[j] - avg[j]) * 0.5  # остаётся только покачивание, приглушённое
            mins = [min(v[c] for v in vals) for c in range(3)]
            maxs = [max(v[c] for v in vals) for c in range(3)]
            for j, v in enumerate(vals):
                struct.pack_into("<3f", raw, off + j * stride, *v)
            acc["min"], acc["max"] = mins, maxs
            print(an["name"], "fixed", n, "keys")
    js = json.dumps(g, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    out = raw[:12] + struct.pack("<I", len(js)) + b"JSON" + js + raw[20 + jlen:]
    struct.pack_into("<I", out, 8, len(out))
    open(dst, "wb").write(out)

main()
