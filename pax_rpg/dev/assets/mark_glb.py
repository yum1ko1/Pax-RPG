"""Заглушки картинок glb мода (PNG 1×1 от strip_glb.py) → с номером t<N>.dds в пикселе: RGBA = (N, 90, 165, 255).
Игра (assets.gd → _textures) читает номер из пикселя — DDS не зависит от того, как загрузчик игры обходит и делит
картинки. Номера — из tex_map.gd (тот же обход, что при сжатии). Картинка без номера — прежняя белая заглушка.
    python mark_glb.py <папка models мода> <tex_map.json>
"""
import json
import struct
import sys
import zlib


def png1(r, g, b, a):
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)
    raw = bytes([0, r, g, b, a])
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


def mark(path, nums):
    b = open(path, "rb").read()
    jl = struct.unpack_from("<I", b, 12)[0]
    j = json.loads(b[20:20 + jl])
    off = 20 + jl
    bin_ = b[off + 8:off + 8 + struct.unpack_from("<I", b, off)[0]] if off < len(b) else b""
    by_view = {}
    for i, im in enumerate(j.get("images", [])):
        if "bufferView" in im and i < len(nums) and nums[i] >= 0:
            by_view[im["bufferView"]] = png1(nums[i], 90, 165, 255)
            im["mimeType"] = "image/png"
    out = bytearray()
    for i, v in enumerate(j.get("bufferViews", [])):
        o = v.get("byteOffset", 0)
        data = by_view.get(i, bin_[o:o + v["byteLength"]])
        while len(out) % 4:
            out.append(0)
        v["byteOffset"] = len(out)
        v["byteLength"] = len(data)
        out += data
    while len(out) % 4:
        out.append(0)
    j["buffers"] = [{"byteLength": len(out)}]
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    glb = struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out))
    glb += struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(out), 0x004E4942) + bytes(out)
    open(path, "wb").write(glb)
    return len(by_view)


if __name__ == "__main__":
    root, mp = sys.argv[1], json.load(open(sys.argv[2]))
    for rel, nums in sorted(mp.items()):
        print(rel, mark(root + "/" + rel, nums))
