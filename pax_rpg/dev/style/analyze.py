"""Анализ текстур локации (Гхарн): для каждой картинки базового цвета — средний цвет, оттенок, насыщенность,
яркость, контраст, разрешение; плюс лист-превью. Источники: glb из models_src (gharn, props, персонажи, оружие),
текстуры земли, арены (DDS не читаем — исходники jpg из tex4k, если есть).
    python3 pax_rpg/dev/style/analyze.py <out_dir>"""
import colorsys, glob, io, json, os, struct, sys
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
OUT = sys.argv[1]
os.makedirs(OUT, exist_ok=True)


def glb_base_images(path):
    raw = open(path, "rb").read()
    jl = struct.unpack_from("<I", raw, 12)[0]
    g = json.loads(raw[20:20 + jl])
    bo = 20 + jl + 8
    base = set()
    for m in g.get("materials", []):
        bc = m.get("pbrMetallicRoughness", {}).get("baseColorTexture")
        if bc is not None:
            base.add(g["textures"][bc["index"]].get("source"))
    out = []
    for i, im in enumerate(g.get("images", [])):
        if i not in base or "bufferView" not in im:
            continue
        bv = g["bufferViews"][im["bufferView"]]
        data = raw[bo + bv.get("byteOffset", 0): bo + bv.get("byteOffset", 0) + bv["byteLength"]]
        try:
            out.append((i, Image.open(io.BytesIO(data)).convert("RGB")))
        except Exception:
            pass
    return out


def stats(img):
    a = np.asarray(img.resize((128, 128))).astype(np.float32) / 255.0
    flat = a.reshape(-1, 3)
    mean = flat.mean(0)
    hsv = np.array([colorsys.rgb_to_hsv(*p) for p in flat[::7]])
    lum = flat @ np.array([0.2126, 0.7152, 0.0722])
    return {"mean": [round(float(c), 3) for c in mean], "hue": round(float(colorsys.rgb_to_hsv(*mean)[0] * 360), 0),
            "sat": round(float(hsv[:, 1].mean()), 3), "lum": round(float(lum.mean()), 3),
            "contrast": round(float(lum.std()), 3)}


rows = []
for p in sorted(glob.glob(os.path.join(ROOT, "pax_rpg/dev/models_src/**/*.glb"), recursive=True)):
    rel = os.path.relpath(p, os.path.join(ROOT, "pax_rpg/dev/models_src"))
    if rel.startswith("goblin/") and not rel.endswith("goblin_rigged.glb"):
        continue
    for i, img in glb_base_images(p):
        st = stats(img)
        st.update({"src": rel, "img": i, "size": img.size})
        rows.append((st, img))
for p in sorted(glob.glob(os.path.join(ROOT, "mods/pax_rpg/models/gharn/tex/*.jpg"))) + \
        sorted(glob.glob(os.path.join(ROOT, "mods/pax_rpg/models/items/*.jpg"))):
    if any(k in p for k in ("_n.", "_r.", "_h.")):
        continue
    img = Image.open(p).convert("RGB")
    st = stats(img)
    st.update({"src": os.path.relpath(p, ROOT), "img": 0, "size": img.size})
    rows.append((st, img))
extra = sys.argv[2] if len(sys.argv) > 2 else ""
for p in sorted(glob.glob(os.path.join(extra, "*_diff.jpg"))) if extra else []:
    img = Image.open(p).convert("RGB")
    st = stats(img)
    st.update({"src": "arena/" + os.path.basename(p), "img": 0, "size": img.size})
    rows.append((st, img))
json.dump([r[0] for r in rows], open(os.path.join(OUT, "stats.json"), "w"), ensure_ascii=False, indent=1)
# лист-превью: 8 в ряд, подпись — источник и цифры
from PIL import ImageDraw
W = 220
cols = 8
sheet = Image.new("RGB", (cols * W, ((len(rows) + cols - 1) // cols) * (W + 44)), (20, 20, 28))
d = ImageDraw.Draw(sheet)
for k, (st, img) in enumerate(rows):
    x, y = (k % cols) * W, (k // cols) * (W + 44)
    sheet.paste(img.resize((W - 8, W - 8)), (x + 4, y + 4))
    d.text((x + 4, y + W - 2), st["src"][-30:], fill=(230, 230, 230))
    d.text((x + 4, y + W + 14), "h%d s%.2f l%.2f c%.2f %dpx" % (st["hue"], st["sat"], st["lum"], st["contrast"], st["size"][0]),
           fill=(255, 190, 120))
sheet.save(os.path.join(OUT, "sheet.jpg"), quality=85)
print(len(rows), "textures")
for st, _ in rows:
    print("%-48s %5dpx hue %3d sat %.2f lum %.2f con %.2f" % (st["src"][-48:], st["size"][0], st["hue"], st["sat"], st["lum"], st["contrast"]))
