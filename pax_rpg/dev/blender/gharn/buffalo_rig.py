"""Демонический буйвол Гхарна (Meshy image-to-3D) → скелет и анимации покоя, glb для мода.
Авториг Meshy — только для людей, поэтому скелет ставится здесь по габаритам модели (доли длины/высоты), веса —
автоматически (Blender), ключи — руками:
  Idle  (4 с, цикл): дышит грудью, переносит вес, хвост машет, голова чуть кивает и оглядывается;
  Graze (5 с, цикл): опускает голову к земле, жуёт, поднимает.
Модель Meshy смотрит на +Z glTF = −Y Blender, Z — вверх.
    blender -b -P buffalo_rig.py -- <model.glb> <out.glb> [папка превью] [высота в холке, м]
"""
import math
import os
import sys

import bpy
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = A[0], A[1]
PREV = A[2] if len(A) > 2 else ""
HEIGHT = float(A[3]) if len(A) > 3 else 2.1         # м, вся высота с рогами
FPS = 30
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=SRC)
sc = bpy.context.scene
sc.render.fps = FPS
meshes = [o for o in sc.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")
if len(meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
for o in [o for o in sc.objects if o.type != "MESH"]:
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
lo = Vector(map(min, *[body.matrix_world @ Vector(c) for c in body.bound_box]))
hi = Vector(map(max, *[body.matrix_world @ Vector(c) for c in body.bound_box]))
k = HEIGHT / (hi.z - lo.z)                            # в метры, низ — на землю, центр — в 0
body.scale = (k, k, k)
body.location = (-(lo.x + hi.x) / 2 * k, -(lo.y + hi.y) / 2 * k, -lo.z * k)
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
L = (hi.y - lo.y) * k                                 # длина (по Y)
H = HEIGHT


def P(fy, fz, x=0.0):
    """Точка по долям: fy — от морды (−0.5) к хвосту (+0.5) длины, fz — доля высоты от земли."""
    return Vector((x * L, fy * L, fz * H))


BONES = [  # имя, голова, хвост, родитель
    ("Hips", P(0.24, 0.6), P(0.0, 0.64), None),
    ("Chest", P(0.0, 0.64), P(-0.22, 0.66), "Hips"),
    ("Neck", P(-0.22, 0.66), P(-0.34, 0.6), "Chest"),
    ("Head", P(-0.34, 0.6), P(-0.5, 0.42), "Neck"),
    ("Tail1", P(0.3, 0.58), P(0.38, 0.5), "Hips"),
    ("Tail2", P(0.38, 0.5), P(0.44, 0.4), "Tail1"),
    ("Tail3", P(0.44, 0.4), P(0.5, 0.32), "Tail2"),
]
for side, sx in (("L", 0.13), ("R", -0.13)):
    for part, fy, par in (("Front", -0.17, "Chest"), ("Hind", 0.2, "Hips")):
        BONES.append((f"{part}Up.{side}", P(fy, 0.5, sx), P(fy, 0.26, sx), par))
        BONES.append((f"{part}Low.{side}", P(fy, 0.26, sx), P(fy, 0.02, sx), f"{part}Up.{side}"))
arm_data = bpy.data.armatures.new("BuffaloRig")
rig = bpy.data.objects.new("Buffalo_rig", arm_data)
sc.collection.objects.link(rig)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.mode_set(mode="EDIT")
for name, h, t, par in BONES:
    eb = arm_data.edit_bones.new(name)
    eb.head, eb.tail = h, t
    if par:
        eb.parent = arm_data.edit_bones[par]
        eb.use_connect = (eb.parent.tail - h).length < 1e-4
bpy.ops.object.mode_set(mode="OBJECT")
bpy.ops.object.select_all(action="DESELECT")
body.select_set(True)
rig.select_set(True)
bpy.context.view_layer.objects.active = rig
bpy.ops.object.parent_set(type="ARMATURE_NAME")     # группы по именам костей; веса — ниже, свои
# веса по расстоянию до отрезков костей (автовеса Blender на сетке Meshy молча не считаются): 3 ближайшие кости,
# вес ~ 1/d^4, ноги не берут вершины корпуса выше бедра, хвост — только позади таза
import numpy as np  # noqa: E402
segs = [(name, np.array(h), np.array(t)) for name, h, t, _ in BONES]
co = np.array([v.co[:] for v in body.data.vertices])
D = np.zeros((len(co), len(segs)))
for j, (name, h, t) in enumerate(segs):
    ab = t - h
    u = np.clip(((co - h) @ ab) / max(ab @ ab, 1e-9), 0.0, 1.0)
    d = np.linalg.norm(co - (h + u[:, None] * ab), axis=1)
    if "Up" in name or "Low" in name:
        d = d + np.where(co[:, 2] > h[2] + 0.05, 9.0, 0.0)          # нога — не выше своего начала
    if name.startswith("Tail"):
        d = d + np.where(co[:, 1] < segs[0][1][1], 9.0, 0.0)        # хвост — только сзади
    D[:, j] = d
W = 1.0 / np.maximum(D, 0.02) ** 4
top = np.argsort(-W, axis=1)[:, :3]
for j, (name, _, _) in enumerate(segs):
    vg = body.vertex_groups.get(name) or body.vertex_groups.new(name=name)
    rows = np.where((top == j).any(axis=1))[0]
    tot = np.take_along_axis(W, top, axis=1).sum(axis=1)
    for i in rows:
        vg.add([int(i)], float(W[i, j] / tot[i]), "REPLACE")
print("weights:", len(body.vertex_groups), "groups", flush=True)
pb = rig.pose.bones
for p in pb:
    p.rotation_mode = "XYZ"


def key(f, name, rot=None, scale=None, loc=None):
    p = pb[name]
    if rot is not None:
        p.rotation_euler = rot
        p.keyframe_insert("rotation_euler", frame=f)
    if scale is not None:
        p.scale = scale
        p.keyframe_insert("scale", frame=f)
    if loc is not None:
        p.location = loc
        p.keyframe_insert("location", frame=f)


def new_action(name):
    a = bpy.data.actions.new(name)
    a.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = a
    for p in pb:
        p.rotation_euler = (0, 0, 0)
        p.scale = (1, 1, 1)
        p.location = (0, 0, 0)
    return a


# Idle: 120 кадров, всё — по синусам кратного периода (цикл без шва)
idle = new_action("Idle")
N = 120
for f in range(0, N + 1, 4):
    t = f / N * math.tau
    breathe = 1.0 + 0.03 * (0.5 - 0.5 * math.cos(t * 2))
    key(f, "Chest", rot=(0.02 * math.sin(t * 2), 0, 0), scale=(breathe, 1.0, breathe))
    key(f, "Hips", rot=(0, 0.025 * math.sin(t), 0), loc=(0.015 * math.sin(t), 0, 0))
    look = 0.5 - 0.5 * math.cos(t)                       # оглядывается: 0 → 1 → 0
    key(f, "Neck", rot=(0.05 * math.sin(t * 2 + 1.0), 0, 0.28 * math.sin(t) * look))
    key(f, "Head", rot=(0.08 * math.sin(t * 3), 0.06 * math.sin(t), 0.18 * math.sin(t) * look))
    key(f, "Tail1", rot=(0.05 * math.sin(t * 2), 0, 0.35 * math.sin(t * 3)))
    key(f, "Tail2", rot=(0, 0, 0.45 * math.sin(t * 3 - 0.8)))
    key(f, "Tail3", rot=(0, 0, 0.6 * math.sin(t * 3 - 1.6)))
    for s in ("L", "R"):                                  # перенос веса: ноги чуть сгибаются по очереди
        ph = 0.0 if s == "L" else math.pi
        key(f, f"HindUp.{s}", rot=(0.04 * math.sin(t + ph), 0, 0))
        key(f, f"HindLow.{s}", rot=(-0.05 * math.sin(t + ph), 0, 0))

# Graze: 150 кадров — голову вниз (30), жуёт (90), вверх (30)
graze = new_action("Graze")
N2 = 150
for f in range(0, N2 + 1, 3):
    d = min(1.0, f / 30.0) if f < 120 else max(0.0, (150 - f) / 30.0)
    d = d * d * (3 - 2 * d)
    chew = 0.06 * math.sin(f / N2 * math.tau * 12) * (1.0 if 30 < f < 120 else 0.0)
    t = f / N2 * math.tau
    key(f, "Chest", rot=(0.12 * d, 0, 0), scale=(1.0 + 0.02 * math.sin(t * 3), 1, 1.0 + 0.02 * math.sin(t * 3)))
    key(f, "Neck", rot=(0.75 * d, 0, 0.1 * math.sin(t) * d))
    key(f, "Head", rot=(0.35 * d + chew, 0, 0))
    key(f, "FrontUp.L", rot=(-0.12 * d, 0, 0))
    key(f, "FrontUp.R", rot=(-0.08 * d, 0, 0))
    key(f, "Tail1", rot=(0, 0, 0.3 * math.sin(t * 2)))
    key(f, "Tail2", rot=(0, 0, 0.4 * math.sin(t * 2 - 0.8)))
    key(f, "Tail3", rot=(0, 0, 0.5 * math.sin(t * 2 - 1.6)))

act = bpy.data.actions["Graze"]
rig.animation_data.action = act
if hasattr(rig.animation_data, "action_slot") and len(getattr(act, "slots", [])):
    rig.animation_data.action_slot = act.slots[0]
for fr in (0, 60):
    sc.frame_set(fr)
    print("debug f", fr, "head", tuple(round(x, 3) for x in (rig.matrix_world @ pb["Head"].head)),
          "mods", [m.type for m in body.modifiers], "fcurves",
          len(getattr(act, "fcurves", [])) or sum(len(cb.fcurves) for l in getattr(act, "layers", [])
                                                 for st in l.strips for cb in st.channelbags), flush=True)
if PREV:
    os.makedirs(PREV, exist_ok=True)
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x, sc.render.resolution_y = 320, 240
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = max(L, H) * 1.25
    for an, n in (("Idle", 120), ("Graze", 150)):
        act = bpy.data.actions[an]
        rig.animation_data.action = act
        if hasattr(rig.animation_data, "action_slot") and len(getattr(act, "slots", [])):
            rig.animation_data.action_slot = act.slots[0]       # Blender 5: без слота действие не играет
        for i in range(5):
            sc.frame_set(round(n * i / 4))
            for vi, (cx, cy, rz) in enumerate(((6.0, -1.5, 75), (1.5, -6.0, 15))):
                cam.location = (cx, cy, H * 0.55)
                cam.rotation_euler = (math.radians(86), 0, math.radians(rz))
                sc.render.filepath = os.path.join(PREV, f"{an}_{vi}_{i}.png")
                bpy.ops.render.render(write_still=True)

ad = rig.animation_data
ad.action = None
for name in ("Idle", "Graze"):
    tr = ad.nla_tracks.new()
    tr.name = name
    a = bpy.data.actions[name]
    st = tr.strips.new(name, int(a.frame_range[0]), a)
    if hasattr(st, "action_slot") and len(getattr(a, "slots", [])):
        st.action_slot = a.slots[0]
for img in bpy.data.images:                           # текстуры 2K: модель не главная в кадре
    if img.size[0] > 2048:
        img.scale(2048, 2048)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animation_mode="NLA_TRACKS",
                          export_force_sampling=True, export_yup=True, export_image_format="JPEG",
                          export_jpeg_quality=88)
print("exported", OUT, round(os.path.getsize(OUT) / 1e6, 1), "MB; L", round(L, 2), "H", H, flush=True)
