"""Оружие из glb отдельно, горизонтально — референс для иконок и арта (катана, ножны и т. п.).
Все меши glb склеиваются в один, длинная сторона — по горизонтали; два вида с поворотом на 90° вокруг длинной оси.
Прозрачный фон, свет как в tianlong/turnaround.py. Eevee, 1536×512.
    blender -b -P weapon_ref.py -- <weapon.glb> <папка вывода> <имя>
Кадры: <имя>_a, <имя>_b.
"""
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

A = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, NAME = A[0], A[1], A[2]
os.makedirs(OUT, exist_ok=True)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=SRC)
sc = bpy.context.scene
meshes = [o for o in sc.objects if o.type == "MESH"]
for o in meshes:
    mw = o.matrix_world.copy()
    o.parent = None
    o.matrix_world = mw
    for poly in o.data.polygons:
        poly.use_smooth = True
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
if len(meshes) > 1:
    bpy.ops.object.join()
w = bpy.context.view_layer.objects.active
co = [v.co.copy() for v in w.data.vertices]
lo = Vector(map(min, *co))
hi = Vector(map(max, *co))
axis = max(range(3), key=lambda i: (hi - lo)[i])      # клинок — вдоль самой длинной стороны рамки
long = Vector((0, 0, 0))
long[axis] = 1
w.matrix_world = long.rotation_difference(Vector((1, 0, 0))).to_matrix().to_4x4()
bpy.context.view_layer.update()
pts = [w.matrix_world @ v for v in co]
lo = Vector(map(min, *pts))
hi = Vector(map(max, *pts))
c = (lo + hi) / 2
L = hi.x - lo.x

sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in
    bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 1536, 512
sc.render.film_transparent = True
sc.view_settings.view_transform = "Standard"
wd = bpy.data.worlds.new("w")
wd.use_nodes = True
wd.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.05, 0.055, 1)
sc.world = wd
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.type = "ORTHO"
cam.data.ortho_scale = L * 1.06
lights = []
for name, col, en in (("key", (1.0, 0.92, 0.85), 220), ("rim", (1.0, 0.22, 0.2), 300), ("fill", (0.75, 0.8, 1.0), 70)):
    l = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
    l.data.color, l.data.energy, l.data.size = col, en, 1.5
    sc.collection.objects.link(l)
    lights.append(l)

d = Vector((0, -1, 0))                                # камера спереди; второй вид — оружие повёрнуто вокруг своей оси
cam.location = c + d * (L + 2)
cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
for l, off in zip(lights, (Vector((L * 0.3, -2, 1.5)), Vector((-L * 0.3, 2, 1.0)), Vector((0, -1.5, -1.5)))):
    l.location = c + off
    l.rotation_euler = (c - l.location).to_track_quat("-Z", "Y").to_euler()
base = w.matrix_world.copy()
for tag, roll in (("a", 0), ("b", 90)):
    w.matrix_world = Matrix.Translation(c) @ Matrix.Rotation(math.radians(roll), 4, "X") @ Matrix.Translation(-c) @ base
    sc.render.filepath = os.path.join(OUT, f"{NAME}_{tag}.png")
    bpy.ops.render.render(write_still=True)
    print("shot", sc.render.filepath, flush=True)
