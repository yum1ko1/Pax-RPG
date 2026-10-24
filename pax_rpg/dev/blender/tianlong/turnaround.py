"""Тянь Лун в полный рост с разных сторон — референс для арта (центр инвентаря, концепты в GPT).
Родные текстуры модели, свет в палитре HUD (тёплый ключ, багровый контровой), тёмно-серый фон. Eevee, 1024×1536.
    blender -b -P turnaround.py -- <tian_long/model.glb> <папка вывода>
Кадры: idle_front, idle_34, idle_side, idle_back (клип Idle) и hero_34 (клип CombatIdle).
"""
import math
import os
import sys

import bpy
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = A[0], A[1]
os.makedirs(OUT, exist_ok=True)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=SRC)
sc = bpy.context.scene
arm = [o for o in sc.objects if o.type == "ARMATURE"][0]
meshes = [o for o in sc.objects if o.type == "MESH"]
for o in meshes:
    for poly in o.data.polygons:
        poly.use_smooth = True
if not arm.animation_data:
    arm.animation_data_create()


def pose(clip: str, at: float = 0.3):
    act = bpy.data.actions.get(clip)
    arm.animation_data.action = act
    if act:
        a, b = act.frame_range
        sc.frame_set(int(a + (b - a) * at))
    bpy.context.view_layer.update()


def bounds() -> tuple:
    dg = bpy.context.evaluated_depsgraph_get()
    lo, hi = Vector((1e9,) * 3), Vector((-1e9,) * 3)
    for o in meshes:
        e = o.evaluated_get(dg)
        for v in e.to_mesh().vertices:
            p = e.matrix_world @ v.co
            lo = Vector(map(min, lo, p))
            hi = Vector(map(max, hi, p))
        e.to_mesh_clear()
    return lo, hi


def forward() -> Vector:
    """Куда смотрит лицо: от головы к глазам, по горизонтали."""
    pose("Idle")
    pb = {b.name.lower(): b for b in arm.pose.bones}
    hb = next(b for k, b in pb.items() if k.endswith("head") and "top" not in k and "end" not in k)
    head = arm.matrix_world @ hb.head
    eyes = [o for o in meshes if o.name.startswith("Eye_")]
    if not eyes:
        return Vector((0, -1, 0))
    c = sum((o.matrix_world @ Vector(o.bound_box[0]).lerp(Vector(o.bound_box[6]), 0.5) for o in eyes), Vector()) / len(eyes)
    f = c - head
    f.z = 0
    return f.normalized() if f.length > 1e-4 else Vector((0, -1, 0))


FWD = forward()
sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in
    bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 1024, 1536
sc.render.film_transparent = False
sc.view_settings.view_transform = "Standard"
w = bpy.data.worlds.new("w")
w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.09, 0.09, 0.1, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
sc.world = w
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
cam.data.lens = 70
lights = []
for name, col, en in (("key", (1.0, 0.92, 0.85), 260), ("rim", (1.0, 0.22, 0.2), 420), ("fill", (0.75, 0.8, 1.0), 70)):
    l = bpy.data.objects.new(name, bpy.data.lights.new(name, "AREA"))
    l.data.color, l.data.energy, l.data.size = col, en, 1.2
    sc.collection.objects.link(l)
    lights.append(l)


def shot(name: str, clip: str, yaw_deg: float):
    pose(clip)
    lo, hi = bounds()
    c = (lo + hi) / 2
    h = hi.z - lo.z
    yaw = math.radians(yaw_deg)
    d = Vector((FWD.x * math.cos(yaw) - FWD.y * math.sin(yaw), FWD.x * math.sin(yaw) + FWD.y * math.cos(yaw), 0))
    side = Vector((-d.y, d.x, 0))
    fov = 2 * math.atan(cam.data.sensor_width / 2 / cam.data.lens)   # sensor_fit AUTO: сенсор — по высоте кадра
    dist = h * 1.12 / 2 / math.tan(fov / 2)
    cam.location = c + d * dist + Vector((0, 0, h * 0.04))
    cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
    for l, off in zip(lights, ((side * 1.6 + d * 2.2 + Vector((0, 0, 1.6))),
                               (-d * 2.4 - side * 1.2 + Vector((0, 0, 1.4))),
                               (-side * 2.2 + d * 1.6 + Vector((0, 0, 0.3))))):
        l.location = c + off
        l.rotation_euler = (c - l.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("shot", sc.render.filepath, flush=True)


shot("idle_front", "Idle", 0)
shot("idle_34", "Idle", 35)
shot("idle_side", "Idle", 90)
shot("idle_back", "Idle", 180)
shot("hero_34", "CombatIdle", 30)
