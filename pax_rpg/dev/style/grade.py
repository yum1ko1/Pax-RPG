"""Единый стиль Гхарна: грейдинг базовых цветов локации (здания, пропсы, земля, арена) к общей палитре —
тёплая охра/умбра, киноварь, сакура, золото. Исходники не трогаем: glb из models_src → models_graded (та же
структура), картинки земли/арены → рядом с _graded. Нормали, шероховатость — без изменений.
По группам цель: средняя яркость, контраст (σ яркости), насыщенность, тон (YCbCr-сдвиг к тёплому) и сила.
    python3 pax_rpg/dev/style/grade.py"""
import glob, io, json, os, struct, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
SRC = os.path.join(ROOT, "pax_rpg/dev/models_src")
DST = os.path.join(ROOT, "pax_rpg/dev/models_graded")
WARM = np.array([0.0, -0.035, 0.045])   # YCbCr сдвиг «тёплой земли» (Cb −, Cr +)

# группа: (яркость, контраст, насыщ., сила тёплого сдвига, сила всего)
GROUPS = {
    "building": (0.29, 0.085, 0.27, 0.6, 0.85),
    "prop":     (0.29, 0.085, 0.26, 0.7, 0.8),
    "accent":   (0.28, 0.09, 0.40, 0.2, 0.5),    # фонари, флаги, мана — цвет оставляем, но не ядовитый
    "ground":   (0.40, 0.08, 0.22, 0.4, 0.9),
    "stone":    (0.34, 0.08, 0.16, 0.8, 0.85),   # фотокамень (булыжник, арена) — теплее, темнее
    "sand":     (0.42, 0.05, 0.30, 0.5, 0.85),
}
SKIP = ("goblin/", "orc/", "knight", "hero_simple", "weapons/", "items/", "buffalo")
ACCENT = ("lantern", "mana_", "banner", "flame_tree", "firepit", "fountain")


def group_of(rel):
    if any(k in rel for k in SKIP):
        return None
    if any(k in rel for k in ACCENT):
        return "accent"
    if rel.startswith("gharn/props/"):
        return "stone" if any(k in rel for k in ("road_cobble", "stairs_stone", "rock_small", "wall_hob")) else "prop"
    return "building"


def to_ycc(a):
    y = a @ np.array([0.299, 0.587, 0.114])
    cb = (a[..., 2] - y) * 0.564
    cr = (a[..., 0] - y) * 0.713
    return y, cb, cr


def from_ycc(y, cb, cr):
    r = y + cr / 0.713
    b = y + cb / 0.564
    g = (y - 0.299 * r - 0.114 * b) / 0.587
    return np.clip(np.stack([r, g, b], -1), 0, 1)


def grade(img, grp):
    lum_t, con_t, sat_t, warm_k, k = GROUPS[grp]
    a = np.asarray(img.convert("RGB")).astype(np.float32) / 255.0
    y, cb, cr = to_ycc(a)
    m, s = float(y.mean()), float(y.std()) + 1e-4
    gain = np.clip(con_t / s, 0.75, 1.6)
    y2 = lum_t + (y - m) * gain
    y2 = y2 + 0.04 * (1 - y2) * np.clip(0.18 - y2, 0, 1) * 5      # чуть приподнять самые чёрные (мягкие тени)
    c = np.sqrt(cb ** 2 + cr ** 2)
    c_mean = float(c.mean()) + 1e-4
    sat_now = c_mean / max(m, 0.05)
    cs = np.clip(sat_t / max(sat_now, 1e-3), 0.55, 1.6)
    hi = np.clip((c - c_mean * 2.2) / (c_mean * 2.0 + 1e-4), 0, 1)    # яркие акценты жмём меньше
    scale = cs * (1 - hi) + np.minimum(1.0, cs * 1.4) * hi
    # тёплый сдвиг: убрать «свой» средний оттенок источника и добавить общий тёплый
    cb2 = (cb - float(cb.mean()) * warm_k) * scale + WARM[1] * warm_k
    cr2 = (cr - float(cr.mean()) * warm_k) * scale + WARM[2] * warm_k
    out = from_ycc(y2, cb2, cr2)
    out = a * (1 - k) + out * k
    return Image.fromarray((np.clip(out, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB")


def regrade_glb(src, dst, grp):
    raw = open(src, "rb").read()
    jl = struct.unpack_from("<I", raw, 12)[0]
    g = json.loads(raw[20:20 + jl])
    bo = 20 + jl + 8
    blen = struct.unpack_from("<I", raw, 20 + jl)[0]
    binc = raw[bo:bo + blen]
    base = set()
    for mt in g.get("materials", []):
        bc = mt.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if bc is not None:
            base.add(g["textures"][bc["index"]].get("source"))
    repl = {}
    for i, im in enumerate(g.get("images", [])):
        if i in base and "bufferView" in im:
            bv = g["bufferViews"][im["bufferView"]]
            data = binc[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]]
            img = Image.open(io.BytesIO(data))
            buf = io.BytesIO()
            mime = im.get("mimeType", "image/jpeg")
            grade(img, grp).save(buf, "PNG" if mime == "image/png" else "JPEG", quality=93)
            repl[im["bufferView"]] = buf.getvalue()
    out = bytearray()
    for vi, bv in enumerate(g["bufferViews"]):
        data = repl.get(vi, binc[bv.get("byteOffset", 0): bv.get("byteOffset", 0) + bv["byteLength"]])
        while len(out) % 4:
            out.append(0)
        bv["byteOffset"] = len(out)
        bv["byteLength"] = len(data)
        out += data
    while len(out) % 4:
        out.append(0)
    g["buffers"][0]["byteLength"] = len(out)
    js = json.dumps(g, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(out)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js)
        f.write(struct.pack("<I4s", len(out), b"BIN\x00") + bytes(out))
    return len(repl)


if __name__ == "__main__":
    n = 0
    for p in sorted(glob.glob(os.path.join(SRC, "**/*.glb"), recursive=True)):
        rel = os.path.relpath(p, SRC)
        grp = group_of(rel)
        dst = os.path.join(DST, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if grp is None:
            open(dst, "wb").write(open(p, "rb").read())   # персонажи, оружие — как есть
            continue
        n += regrade_glb(p, dst, grp)
        print(grp.ljust(9), rel)
    tex = os.path.join(ROOT, "mods/pax_rpg/models/gharn/tex")
    orig = os.path.join(ROOT, "pax_rpg/dev/style/orig")
    os.makedirs(orig, exist_ok=True)
    for name, grp in (("ground.jpg", "ground"), ("cobble.jpg", "stone")):
        keep = os.path.join(orig, name)
        if not os.path.exists(keep):
            open(keep, "wb").write(open(os.path.join(tex, name), "rb").read())
        grade(Image.open(keep), grp).save(os.path.join(tex, name), quality=93)
        print(grp.ljust(9), name)
    if len(sys.argv) > 1:                                    # папка с jpg арены (CC0): *_diff → в ту же папку *_graded
        for p in glob.glob(os.path.join(sys.argv[1], "*_diff.jpg")):
            grp = "sand" if "sand_diff" in p and "blocks" not in p else "stone"
            grade(Image.open(p), grp).save(p.replace("_diff.jpg", "_diffg.jpg"), quality=95)
            print(grp.ljust(9), os.path.basename(p))
    print("ok, текстур:", n)
