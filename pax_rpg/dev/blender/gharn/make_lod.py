"""LOD-копии тяжёлых построек Гхарна: <id>.glb → <id>_lo.glb (Decimate, ~TARGET граней, UV и материалы те же).
    blender -b -P make_lod.py -- C:\\...\\gharn\\out house_two_a,house_two_b [12000]
Город (city.gd) рисует копию дальше LOD_NEAR м, полную модель — ближе.
"""
import os
import sys

import bpy

a = sys.argv[sys.argv.index("--") + 1:]
OUT, ids = a[0], a[1].split(",")
TARGET = int(a[2]) if len(a) > 2 else 12000
for k in ids:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=os.path.join(OUT, k + ".glb"))
    objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    tris = sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)
    ratio = min(1.0, TARGET / max(tris, 1))
    for o in objs:
        m = o.modifiers.new("lod", "DECIMATE")
        m.ratio = ratio
        m.use_collapse_triangulate = True
        bpy.context.view_layer.objects.active = o
        bpy.ops.object.modifier_apply(modifier="lod")
    after = sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, k + "_lo.glb"), export_format="GLB", export_yup=True)
    print(f"{k}: {tris} → {after} tris", flush=True)
