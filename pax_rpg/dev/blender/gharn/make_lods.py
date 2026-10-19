"""LOD-копии тяжёлых неподвижных моделей: <id>.glb → <id>_lod1.glb (~30 % граней, средняя даль) и <id>_lod2.glb
(~12 %, дальняя). Decimate (collapse), развёртка и материалы те же — игра берёт материалы и текстуры основной
модели (assets.gd → lod_base), город переключает по дальности (city.gd). Картинки в копиях — те же 1×1 PNG.
    blender -b -P make_lods.py -- <папка models мода> <список путей через запятую> [r1=0.30] [r2=0.12]
"""
import os, sys
import bpy

a = sys.argv[sys.argv.index("--") + 1:]
ROOT, ids = a[0], a[1].split(",")
R1 = float(a[2]) if len(a) > 2 else 0.30
R2 = float(a[3]) if len(a) > 3 else 0.12
MIN_TRIS = 300


def tris_of(objs):
    return sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)


for k in ids:
    src = os.path.join(ROOT, k + ".glb")
    for suf, ratio in (("_lod1", R1), ("_lod2", R2)):
        bpy.ops.wm.read_factory_settings(use_empty=True)
        bpy.ops.import_scene.gltf(filepath=src)
        objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
        t0 = tris_of(objs)
        r = max(ratio, MIN_TRIS / max(t0, 1))
        for o in objs:
            bpy.context.view_layer.objects.active = o
            o.select_set(True)
            # без склейки вершин: склеенные по швам UV сетки Meshy Decimate тянет в шипы (проверено)
            m = o.modifiers.new("lod", "DECIMATE")
            m.decimate_type = "COLLAPSE"
            m.ratio = min(1.0, r)
            m.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier="lod")
        t1 = tris_of(objs)
        bpy.ops.export_scene.gltf(filepath=os.path.join(ROOT, k + suf + ".glb"), export_format="GLB", export_yup=True,
                                  export_image_format="AUTO", export_animations=False, export_skins=False)
        print(f"LOD {k}{suf}: {t0} → {t1} tris", flush=True)
