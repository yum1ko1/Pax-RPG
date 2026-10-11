"""Бюджет текстур моделей Гхарна: размер картинок в glb — по габариту модели (4K нужен только крупному).
Цвет: ≥6 м — 4096, ≥1.5 м — 2048, мельче — 1024; нормали и шероховатость — вдвое меньше (не меньше 512).
Иначе ~150 картинок 4K без сжатия (игра грузит glb без импорта) не влезают в память — вылет при входе в город.
    python pax_rpg/dev/gharn/tex_budget.py   (правит mods/pax_rpg/models/gharn/**/*.glb на месте)
"""
import glob
import io
import os

import pygltflib
import trimesh
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


def budget(size):
    return 4096 if size >= 6 else 2048 if size >= 1.5 else 1024


for f in sorted(glob.glob(os.path.join(ROOT, "mods/pax_rpg/models/gharn/**/*.glb"), recursive=True)):
    size = float(max(trimesh.load(f).extents))
    g = pygltflib.GLTF2().load(f)
    blob = g.binary_blob()
    base = {t.source for m in g.materials if m.pbrMetallicRoughness and m.pbrMetallicRoughness.baseColorTexture
            for t in [g.textures[m.pbrMetallicRoughness.baseColorTexture.index]]}
    chunks, changed = [], False
    for i, im in enumerate(g.images):
        bv = g.bufferViews[im.bufferView]
        data = blob[bv.byteOffset:bv.byteOffset + bv.byteLength]
        img = Image.open(io.BytesIO(data))
        want = budget(size) if i in base else max(512, budget(size) // 2)
        if img.size[0] > want:
            buf = io.BytesIO()
            img.convert("RGB").resize((want, want), Image.LANCZOS).save(buf, "JPEG", quality=90)
            data = buf.getvalue()
            im.mimeType = "image/jpeg"
            changed = True
        chunks.append(data)
    if not changed:
        continue
    # пересобрать буфер: картинки — заново в конец, прочие виды буфера — как были
    img_views = {im.bufferView for im in g.images}
    out = bytearray()
    for vi, bv in enumerate(g.bufferViews):
        if vi in img_views:
            continue
        d = blob[bv.byteOffset:bv.byteOffset + bv.byteLength]
        while len(out) % 4:
            out += b"\0"
        bv.byteOffset = len(out)
        out += d
    for im, d in zip(g.images, chunks):
        while len(out) % 4:
            out += b"\0"
        bv = g.bufferViews[im.bufferView]
        bv.byteOffset, bv.byteLength = len(out), len(d)
        out += d
    g.buffers[0].byteLength = len(out)
    g.set_binary_blob(bytes(out))
    before = os.path.getsize(f)
    g.save_binary(f)
    print(f"{os.path.relpath(f, ROOT)}: {size:.1f} м → {budget(size)}, {before // 1024} → {os.path.getsize(f) // 1024} КБ")
