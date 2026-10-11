"""Кадры смерти воина для экрана загрузки: анимация Meshy «Fall Dead from Abdominal Injury» на риге рыцаря →
чёрный силуэт сбоку (смотрит влево), неподвижная камера, прозрачный фон. Начало — с момента, когда он уже на
колене (бёдра низко), до конца; первый кадр экран загрузки держит, пока катаны вонзаются.
    blender -b -P death_frames.py -- <animation.glb> <папка для кадров> [кадров]
→ <папка>/f_000.png … (512², RGBA)
"""
import math
import os
import sys

import bpy
from mathutils import Vector

ARGS = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = ARGS[0], ARGS[1]
N = int(ARGS[2]) if len(ARGS) > 2 else 32
os.makedirs(OUT, exist_ok=True)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=SRC)
sc = bpy.context.scene
arm = [o for o in sc.objects if o.type == "ARMATURE"][0]
meshes = [o for o in sc.objects if o.type == "MESH"]
act = arm.animation_data.action if arm.animation_data else None
f0, f1 = (int(act.frame_range[0]), int(act.frame_range[1])) if act else (1, 60)
hips = arm.pose.bones.get("Hips")


def hips_z(f):
    sc.frame_set(f)
    return (arm.matrix_world @ hips.head).z


def bounds(f):
    sc.frame_set(f)
    dg = bpy.context.evaluated_depsgraph_get()
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for m in meshes:
        ev = m.evaluated_get(dg)
        me = ev.to_mesh()
        for v in list(me.vertices)[::7]:
            p = ev.matrix_world @ v.co
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
        ev.to_mesh_clear()
    return lo, hi


stand = hips_z(f0)
zs = [(f, hips_z(f)) for f in range(f0, f1 + 1)]
low = min(z for _, z in zs)
# на колене: бёдра опустились до ~половины пути к самой низкой точке и почти не движутся
start = f0
for i, (f, z) in enumerate(zs[:-3]):
    if z < stand - (stand - low) * 0.45 and abs(zs[i + 3][1] - z) < 0.03:
        start = f
        break
print(f"frames {f0}..{f1}, stand {stand:.2f}, low {low:.2f}, kneel from {start}", flush=True)
lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
for f in range(start, f1 + 1, 3):
    a, b = bounds(f)
    lo, hi = Vector(map(min, lo, a)), Vector(map(max, hi, b))
size = max(hi.y - lo.y, hi.z - lo.z) * 1.08
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = size
cx = (lo.x + hi.x) / 2
cam.location = (cx + 10.0, (lo.y + hi.y) / 2, lo.z + size / 2 - size * 0.04)   # сбоку: +X → смотрит на −X
cam.rotation_euler = (math.pi / 2, 0, math.pi / 2)
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "FLAT"
sc.display.shading.color_type = "SINGLE"
sc.display.shading.single_color = (0.0, 0.0, 0.0)
sc.display.shading.show_shadows = False
sc.display.shading.show_cavity = False
sc.render.film_transparent = True
sc.render.resolution_x = sc.render.resolution_y = 512
sc.render.image_settings.file_format = "PNG"
sc.render.image_settings.color_mode = "RGBA"
sc.view_settings.view_transform = "Standard"
for i in range(N):
    f = round(start + (f1 - start) * i / (N - 1))
    sc.frame_set(f)
    sc.render.filepath = os.path.join(OUT, f"f_{i:03d}.png")
    bpy.ops.render.render(write_still=True)
print("done", N, "frames, size", round(size, 2), flush=True)
