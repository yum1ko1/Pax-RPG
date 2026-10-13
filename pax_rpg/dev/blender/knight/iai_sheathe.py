"""Иай: клип IaiSheathe — сидя на колене, правая рука держит рукоять (клинок сильно выдвинут), ведёт её к ножнам
и вгоняет клинок; левая придерживает ножны у устья. Основа — первая поза IaiHold; руки — IK на точки катаны,
положение катаны то же, что в iai.gd (_attach_katana: от кости Hips в осях модели). Длина — звук iai_sheathe.
    blender -b -P iai_sheathe.py -- <knight.glb с IaiHold> <out.glb> <секунд> [превью.png]
"""
import json
import math
import struct
import sys

import bpy
from mathutils import Euler, Matrix, Vector

A = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, SECS = A[0], A[1], float(A[2])
PREVIEW = A[3] if len(A) > 3 else ""
FPS = 30
DRAW0 = 0.24                # м — насколько клинок выдвинут в начале (в iai.gd — SHEATHE_OUT)
GRIP = 0.09                 # м — кулак от цубы по рукояти
SAYA = -0.07                # м — левая рука на ножнах ниже устья


def draw_at(t):             # доля клипа → выдвинут, м: держит 0.12, ведёт до 0.85, дальше в ножнах
    u = min(max((t - 0.12) / 0.73, 0.0), 1.0)
    return DRAW0 * (1.0 - u * u * (3 - 2 * u))


sc = bpy.context.scene
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=SRC)
sc.render.fps, sc.render.fps_base = FPS, 1.0
rig = [o for o in sc.objects if o.type == "ARMATURE"][0]
acts = {a.name.split("_Knight")[0].split(".")[0]: a for a in bpy.data.actions}
ad = rig.animation_data or rig.animation_data_create()
for tr in list(ad.nla_tracks):
    ad.nla_tracks.remove(tr)
PB = rig.pose.bones
MW = rig.matrix_world


def g2b(v):                 # Godot (x, y, z) → Blender (x, −z, y)
    return Vector((v.x, -v.z, v.y))


R = (Matrix.Rotation(math.radians(-8), 3, "Y") @ Matrix.Rotation(math.radians(-15), 3, "X"))
ORIGIN = Vector((0.17, -0.04, 0.13))


def katana_pt(along):       # точка на оси катаны (Godot, +Z — к рукояти), в мире Blender
    hip = (MW @ PB["Hips"].matrix).translation
    return hip + MW.to_3x3().normalized() @ g2b(ORIGIN + R @ Vector((0, 0, along)))


ad.action = acts["IaiHold"]
sc.frame_set(0)
base = {p.name: (p.location.copy(), p.rotation_quaternion.copy()) for p in PB}
ad.action = None
for p in PB:
    p.location, p.rotation_quaternion = base[p.name]
bpy.context.view_layer.update()


def _rot_bone(bone, frm, to):
    """Повернуть кость в мире так, чтобы направление frm стало to (вокруг её головы)."""
    pb = PB[bone]
    W = MW @ pb.matrix
    q = frm.rotation_difference(to).to_matrix().to_4x4()
    h = W.translation.copy()
    W2 = Matrix.Translation(h) @ q @ Matrix.Translation(-h) @ W
    pb.matrix = MW.inverted() @ W2
    bpy.context.view_layer.update()


def head(bone):
    return (MW @ PB[bone].matrix).translation.copy()


def two_bone(arm, fore, hand, target, pole):
    """Аналитический IK по положениям суставов: плечо — локоть — запястье, локоть — в сторону pole."""
    s, e, w = head(arm), head(fore), head(hand)
    l1, l2 = (e - s).length, (w - e).length
    d = target - s
    dist = min(d.length, (l1 + l2) * 0.999)
    dn = d.normalized()
    a = math.acos(max(-1.0, min(1.0, (l1 * l1 + dist * dist - l2 * l2) / (2 * l1 * dist))))
    side = (pole - s)
    side = (side - dn * side.dot(dn)).normalized()
    e_new = s + (dn * math.cos(a) + side * math.sin(a)) * l1
    _rot_bone(arm, e - s, e_new - s)
    e2, w2 = head(fore), head(hand)
    _rot_bone(fore, w2 - e2, s + dn * dist - e2)


n = int(round(SECS * FPS)) + 1
poses = []
hip0 = head("Hips")
for k in range(n):
    t = k / (n - 1)
    d = draw_at(t)
    for p in PB:
        p.location, p.rotation_quaternion = base[p.name]
    bpy.context.view_layer.update()
    two_bone("RightArm", "RightForeArm", "RightHand", katana_pt(GRIP + d), hip0 + Vector((-0.6, 0.2, 0.2)))
    two_bone("LeftArm", "LeftForeArm", "LeftHand", katana_pt(SAYA), hip0 + Vector((0.6, 0.3, 0.2)))
    poses.append({p.name: p.matrix.copy() for p in PB})
    if PREVIEW and k in (0, n // 2, n - 1):
        cam = sc.camera or bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
        if sc.camera is None:
            sc.collection.objects.link(cam)
            sc.camera = cam
        cam.location = hip0 + Vector((0.3, -2.6, 0.5))
        cam.rotation_euler = (math.radians(85), 0, math.radians(5))
        sc.render.engine = "CYCLES"
        sc.cycles.samples = 8
        sc.cycles.device = "CPU"
        sc.render.resolution_x, sc.render.resolution_y = 360, 420
        if not [o for o in sc.objects if o.type == "LIGHT"]:
            L = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
            L.data.energy = 4
            L.rotation_euler = (0.6, 0.2, 0.3)
            sc.collection.objects.link(L)
        sc.render.filepath = PREVIEW.replace(".png", f"_{k}.png")
        bpy.ops.render.render(write_still=True)

for p in PB:
    for c in list(p.constraints):
        p.constraints.remove(c)
a = bpy.data.actions.new("IaiSheathe_t")
ad.action = a
for k, vis in enumerate(poses):
    for name in [b.name for b in rig.data.bones]:          # родитель раньше детей
        PB[name].matrix = vis[name]
        bpy.context.view_layer.update()
    for p in PB:
        p.keyframe_insert("rotation_quaternion", frame=k)
        if p.name == "Hips":
            p.keyframe_insert("location", frame=k)
a.use_fake_user = True
ad.action = None
final = dict(acts)
final["IaiSheathe"] = a
for name, act in final.items():
    t = ad.nla_tracks.new()
    t.name = name
    st = t.strips.new(name, int(act.frame_range[0]), act)
    if hasattr(st, "action_slot") and len(getattr(act, "slots", [])):
        st.action_slot = act.slots[0]
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animation_mode="NLA_TRACKS",
                          export_force_sampling=True, export_frame_step=1, export_yup=True,
                          export_image_format="JPEG", export_jpeg_quality=88)


def _glb(path):
    b = open(path, "rb").read()
    m = struct.unpack_from("<I", b, 12)[0]
    return json.loads(b[20:20 + m]), b[20 + m:]


src, _ = _glb(SRC)                                   # Blender сдвигает узлы мечей — вернуть TRS из исходника
dst, rest = _glb(OUT)
keep = {x["name"]: x for x in src["nodes"] if x.get("name", "").startswith("Sword_")}
for x in dst["nodes"]:
    if x.get("name") in keep:
        for k in ("translation", "rotation", "scale"):
            if k in keep[x["name"]]:
                x[k] = keep[x["name"]][k]
js = json.dumps(dst, separators=(",", ":")).encode()
js += b" " * ((4 - len(js) % 4) % 4)
body = struct.pack("<II", len(js), 0x4E4F534A) + js + rest
open(OUT, "wb").write(struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body)
print("IaiSheathe", n, "frames", flush=True)
