"""Портрет Тянь Лун для выбора героя и HUD: как у рыцаря (dev/blender/knight/portrait.py), но с родными текстурами модели, розовый контровой свет
и голубой заполняющий (палитра «Сакура и сталь»). Eevee, 512².
    blender -b -P portrait.py -- <tian_long/model.glb> <out.png>
"""
import math
import sys

import bpy
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = A[0], A[1]
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=SRC)
sc = bpy.context.scene
arm = [o for o in sc.objects if o.type == "ARMATURE"][0]
if arm.animation_data:
    arm.animation_data.action = None
for o in sc.objects:                                   # мечи и прочее — не в кадр
    if o.type == "MESH" and o.name.startswith("Sword"):
        o.hide_render = True
for o in sc.objects:                                   # свои текстуры модели — только сглаживание
    if o.type == "MESH":
        for poly in o.data.polygons:
            poly.use_smooth = True
bpy.context.view_layer.update()
pb = {b.name.lower(): b for b in arm.pose.bones}
hb = next(b for k, b in pb.items() if k.endswith("head") and "top" not in k and "end" not in k)
nb = next(b for k, b in pb.items() if k.endswith("neck") or k.endswith("neck1"))
head = arm.matrix_world @ hb.head
neck = arm.matrix_world @ nb.head
c = head + (head - neck) * 0.6
sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in
    bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
sc.render.resolution_x = sc.render.resolution_y = 512
sc.render.film_transparent = False
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.03, 0.03, 0.08, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.04
sc.world = w
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.lens = 85
d = Vector((-0.55, -1.0, 0.12)).normalized()          # рыцарь смотрит на −Y: камера спереди-слева
cam.location = c + d * 1.25
cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
for name, col, en, pos in (("rim", (1.0, 0.45, 0.75), 70, (0.9, 0.9, 0.5)), ("fill", (0.45, 0.75, 1.0), 14, (-1.2, -1.0, 0.2)),
                           ("key", (1.0, 0.9, 0.85), 22, (-0.4, -1.2, 0.9))):
    l = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
    l.data.color = col
    l.data.energy = en
    l.data.size = 0.6
    sc.collection.objects.link(l)
    l.location = c + Vector(pos)
    l.rotation_euler = (c - l.location).to_track_quat("-Z", "Y").to_euler()
sc.world.color = (0.03, 0.03, 0.08)
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("portrait", OUT, flush=True)
