"""Облегчить glb-клип Meshy без Blender: оставить узлы, скелет (skin) и анимации, выбросить сетки, материалы и
картинки. Байты анимации и узлы — те же, что в исходнике (Blender при перегонке мог бы повернуть оси костей).

    python slim_glb.py вход.glb выход.glb [вход2.glb выход2.glb ...]
"""
import json
import struct
import sys


def read(path):
    b = open(path, "rb").read()
    assert b[:4] == b"glTF"
    off, js, bin_ = 12, None, b""
    while off < len(b):
        ln, typ = struct.unpack("<II", b[off:off + 8])
        chunk = b[off + 8:off + 8 + ln]
        if typ == 0x4E4F534A:
            js = json.loads(chunk)
        elif typ == 0x004E4942:
            bin_ = chunk
        off += 8 + ln
    return js, bin_


def slim(src, dst):
    g, bin_ = read(src)
    keep_acc = []
    for a in g.get("animations", []):
        for s in a["samplers"]:
            keep_acc += [s["input"], s["output"]]
    for sk in g.get("skins", []):
        if "inverseBindMatrices" in sk:
            keep_acc.append(sk["inverseBindMatrices"])
    keep_acc = sorted(set(keep_acc))
    acc_map, accessors, views, out = {}, [], [], bytearray()
    for i in keep_acc:
        a = dict(g["accessors"][i])
        v = g["bufferViews"][a["bufferView"]]
        data = bin_[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
        while len(out) % 4:
            out.append(0)
        nv = {"buffer": 0, "byteOffset": len(out), "byteLength": len(data)}
        if "byteStride" in v:
            nv["byteStride"] = v["byteStride"]
        out += data
        a["bufferView"] = len(views)
        views.append(nv)
        acc_map[i] = len(accessors)
        accessors.append(a)
    for a in g.get("animations", []):
        for s in a["samplers"]:
            s["input"], s["output"] = acc_map[s["input"]], acc_map[s["output"]]
    for sk in g.get("skins", []):
        if "inverseBindMatrices" in sk:
            sk["inverseBindMatrices"] = acc_map[sk["inverseBindMatrices"]]
    nodes = []
    for n in g["nodes"]:
        n = {k: v for k, v in n.items() if k not in ("mesh", "skin")}
        nodes.append(n)
    while len(out) % 4:
        out.append(0)
    res = {"asset": g["asset"], "scene": g.get("scene", 0), "scenes": g["scenes"], "nodes": nodes,
           "skins": g.get("skins", []), "animations": g.get("animations", []), "accessors": accessors,
           "bufferViews": views, "buffers": [{"byteLength": len(out)}]}
    js = json.dumps(res, separators=(",", ":")).encode()
    while len(js) % 4:
        js += b" "
    total = 12 + 8 + len(js) + 8 + len(out)
    with open(dst, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(out), 0x004E4942) + bytes(out))
    print(dst, total)


if __name__ == "__main__":
    a = sys.argv[1:]
    for i in range(0, len(a), 2):
        slim(a[i], a[i + 1])
