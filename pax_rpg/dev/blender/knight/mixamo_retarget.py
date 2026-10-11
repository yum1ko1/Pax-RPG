"""Анимации Mixamo (FBX, скелет mixamorig) → риг Чёрного рыцаря (Meshy): подменить клипы в knight.glb мода.
Перенос: поворот каждой кости относительно её позы покоя — в мировых осях (так разница поз покоя T/A и осей костей
не важна), таз — смещение от покоя, масштаб по высоте таза. Циклы ходьбы — на месте (горизонтальный уход вынут,
игра двигает героя сама), 60 → 30 к/с. mirror — зеркально (левый стрейф из правого).
    blender -b -P mixamo_retarget.py -- <knight.glb> <папка fbx> <out.glb> [кадры-превью-папка]
Клипы — CLIPS ниже. Мечи и плащ glb не трогаются (меч — ребёнок кости руки).
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

A = sys.argv[sys.argv.index("--") + 1:]
KNIGHT, FBX, OUT = A[0], A[1], A[2]
PREVIEW = A[3] if len(A) > 3 else ""
FPS = 30
# клип рыцаря: (файл fbx, зеркально, на месте)
CLIPS = {
    "Walk": ("Swagger_Walk.fbx", False, True),
    "Run": ("Fast_Run.fbx", False, True),
    "WalkArmed": ("Great_Sword_Walk.fbx", False, True),
    "GuardBack": ("Great_Sword_Walk_1.fbx", False, True),
    "GuardStrafeR": ("Great_Sword_Strafe.fbx", False, True),
    "GuardStrafeL": ("Great_Sword_Strafe.fbx", True, True),
    "WalkBack": ("Walking_Backwards.fbx", False, True),
    "HeavySlash": ("Great_Sword_Slash.fbx", False, False),
    "Turn180Armed": ("Great_Sword_180_Turn.fbx", False, False),
}
MAP = {"Hips": "Hips", "Spine": "Spine02", "Spine1": "Spine01", "Spine2": "Spine", "Neck": "neck", "Head": "Head",
       "LeftShoulder": "LeftShoulder", "LeftArm": "LeftArm", "LeftForeArm": "LeftForeArm", "LeftHand": "LeftHand",
       "RightShoulder": "RightShoulder", "RightArm": "RightArm", "RightForeArm": "RightForeArm", "RightHand": "RightHand",
       "LeftUpLeg": "LeftUpLeg", "LeftLeg": "LeftLeg", "LeftFoot": "LeftFoot", "LeftToeBase": "LeftToeBase",
       "RightUpLeg": "RightUpLeg", "RightLeg": "RightLeg", "RightFoot": "RightFoot", "RightToeBase": "RightToeBase"}
MX = Matrix.Diagonal((-1.0, 1.0, 1.0)).to_3x3()        # зеркало по X (в мире Blender)


def swap(n):
    return n.replace("Left", "#").replace("Right", "Left").replace("#", "Right")


sc = bpy.context.scene
sc.render.fps = FPS
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=KNIGHT)
rig = [o for o in sc.objects if o.type == "ARMATURE"][0]
MW = rig.matrix_world.copy()
acts = {a.name: a for a in bpy.data.actions}
print("knight actions:", sorted(acts), flush=True)


def act_for(clip):
    for n, a in acts.items():
        if n == clip or n.startswith(clip + "_") or n.startswith(clip + "."):
            return a
    return None


rig.animation_data_create()
rig.animation_data.action = None
for p in rig.pose.bones:
    p.matrix_basis = Matrix.Identity(4)
bpy.context.view_layer.update()
T_REST = {b.name: (MW @ b.matrix_local) for b in rig.data.bones}
order = [b.name for b in rig.data.bones]                 # родитель раньше детей
tgt_names = set(order)
hips_rest_t = T_REST["Hips"].translation.copy()

made = {}
for clip, (fname, mirror, inplace) in CLIPS.items():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=os.path.join(FBX, fname))
    new = [o for o in bpy.data.objects if o not in before]
    src = [o for o in new if o.type == "ARMATURE"][0]
    sact = src.animation_data.action
    f0, f1 = int(sact.frame_range[0]), int(sact.frame_range[1])
    SW = src.matrix_world.copy()
    pre = "mixamorig:"
    src.animation_data.action = None
    saved = {p.name: p.matrix_basis.copy() for p in src.pose.bones}
    for p in src.pose.bones:
        p.matrix_basis = Matrix.Identity(4)
    bpy.context.view_layer.update()
    S_REST = {b.name: (SW @ b.matrix_local) for b in src.data.bones}
    src.animation_data.action = sact
    hips_rest_s = S_REST[pre + "Hips"].translation.copy()
    ratio = hips_rest_t.z / max(hips_rest_s.z, 1e-3)
    act = bpy.data.actions.new(clip + "_mx")
    rig.animation_data.action = act
    if hasattr(rig.animation_data, "action_slot") and len(getattr(act, "slots", [])):
        rig.animation_data.action_slot = act.slots[0]
    n_out = int((f1 - f0) / 2) + 1
    first_h = None
    last_h = None
    for k in range(n_out):
        fs = f0 + k * 2
        sc.frame_set(fs)
        spose = {p.name: (SW @ p.matrix) for p in src.pose.bones}
        for tn in order:
            sn = None
            for mk, mv in MAP.items():
                if mv == tn:
                    sn = pre + (swap(mk) if mirror else mk)
            if sn is None or sn not in spose:
                continue
            ds = spose[sn].to_3x3().normalized() @ S_REST[sn].to_3x3().normalized().inverted()
            if mirror:
                ds = MX @ ds @ MX
            # покой рыцаря (A-поза) ≠ покой Mixamo (T-поза): сначала кость рыцаря — в направление кости-источника
            # в покое (минимальный поворот), потом — тот же поворот от покоя, что у источника
            sdir = (S_REST[sn].to_3x3().normalized() @ Vector((0, 1, 0)))
            if mirror:
                sdir = MX @ sdir
            tdir = T_REST[tn].to_3x3().normalized() @ Vector((0, 1, 0))
            corr = tdir.rotation_difference(sdir).to_matrix()
            rot = ds @ corr @ T_REST[tn].to_3x3().normalized()
            pbt = rig.pose.bones[tn]
            cur = (MW @ pbt.matrix)
            M = (rot @ Matrix.Diagonal(T_REST[tn].to_scale())).to_4x4()   # масштаб кости (риг Meshy — в см)
            if tn == "Hips":
                dpos = (spose[sn].translation - hips_rest_s) * ratio
                if mirror:
                    dpos.x = -dpos.x
                if first_h is None:
                    first_h = dpos.copy()
                last_h = dpos.copy()
                if inplace:
                    dpos.x, dpos.y = 0.0, 0.0              # уход вперёд/вбок — игра двигает сама
                M.translation = hips_rest_t + dpos
            else:
                M.translation = cur.translation
            pbt.matrix = MW.inverted() @ M
            bpy.context.view_layer.update()
        for tn in order:
            p = rig.pose.bones[tn]
            p.keyframe_insert("rotation_quaternion", frame=k)
            if tn == "Hips":
                p.keyframe_insert("location", frame=k)
    act.use_fake_user = True
    made[clip] = (act, n_out)
    trav = (last_h - first_h).xy.length if first_h is not None else 0.0
    print(f"{clip}: {fname} {f0}-{f1} → {n_out} frames, путь за цикл {trav:.2f} м ({trav / max((n_out - 1) / FPS, 1e-3):.2f} м/с)", flush=True)
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.actions.remove(sact)

# превью: кадры клипов (рыцарь сбоку) — проверить глазами
if PREVIEW:
    os.makedirs(PREVIEW, exist_ok=True)
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.render.resolution_x, sc.render.resolution_y = 260, 340
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.6
    for clip, (act, n) in made.items():
        rig.animation_data.action = act
        for i in range(6):
            sc.frame_set(round((n - 1) * i / 5))
            cam.location = Vector((3.5, -1.2, 1.0))
            cam.rotation_euler = (math.radians(88), 0, math.radians(70))
            sc.render.filepath = os.path.join(PREVIEW, f"{clip}_{i}.png")
            bpy.ops.render.render(write_still=True)

# подмена клипов и экспорт (NLA: дорожка на клип)
ad = rig.animation_data
ad.action = None
for tr in list(ad.nla_tracks):
    ad.nla_tracks.remove(tr)
final = {}
for n, a in acts.items():
    base = n.split("_Knight")[0].split(".")[0]
    final[base] = a
for clip, (a, _) in made.items():
    final[clip] = a
for name, a in final.items():
    tr = ad.nla_tracks.new()
    tr.name = name
    st = tr.strips.new(name, int(a.frame_range[0]), a)
    if hasattr(st, "action_slot") and len(getattr(a, "slots", [])):
        st.action_slot = a.slots[0]
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animation_mode="NLA_TRACKS",
                          export_force_sampling=True, export_frame_step=1, export_yup=True,
                          export_image_format="JPEG", export_jpeg_quality=88)
json.dump({c: round((n - 1) / FPS, 3) for c, (_, n) in made.items()},
          open(os.path.splitext(OUT)[0] + "_mixamo.json", "w"))
print("exported", OUT, sorted(final), flush=True)
