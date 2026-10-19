"""Новые жители Гхарна (модели Tripo с ригом Mixamo) → glb для игры: куски сетки склеены в одну, рост в метрах,
материал из карт рядом с FBX (базовый цвет, нормали, шероховатость, металл), клипы гоблина-жителя (walk, idle)
перенесены на их скелет — мировой разницей поворотов от покоя (как bl_tl2.py), таз — по высоте бёдер, на месте.
    blender -b -P npc_variant.py -- <модель.fbx> <папка карт> <рост м> <goblin walk.glb> <goblin idle.glb> <out.glb>
"""
import bpy, sys, os, math
from mathutils import Vector, Matrix

a = sys.argv[sys.argv.index("--") + 1:]
FBX, TEX, HEIGHT, WALK, IDLE, OUT = a[0], a[1], float(a[2]), a[3], a[4], a[5]
FPS = 30
MAP = {"Hips": "Hips", "Spine02": "Spine", "Spine01": "Spine1", "Spine": "Spine2", "neck": "Neck", "Head": "Head"}
for s in ("Left", "Right"):
    for b in ("Shoulder", "Arm", "ForeArm", "Hand", "UpLeg", "Leg", "Foot", "ToeBase"):
        MAP[s + b] = s + b

bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene
scn.render.fps = FPS
bpy.ops.import_scene.fbx(filepath=FBX, automatic_bone_orientation=False)
tgt = next(o for o in bpy.data.objects if o.type == "ARMATURE")
meshes = [o for o in bpy.data.objects if o.type == "MESH"]
pre = "mixamorig:" if any(b.name.startswith("mixamorig:") for b in tgt.data.bones) else ""

# --- куски — в одну сетку
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "body"

# --- материал из карт рядом с FBX
files = os.listdir(TEX)
def pick(key):
    return next((os.path.join(TEX, f) for f in files if key in f.lower()), None)
m = bpy.data.materials.new("skin")
m.use_nodes = True
nt = m.node_tree
bs = nt.nodes["Principled BSDF"]
def img(path, nonc=False):
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = bpy.data.images.load(path)
    if nonc:
        n.image.colorspace_settings.name = "Non-Color"
    return n
if pick("basecolor"):
    nt.links.new(img(pick("basecolor")).outputs["Color"], bs.inputs["Base Color"])
if pick("roughness"):
    nt.links.new(img(pick("roughness"), True).outputs["Color"], bs.inputs["Roughness"])
if pick("metallic"):
    nt.links.new(img(pick("metallic"), True).outputs["Color"], bs.inputs["Metallic"])
if pick("normal"):
    nm = nt.nodes.new("ShaderNodeNormalMap")
    nt.links.new(img(pick("normal"), True).outputs["Color"], nm.inputs["Color"])
    nt.links.new(nm.outputs["Normal"], bs.inputs["Normal"])
body.data.materials.clear()
body.data.materials.append(m)

# --- рост: масштаб всей арматуры (с сеткой) и применить
bpy.context.view_layer.update()
zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
k = HEIGHT / (max(zs) - min(zs))
tgt.scale = tgt.scale * k
bpy.context.view_layer.update()
bpy.ops.object.select_all(action="DESELECT")
tgt.select_set(True); body.select_set(True)
bpy.context.view_layer.objects.active = tgt
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
bpy.context.view_layer.update()
zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
print("NPCV height", round(max(zs) - min(zs), 2), "verts", len(body.data.vertices))

# --- перенос клипов гоблина
if tgt.animation_data is None:
    tgt.animation_data_create()
ad = tgt.animation_data
for x in list(bpy.data.actions):
    bpy.data.actions.remove(x)
TW = tgt.matrix_world.copy(); TWi = TW.inverted()
for p in tgt.pose.bones:
    p.rotation_mode = "QUATERNION"
def rot(M): return M.to_3x3().normalized().to_quaternion()
names = {b.name[len(pre):]: b.name for b in tgt.data.bones}
t_rest = {n: rot(TW @ tgt.data.bones[full].matrix_local) for n, full in names.items()}
t_hips = TW @ tgt.data.bones[names["Hips"]].head_local
t_floor = min((TW @ tgt.data.bones[names[n]].head_local).z for n in ("LeftToeBase", "RightToeBase"))
order = [b.name for b in tgt.data.bones]


def retarget(path, name):
    before = set(bpy.data.objects); acts = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    src = next(o for o in new if o.type == "ARMATURE")
    sact = next(x for x in bpy.data.actions if x not in acts)
    src.animation_data.action = sact
    if hasattr(src.animation_data, "action_slot") and len(getattr(sact, "slots", [])):
        src.animation_data.action_slot = sact.slots[0]
    SW = src.matrix_world.copy()
    s_rest = {sn: rot(SW @ src.data.bones[sn].matrix_local) for sn in MAP if sn in src.data.bones}
    s_hips = SW @ src.data.bones["Hips"].head_local
    s_floor = min((SW @ src.data.bones[n].head_local).z for n in ("LeftToeBase", "RightToeBase"))
    ratio = (t_hips.z - t_floor) / max(1e-4, s_hips.z - s_floor)
    f0, f1 = int(round(sact.frame_range[0])), int(round(sact.frame_range[1]))
    act = bpy.data.actions.new(name)
    ad.action = act
    for k, f in enumerate(range(f0, f1 + 1)):
        scn.frame_set(f); bpy.context.view_layer.update()
        hp = SW @ src.pose.bones["Hips"].head
        hz = t_floor + (hp.z - s_floor) * ratio
        for full in order:
            short = full[len(pre):]
            sn = next((s for s, t in MAP.items() if t == short), None)
            if sn is None or sn not in s_rest:
                continue
            if any(k in short for k in ("Arm", "Hand", "Shoulder", "Leg", "Foot", "ToeBase")):
                # руки и ноги — по направлению кости гоблина в кадре (позы покоя у ригов разные: A и T)
                sd = (SW.to_3x3() @ src.pose.bones[sn].matrix.to_3x3()).col[1].normalized()
                td = (TW.to_3x3() @ tgt.data.bones[full].matrix_local.to_3x3()).col[1].normalized()
                q = td.rotation_difference(sd) @ t_rest[short]
            else:
                q = rot(SW @ src.pose.bones[sn].matrix) @ s_rest[sn].inverted() @ t_rest[short]
            pb = tgt.pose.bones[full]
            loc = (TW @ pb.matrix).translation
            if short == "Hips":
                loc = Vector((t_hips.x, t_hips.y, hz))           # на месте: ход ведёт игра
            pb.matrix = TWi @ Matrix.LocRotScale(loc, q, None)
            bpy.context.view_layer.update()
            pb.keyframe_insert("rotation_quaternion", frame=k)
            if short == "Hips":
                pb.keyframe_insert("location", frame=k)
    for o in new:
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.actions.remove(sact)
    print("NPCV clip", name, f1 - f0 + 1, "frames, ratio", round(ratio, 3))
    return act


retarget(WALK, "walk")
retarget(IDLE, "idle")
ad.action = None
for p in tgt.pose.bones:
    p.rotation_quaternion = (1, 0, 0, 0); p.location = (0, 0, 0)
for x in sorted(bpy.data.actions, key=lambda x: x.name):
    tr = ad.nla_tracks.new(); tr.name = x.name
    st = tr.strips.new(x.name, int(x.frame_range[0]), x)
    if hasattr(st, "action_slot") and len(getattr(x, "slots", [])):
        st.action_slot = x.slots[0]
scn.frame_set(0)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_animation_mode="NLA_TRACKS", export_force_sampling=True,
                          export_frame_step=1, export_yup=True, export_image_format="JPEG", export_jpeg_quality=90)
print("NPCV ok", OUT)
