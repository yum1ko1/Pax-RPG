"""Приёмка моделей Meshy для Гхарна (blender -b -P gharn_import.py -- [--only id,…]):
W\\gharn\\<id>\\model.glb → реальный масштаб (высота из HEIGHT, метры), пивот — центр основания, текстуры ≤ 2K
JPEG → W\\gharn\\out\\<id>.glb (оттуда — в mods/pax_rpg/models/gharn/) + превью W\\gharn\\out\\_r_<id>.png.
"""
import math
import os
import sys

import bpy
from mathutils import Vector

W = r"C:\Users\mbkli\Desktop\pax_rpg_work\gharn"
OUT = os.path.join(W, "out")
HEIGHT = {"guild_hall": 16.0, "tavern_hall": 13.0, "fountain_dragon": 4.2, "gate_fang": 14.0, "khan_palace": 22.0,
          "flame_tree": 8.0, "house_shop_a": 9.0, "house_shop_b": 9.0, "house_shop_c": 9.0, "oath_tree": 16.0,
          "shaman_tower": 18.0,
          # версия 3
          "forge_smithy": 9.0, "watch_tower": 12.0, "yurt_noble": 8.0, "stilt_hut": 7.0, "stable_hay": 5.5,
          "house_timber_a": 7.5, "house_timber_b": 7.0, "totem_pole": 4.5, "bone_banner": 4.2, "guardian_statue": 2.6,
          "loot_pile": 1.1, "war_drum": 1.9, "beast_cage": 2.2, "spit_roast": 1.6, "hay_wagon": 2.6, "tusk_arch": 5.5,
          "brazier_tusk": 2.2, "spear_rack": 2.2, "market_stall_hide": 3.2, "mana_totem": 3.0, "hide_frame": 2.4,
          "bucket_set": 0.8}
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = set(ARGS[ARGS.index("--only") + 1].split(",")) if "--only" in ARGS else None


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for coll in (bpy.data.meshes, bpy.data.materials, bpy.data.images):
        for x in list(coll):
            if x.users == 0:
                coll.remove(x)


def bounds(objs):
    lo = Vector((1e9, 1e9, 1e9))
    hi = -lo
    for o in objs:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    return lo, hi


def render(name, objs):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.display.shading.show_shadows = True
    sc.render.resolution_x = sc.render.resolution_y = 600
    lo, hi = bounds(objs)
    size = max(hi - lo)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = size * 1.3
    c = (lo + hi) / 2
    cam.location = c + Vector((0.6, -1.0, 0.55)).normalized() * size * 4
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUT, f"_r_{name}.png")
    bpy.ops.render.render(write_still=True)


def main():
    os.makedirs(OUT, exist_ok=True)
    for name in sorted(os.listdir(W)):
        src = os.path.join(W, name, "model.glb")
        if not os.path.exists(src) or (ONLY and name not in ONLY):
            continue
        clear()
        bpy.ops.import_scene.gltf(filepath=src)
        objs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
        lo, hi = bounds(objs)
        h = HEIGHT.get(name, hi.z - lo.z)
        k = h / max(hi.z - lo.z, 1e-6)
        root = bpy.data.objects.new(name, None)
        bpy.context.scene.collection.objects.link(root)
        for o in bpy.context.scene.objects:
            if o.parent is None and o is not root:
                o.parent = root
        root.scale = (k, k, k)
        root.location = (-(lo.x + hi.x) / 2 * k, -(lo.y + hi.y) / 2 * k, -lo.z * k)
        bpy.context.view_layer.update()
        for o in objs:                                   # применить масштаб и сдвиг в меши
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        for img in bpy.data.images:                      # текстуры ≤ 2K
            if img.size[0] > 2048:
                img.scale(2048, 2048 * img.size[1] // img.size[0])
        tris = sum(len(p.vertices) - 2 for o in objs for p in o.data.polygons)
        lo2, hi2 = bounds(objs)
        d = hi2 - lo2
        print(f"{name}: {tris} tris, {d.x:.1f} x {d.y:.1f} x {d.z:.1f} m", flush=True)
        bpy.ops.object.select_all(action="SELECT")
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, name + ".glb"), use_selection=True, export_yup=True,
                                  export_apply=True, export_image_format="JPEG", export_jpeg_quality=85,
                                  export_animations=False)
        render(name, objs)


main()
