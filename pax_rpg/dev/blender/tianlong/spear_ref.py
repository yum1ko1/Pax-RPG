"""Копьё Алого Заката (CrimsonSpear из модели Тянь Лун) отдельно, вертикально — референс для иконки оружия.
Прозрачный фон, свет как в turnaround.py. Eevee, 768×1536.
    blender -b -P spear_ref.py -- <tian_long/model.glb> <папка вывода>
Кадры: spear_front, spear_side (повёрнуто на 90° вокруг древка).
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

A = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = A[0], A[1]
os.makedirs(OUT, exist_ok=True)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=SRC)
sc = bpy.context.scene
spear = next(o for o in sc.objects if o.type == "MESH" and "spear" in o.name.lower())
for o in sc.objects:
    o.hide_render = o is not spear
for poly in spear.data.polygons:
    poly.use_smooth = True
mw = spear.matrix_world.copy()
spear.parent = None
spear.matrix_world = mw
bpy.context.view_layer.update()
pts = [spear.matrix_world @ Vector(c) for c in spear.bound_box]
lo = Vector(map(min, *pts))
hi = Vector(map(max, *pts))
dims = hi - lo
axis = max(range(3), key=lambda i: dims[i])           # древко — вдоль самой длинной стороны рамки
up = Vector((0, 0, 0))
up[axis] = 1
spear.matrix_world = up.rotation_difference(Vector((0, 0, 1))).to_matrix().to_4x4() @ spear.matrix_world
bpy.context.view_layer.update()
pts = [spear.matrix_world @ Vector(c) for c in spear.bound_box]
lo = Vector(map(min, *pts))
hi = Vector(map(max, *pts))
mid = sum((spear.matrix_world @ v.co for v in spear.data.vertices), Vector()) / len(spear.data.vertices)
if mid.z < (lo.z + hi.z) / 2:                         # наконечник (где гуще вершины) — вверх
    spear.matrix_world = Matrix.Rotation(math.pi, 4, "X") @ spear.matrix_world
c = (lo + hi) / 2
h = hi.z - lo.z

sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in
    bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 768, 1536
sc.render.film_transparent = True
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.05, 0.055, 1)
sc.world = w
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = h * 1.08
lights = []
for name, col, en in (("key", (1.0, 0.92, 0.85), 220), ("rim", (1.0, 0.22, 0.2), 380), ("fill", (0.75, 0.8, 1.0), 60)):
    l = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
    l.data.color, l.data.energy, l.data.size = col, en, 1.5
    sc.collection.objects.link(l)
    lights.append(l)

for name, yaw in (("spear_front", 0), ("spear_side", 90)):
    d = Vector((math.sin(math.radians(yaw)), -math.cos(math.radians(yaw)), 0))
    side = Vector((-d.y, d.x, 0))
    cam.location = c + d * (h + 2)
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    for l, off in zip(lights, (side * 1.5 + d * 2 + Vector((0, 0, h * 0.4)),
                               -d * 2 - side * 1.2 + Vector((0, 0, h * 0.3)),
                               -side * 2 + d * 1.5)):
        l.location = c + off
        l.rotation_euler = (c - l.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("shot", sc.render.filepath, flush=True)
