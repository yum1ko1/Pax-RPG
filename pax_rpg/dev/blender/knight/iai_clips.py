"""Иай (iai.gd): клипы посадки на колено и подъёма (Mixamo Kneeling Down / Standing, перенесены mixamo_retarget.py
как IaiKneel / IaiRise) обрезаются до движения, и между ними — петля IaiHold: поза на колене, дыхание, левая кисть
большим пальцем выталкивает цубу (пальцев у рига нет — движение кистью и предплечьем), голова чуть клонится.
    blender -b -P iai_clips.py -- <knight.glb с IaiKneel/IaiRise> <out.glb>
"""
import json
import math
import struct
import sys

import bpy
from mathutils import Euler

A = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = A[0], A[1]
KNEEL = (20, 56)            # кадры 30 к/с: таз уходит вниз 24…52
RISE = (0, 42)
HOLD = 60                   # кадров петли (2 с)

sc = bpy.context.scene
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=SRC)
sc.render.fps, sc.render.fps_base = 30, 1.0
rig = [o for o in sc.objects if o.type == "ARMATURE"][0]
acts = {a.name.split("_Knight")[0].split(".")[0]: a for a in bpy.data.actions}
ad = rig.animation_data or rig.animation_data_create()
for tr in list(ad.nla_tracks):
    ad.nla_tracks.remove(tr)
PB = rig.pose.bones


def sample(act, f):
    ad.action = act
    sc.frame_set(f)
    return {p.name: (p.location.copy(), p.rotation_quaternion.copy()) for p in PB}


def bake(name, poses):
    a = bpy.data.actions.new(name)
    ad.action = a
    for k, pose in enumerate(poses):
        for p in PB:
            loc, q = pose[p.name]
            p.location, p.rotation_quaternion = loc, q
            p.keyframe_insert("rotation_quaternion", frame=k)
            if p.name == "Hips":
                p.keyframe_insert("location", frame=k)
    a.use_fake_user = True
    return a


kn, ri = acts["IaiKneel"], acts["IaiRise"]
kneel = [sample(kn, f) for f in range(KNEEL[0], KNEEL[1] + 1)]
rise = [sample(ri, f) for f in range(RISE[0], RISE[1] + 1)]
base = kneel[-1]


def bump(t, a, b):          # 0 → 1 → 0 на отрезке [a, b] доли петли, гладко
    if t <= a or t >= b:
        return 0.0
    return math.sin(math.pi * (t - a) / (b - a)) ** 2


hold = []
for k in range(HOLD):
    t = k / HOLD
    pose = {n: (l.copy(), q.copy()) for n, (l, q) in base.items()}
    breath = math.sin(math.tau * t)
    push = bump(t, 0.12, 0.62)                       # большой палец давит на цубу — кисть подгибается и отпускает
    off = {
        "Spine01": Euler((math.radians(1.2 * breath), 0, 0)),
        "Spine": Euler((math.radians(0.8 * breath), 0, 0)),
        "neck": Euler((math.radians(-0.6 * breath), 0, 0)),
        "Head": Euler((math.radians(1.5 * push), math.radians(-1.0 * push), 0)),
        "LeftHand": Euler((math.radians(-9.0 * push), 0, math.radians(4.0 * push))),
        "LeftForeArm": Euler((math.radians(3.0 * push), 0, 0)),
        "RightHand": Euler((math.radians(2.0 * breath), 0, 0)),
    }
    for n, e in off.items():
        if n in pose:
            l, q = pose[n]
            pose[n] = (l, q @ e.to_quaternion())
    hold.append(pose)

new = {"IaiKneel": bake("IaiKneel_t", kneel), "IaiHold": bake("IaiHold_t", hold), "IaiRise": bake("IaiRise_t", rise)}
ad.action = None
final = {}
for n, a in acts.items():
    final[n] = a
final.update(new)
for name, a in final.items():
    tr = ad.nla_tracks.new()
    tr.name = name
    st = tr.strips.new(name, int(a.frame_range[0]), a)
    if hasattr(st, "action_slot") and len(getattr(a, "slots", [])):
        st.action_slot = a.slots[0]
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animation_mode="NLA_TRACKS",
                          export_force_sampling=True, export_frame_step=1, export_yup=True,
                          export_image_format="JPEG", export_jpeg_quality=88)


def _glb(path):
    b = open(path, "rb").read()
    n = struct.unpack_from("<I", b, 12)[0]
    return json.loads(b[20:20 + n]), b[20 + n:]


src, _ = _glb(SRC)                                   # Blender сдвигает узлы мечей — вернуть TRS из исходника
dst, rest = _glb(OUT)
keep = {n["name"]: n for n in src["nodes"] if n.get("name", "").startswith("Sword_")}
for n in dst["nodes"]:
    if n.get("name") in keep:
        for k in ("translation", "rotation", "scale"):
            if k in keep[n["name"]]:
                n[k] = keep[n["name"]][k]
js = json.dumps(dst, separators=(",", ":")).encode()
js += b" " * ((4 - len(js) % 4) % 4)
body = struct.pack("<II", len(js), 0x4E4F534A) + js + rest
open(OUT, "wb").write(struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body)
print("iai clips", {n: len(p) for n, p in (("IaiKneel", kneel), ("IaiHold", hold), ("IaiRise", rise))}, flush=True)
