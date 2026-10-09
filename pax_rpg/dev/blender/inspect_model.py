"""Разбор модели персонажа (Meshy): геометрия, материалы, текстуры, риг + рендеры спереди, сбоку, сзади.

    blender -b <файл.blend> --python inspect_model.py -- <папка_для_рендеров>
    blender -b --python inspect_model.py -- <папка_для_рендеров> <файл.glb|.fbx|.obj>
"""
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out_dir = argv[0] if argv else os.path.join(os.path.expanduser("~"), "Desktop")
src = argv[1] if len(argv) > 1 else ""

if src:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ext = os.path.splitext(src)[1].lower()
    if ext in (".glb", ".gltf"):
        bpy.ops.import_scene.gltf(filepath=src)
    elif ext == ".fbx":
        bpy.ops.import_scene.fbx(filepath=src)
    elif ext == ".obj":
        bpy.ops.wm.obj_import(filepath=src)

print("=== FILE:", bpy.data.filepath or src)
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
total_v = total_t = 0
lo = Vector((1e9, 1e9, 1e9))
hi = Vector((-1e9, -1e9, -1e9))
for o in bpy.data.objects:
    line = f"OBJ {o.name!r} type={o.type} loc={tuple(round(x, 3) for x in o.location)} " \
           f"rot={tuple(round(math.degrees(x), 1) for x in o.rotation_euler)} scale={tuple(round(x, 3) for x in o.scale)} " \
           f"parent={o.parent.name if o.parent else None}"
    if o.type == "MESH":
        me = o.data
        tris = sum(len(p.vertices) - 2 for p in me.polygons)
        total_v += len(me.vertices)
        total_t += tris
        line += f" verts={len(me.vertices)} faces={len(me.polygons)} tris={tris} uv={len(me.uv_layers)} " \
                f"vgroups={len(o.vertex_groups)} mods={[m.type for m in o.modifiers]} " \
                f"mats={[s.material.name if s.material else None for s in o.material_slots]}"
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector(map(min, lo, w))
            hi = Vector(map(max, hi, w))
    if o.type == "ARMATURE":
        line += f" bones={len(o.data.bones)} first={[b.name for b in o.data.bones][:12]}"
    print(line)
print(f"TOTAL verts={total_v} tris={total_t}")
if meshes:
    print("BOUNDS min", tuple(round(x, 3) for x in lo), "max", tuple(round(x, 3) for x in hi),
          "size", tuple(round(x, 3) for x in (hi - lo)))
for m in bpy.data.materials:
    if not m.use_nodes:
        continue
    nodes = [(n.type, n.image.name if getattr(n, "image", None) else "") for n in m.node_tree.nodes]
    print(f"MAT {m.name!r}: {nodes}")
for img in bpy.data.images:
    print(f"IMG {img.name!r} size={tuple(img.size)} packed={img.packed_file is not None} path={img.filepath!r}")
for a in bpy.data.actions:
    print(f"ACTION {a.name!r} frames={tuple(a.frame_range)}")

# ---- рендеры: workbench с текстурами, три стороны
if meshes:
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    scene.display.shading.light = "STUDIO"
    scene.display.shading.color_type = "TEXTURE"
    scene.display.shading.show_cavity = True
    scene.render.resolution_x = 512
    scene.render.resolution_y = 768
    scene.render.image_settings.file_format = "JPEG"
    scene.render.image_settings.quality = 85
    scene.render.film_transparent = False
    world = scene.world or bpy.data.worlds.new("W")
    scene.world = world
    centre = (lo + hi) / 2
    size = hi - lo
    cam_data = bpy.data.cameras.new("InspectCam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = max(size.z, size.x) * 1.15
    cam = bpy.data.objects.new("InspectCam", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    dist = max(size) * 3
    os.makedirs(out_dir, exist_ok=True)
    # glTF: персонаж смотрит вдоль -Y Blender (вперёд +Y glTF после импорта → -Y)
    for name, d in (("front", Vector((0, -1, 0))), ("side", Vector((1, 0, 0))), ("back", Vector((0, 1, 0)))):
        cam.location = centre + d * dist
        cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
        scene.render.filepath = os.path.join(out_dir, f"inspect_{name}.jpg")
        bpy.ops.render.render(write_still=True)
        print("RENDER", scene.render.filepath)
