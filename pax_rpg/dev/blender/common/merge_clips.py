"""Добавить в glb модели клипы из анимаций Meshy (тот же риг): каждый glb анимации → действие с нашим именем.
    blender -b -P merge_clips.py -- <база.glb> <выход.glb> Имя=<анимация.glb> [Имя=<анимация.glb> ...]
Кадры 30 к/с, узлы мечей (Sword_*) сохраняют положение из базы (экспорт Blender их сдвигает).
"""
import json
import struct
import sys

import bpy

A = sys.argv[sys.argv.index("--") + 1:]
BASE, OUT, PAIRS = A[0], A[1], [p.split("=", 1) for p in A[2:]]
sc = bpy.context.scene
sc.render.fps, sc.render.fps_base = 30, 1.0
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=BASE)
sc.render.fps, sc.render.fps_base = 30, 1.0
rig = [o for o in sc.objects if o.type == "ARMATURE"][0]
keep = set(bpy.data.objects)
for name, path in PAIRS:
    before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    sc.render.fps, sc.render.fps_base = 30, 1.0
    new = [a for a in bpy.data.actions if a not in before]
    if not new:
        print("no action in", path)
        continue
    act = max(new, key=lambda a: a.frame_range[1] - a.frame_range[0])
    act.name = name
    act.use_fake_user = True
    for a in new:
        if a is not act:
            bpy.data.actions.remove(a)
    for o in list(bpy.data.objects):
        if o not in keep:
            bpy.data.objects.remove(o, do_unlink=True)
    print("clip", name, tuple(act.frame_range), flush=True)
ad = rig.animation_data or rig.animation_data_create()
ad.action = None
for tr in list(ad.nla_tracks):
    ad.nla_tracks.remove(tr)
for a in bpy.data.actions:
    base = a.name.split("_Knight")[0].split(".")[0]
    tr = ad.nla_tracks.new()
    tr.name = base
    st = tr.strips.new(base, int(a.frame_range[0]), a)
    if hasattr(st, "action_slot") and len(getattr(a, "slots", [])):
        st.action_slot = a.slots[0]
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animation_mode="NLA_TRACKS",
                          export_force_sampling=True, export_frame_step=1, export_yup=True,
                          export_image_format="AUTO")


def _glb(path):
    b = open(path, "rb").read()
    n = struct.unpack_from("<I", b, 12)[0]
    return json.loads(b[20:20 + n]), b[20 + n:]


src, _ = _glb(BASE)
dst, rest = _glb(OUT)
sw = {n["name"]: n for n in src["nodes"] if n.get("name", "").startswith("Sword_")}
for n in dst["nodes"]:
    if n.get("name") in sw:
        for k in ("translation", "rotation", "scale"):
            if k in sw[n["name"]]:
                n[k] = sw[n["name"]][k]
js = json.dumps(dst, separators=(",", ":")).encode()
js += b" " * ((4 - len(js) % 4) % 4)
body = struct.pack("<II", len(js), 0x4E4F534A) + js + rest
open(OUT, "wb").write(struct.pack("<III", 0x46546C67, 2, 12 + len(body)) + body)
print("exported", OUT, sorted(a.name for a in bpy.data.actions), flush=True)
