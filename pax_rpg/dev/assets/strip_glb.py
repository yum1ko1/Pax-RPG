"""glb без картинок: каждая картинка → PNG 1×1 (текстуры игра берёт из <name>.tex/*.dds — bake_textures.gd).
Без этого Godot при загрузке glb создаёт несжатые 4K-текстуры, которые всё равно заменяются.
    python strip_glb.py <исходный.glb> <выход.glb>
"""
import base64
import json
import struct
import sys

PNG1 = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAIAAACQd1PeAAAADElEQVR4nGP4//8/AAX+Av4N70a4AAAAAElFTkSuQmCC")


def strip(src, dst):
    b = open(src, "rb").read()
    jl = struct.unpack_from("<I", b, 12)[0]
    j = json.loads(b[20:20 + jl])
    off = 20 + jl
    bin_ = b""
    if off < len(b):
        bl = struct.unpack_from("<I", b, off)[0]
        bin_ = b[off + 8:off + 8 + bl]
    img_views = {im["bufferView"] for im in j.get("images", []) if "bufferView" in im}
    for im in j.get("images", []):
        if "bufferView" in im:
            im["mimeType"] = "image/png"
    out = bytearray()
    for i, v in enumerate(j.get("bufferViews", [])):
        data = PNG1 if i in img_views else bin_[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
        while len(out) % 4:
            out.append(0)
        v["byteOffset"] = len(out)
        v["byteLength"] = len(data)
        out += data
    while len(out) % 4:
        out.append(0)
    if j.get("buffers"):
        j["buffers"][0]["byteLength"] = len(out)
    js = json.dumps(j, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    body = struct.pack("<II", len(js), 0x4E4F534A) + js + struct.pack("<II", len(out), 0x004E4942) + bytes(out)
    open(dst, "wb").write(struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body)


if __name__ == "__main__":
    strip(sys.argv[1], sys.argv[2])
