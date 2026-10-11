"""Убрать из клипа glb горизонтальный сдвиг кости (по умолчанию Hips): x и z всех кадров = как в первом кадре,
высота остаётся. Отлёт и шаги в игре делает физика, клип только позу — иначе тело уезжает от капсулы.

    python flatten_root.py файл.glb [файл2.glb ...]     (переписывает на месте)
"""
import json
import struct
import sys

BONE = "Hips"


def flatten(path):
    b = bytearray(open(path, "rb").read())
    off, js, js_off, bin_off = 12, None, 0, 0
    while off < len(b):
        ln, typ = struct.unpack("<II", b[off:off + 8])
        if typ == 0x4E4F534A:
            js = json.loads(bytes(b[off + 8:off + 8 + ln]))
        elif typ == 0x004E4942:
            bin_off = off + 8
        off += 8 + ln
    n = 0
    for a in js.get("animations", []):
        for ch in a["channels"]:
            if ch["target"]["path"] != "translation" or js["nodes"][ch["target"]["node"]].get("name") != BONE:
                continue
            acc = js["accessors"][a["samplers"][ch["sampler"]]["output"]]
            v = js["bufferViews"][acc["bufferView"]]
            o = bin_off + v.get("byteOffset", 0) + acc.get("byteOffset", 0)
            vals = list(struct.unpack("<%df" % (acc["count"] * 3), b[o:o + acc["count"] * 12]))
            x0, z0 = vals[0], vals[2]
            for i in range(acc["count"]):
                vals[3 * i], vals[3 * i + 2] = x0, z0
            b[o:o + acc["count"] * 12] = struct.pack("<%df" % (acc["count"] * 3), *vals)
            n += 1
    open(path, "wb").write(bytes(b))     # min/max в JSON не переписываем: длина куска не меняется
    print(path, "channels", n)


if __name__ == "__main__":
    for p in sys.argv[1:]:
        flatten(p)
