"""4K-текстуры и финальные модели Гхарна (blender -b -P gharn_4k.py -- [--only id,…] [--props|--buildings]):
- простые модели: W\\gharn\\retex\\<id>\\model.glb (текстуры Meshy Retexture, 2K) → размеры как у нашей
  W\\gharn\\props\\<id>.glb (Meshy нормирует к 2 ед.), пивот — центр основания;
- здания: W\\gharn\\out\\<id>.glb (уже в метрах).
Цвет (Base Color) → Real-ESRGAN x4plus на видеокарте → 4096; нормали/шероховатость → просто 4096 (ИИ искажает
данные). Итог — W\\gharn\\final\\<id>.glb (JPEG 90) — в mods/pax_rpg/models/gharn[/props].
"""
import os
import subprocess
import sys

import bpy
from mathutils import Vector

W = r"C:\Users\mbkli\Desktop\pax_rpg_work\gharn"
ESR = r"C:\Users\mbkli\Desktop\pax_rpg_work\tools\esrgan\realesrgan-ncnn-vulkan.exe"
FINAL = os.path.join(W, "final")
TMP = os.path.join(W, "_tmp4k")
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = set(ARGS[ARGS.index("--only") + 1].split(",")) if "--only" in ARGS else None
SIZE = 4096


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for x in list(coll):
            coll.remove(x)


def meshes():
    return [o for o in bpy.context.scene.objects if o.type == "MESH"]


def bounds(objs):
    lo = Vector((1e9,) * 3)
    hi = -lo
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def base_color_images():
    out = set()
    for m in bpy.data.materials:
        if not m.node_tree:
            continue
        for l in m.node_tree.links:
            if l.to_socket.name == "Base Color" and l.from_node.type == "TEX_IMAGE" and l.from_node.image:
                out.add(l.from_node.image.name)
    return out


def upscale_images(name):
    os.makedirs(TMP, exist_ok=True)
    color = base_color_images()
    for img in list(bpy.data.images):
        if img.size[0] == 0 or img.size[0] >= SIZE:
            continue
        if img.name in color:
            src = os.path.join(TMP, f"{name}_in.png")
            dst = os.path.join(TMP, f"{name}_out.png")
            img.filepath_raw = src
            img.file_format = "PNG"
            img.save()
            r = subprocess.run([ESR, "-i", src, "-o", dst, "-n", "realesrgan-x4plus", "-s", "4"],
                               capture_output=True, text=True)
            if os.path.exists(dst):
                up = bpy.data.images.load(dst)
                up.scale(SIZE, SIZE)
                img.scale(SIZE, SIZE)
                img.pixels.foreach_set(up.pixels[:])
                bpy.data.images.remove(up)
                print(f"  {name}: base color → ESRGAN 4K", flush=True)
            else:
                img.scale(SIZE, SIZE)
                print(f"  {name}: ESRGAN не сработал ({r.stderr[-200:]}), просто 4K", flush=True)
        else:
            img.scale(SIZE, SIZE)
        img.pack()


def process(name, src, ref=None):
    clear()
    bpy.ops.import_scene.gltf(filepath=src)
    objs = meshes()
    lo, hi = bounds(objs)
    k = 1.0
    if ref:                                       # к размерам нашей модели
        bpy.ops.import_scene.gltf(filepath=ref)
        refs = [o for o in meshes() if o not in objs]
        rlo, rhi = bounds(refs)
        for o in refs:
            bpy.data.objects.remove(o, do_unlink=True)
        k = (rhi.z - rlo.z) / max(hi.z - lo.z, 1e-6)
    root = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(root)
    for o in bpy.context.scene.objects:
        if o.parent is None and o is not root:
            o.parent = root
    root.scale = (k, k, k)
    root.location = (-(lo.x + hi.x) / 2 * k, -(lo.y + hi.y) / 2 * k, -lo.z * k)
    bpy.context.view_layer.update()
    upscale_images(name)
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=os.path.join(FINAL, name + ".glb"), use_selection=True, export_yup=True,
                              export_apply=True, export_image_format="JPEG", export_jpeg_quality=90,
                              export_animations=False)
    d = bounds(meshes())
    print(f"{name}: {(d[1] - d[0]).x:.2f} x {(d[1] - d[0]).y:.2f} x {(d[1] - d[0]).z:.2f} m", flush=True)


def main():
    os.makedirs(FINAL, exist_ok=True)
    if "--buildings" not in ARGS:
        rt = os.path.join(W, "retex")
        for name in sorted(os.listdir(rt)):
            src = os.path.join(rt, name, "model.glb")
            if os.path.exists(src) and (not ONLY or name in ONLY):
                process(name, src, os.path.join(W, "props", name + ".glb"))
    if "--props" not in ARGS:
        for f in sorted(os.listdir(os.path.join(W, "out"))):
            name = f[:-4]
            if f.endswith(".glb") and (not ONLY or name in ONLY):
                process(name, os.path.join(W, "out", f))


main()
