"""Сборка Чёрного рыцаря из выгрузок Meshy в один glb для мода.

Через мост: exec(open(<файл>).read(), {"result": {}}). Берёт из <W>/meshy:
    knight_rig/rigged_character_glb_url.glb             — модель со скелетом Meshy
    knight_rig/basic_animations.{walking,running}_glb_url.glb — ходьба, бег
    anim_{Draw,Sheathe,Attack1,Attack2,Attack3}/animation_glb_url.glb — Text to Motion на этом скелете
    anim_Library/animation_glb_url.glb                  — Idle, Regular Jump, Walk Fight Forward (библиотека)
    greatsword.glb                                      — меч (build_greatsword.py)
Пишет <W>/knight/knight.glb (рыцарь, два меча — на спине и в руке, клипы) и knight_anim.json:
    root motion клипов (смещение тела вынуто из анимации: игра двигает персонажа сама — инерция ударов),
    кадры, когда рука берёт меч со спины (Draw) и отпускает его (Sheathe).
Оси Blender: Z вверх, рыцарь смотрит на -Y. В json смещения — в осях Godot для модели (x, z), модель смотрит на +Z.
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

W = r"C:\Users\mbkli\Desktop\pax_rpg_work\meshy"
OUT = os.path.join(W, "knight")
FPS = 30
TEX = 2048                 # текстуры ужимаются до 2K: glb в 3-4 раза легче
try:
    result
except NameError:
    result = {}
log = result.setdefault("log", [])

if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
win = bpy.context.window or bpy.context.window_manager.windows[0]


def fresh_scene(name):
    old = bpy.data.scenes.get(name)
    if old is not None:
        for o in list(old.objects):
            bpy.data.objects.remove(o, do_unlink=True)
        bpy.data.scenes.remove(old)
    s = bpy.data.scenes.new(name)
    s.render.fps = FPS
    win.scene = s
    return s


def use(ob, action):
    ob.animation_data_create()
    ob.animation_data.action = action
    if hasattr(ob.animation_data, "action_slot") and len(getattr(action, "slots", [])):
        ob.animation_data.action_slot = action.slots[0]


def import_glb(path, scene_name):
    """Импорт во временную сцену → (объекты, новые действия)."""
    s = fresh_scene(scene_name)
    before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=path)
    return list(s.objects), [a for a in bpy.data.actions if a not in before]


def drop_scene(s):
    for o in list(s.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.scenes.remove(s)


# ---------- рыцарь ----------
for a in [a for a in bpy.data.actions if a.name.startswith("K_")]:
    bpy.data.actions.remove(a)
objs, acts = import_glb(os.path.join(W, "knight_rig", "rigged_character_glb_url.glb"), "Knight")
scn = win.scene
for a in acts:
    bpy.data.actions.remove(a)
rig = next(o for o in objs if o.type == "ARMATURE")
rig.name = "Knight_rig"
body = [o for o in objs if o.type == "MESH" and (o.parent == rig or any(m.type == "ARMATURE" for m in o.modifiers))]
for o in [o for o in objs if o.type == "MESH" and o not in body]:
    bpy.data.objects.remove(o, do_unlink=True)          # посторонние сетки в файле (вспомогательные сферы и т. п.)
body.sort(key=lambda o: -len(o.data.vertices))
for i, o in enumerate(body):
    o.name = "Knight_body" if i == 0 else f"Knight_body_{i}"
bones = [b.name for b in rig.data.bones]
log.append(f"bones {len(bones)}: {bones[:40]}")


def find_bone(*keys, avoid=()):
    for k in keys:
        for b in bones:
            n = b.lower().replace("_", "").replace(":", "")
            if k in n and not any(x in n for x in avoid):
                return b
    return None


HIPS = find_bone("hips", "pelvis") or rig.data.bones[0].name
RHAND = find_bone("righthand", "handr", "rhand", avoid=("thumb", "index", "middle", "ring", "pinky", "finger"))
LHAND = find_bone("lefthand", "handl", "lhand", avoid=("thumb", "index", "middle", "ring", "pinky", "finger"))
CHEST = find_bone("spine02", "spine2", "chest", "upperchest", "spine01", "spine1")
log.append(f"hips={HIPS} rhand={RHAND} lhand={LHAND} chest={CHEST}")

# ---------- клипы ----------
SOURCES = [
    ("Walk", "knight_rig/basic_animations.walking_glb_url.glb", None),
    ("Run", "knight_rig/basic_animations.running_glb_url.glb", None),
    ("Draw", "anim_Draw/animation_glb_url.glb", None),
    ("Sheathe", "anim_Sheathe/animation_glb_url.glb", None),
    ("Attack1", "anim_Attack1/animation_glb_url.glb", None),
    ("Attack2", "anim_Attack2/animation_glb_url.glb", None),
    ("Attack3", "anim_Attack3/animation_glb_url.glb", None),
    ("Idle", "anim_Library/animation_glb_url.glb", "idle"),
    ("Jump", "anim_Library/animation_glb_url.glb", "jump"),
    ("WalkArmed", "anim_Library/animation_glb_url.glb", "walk"),
    ("Dodge", "anim_Dodge/animation_glb_url.glb", "roll_dodge"),          # библиотека Meshy 158 (риг 2)
    ("DodgeArmed", "anim_Dodge/animation_glb_url.glb", "roll_dodge_2"),   # 160; руки с мечом — refine_knight.py
    ("Hurt", "anim_Hurt/animation_glb_url.glb", None),                    # 171 Hit Reaction to Waist — получил удар
]
clips = {}
cache = {}
for name, rel, pick in SOURCES:
    if rel not in cache:
        o2, a2 = import_glb(os.path.join(W, rel), "K_tmp")
        cache[rel] = a2
        drop_scene(win.scene)
    acts = cache[rel]
    if pick:
        cand = sorted([a for a in acts if pick in a.name.lower()], key=lambda a: len(a.name))   # точнее — короче
    else:
        cand = sorted(acts, key=lambda a: a.frame_range[1] - a.frame_range[0], reverse=True)
    if not cand:
        log.append(f"!! no clip for {name} in {rel}: {[a.name for a in acts]}")
        continue
    a = cand[0]
    a = a.copy()
    a.name = "K_" + name
    a.use_fake_user = True
    clips[name] = a
for acts in cache.values():
    for a in acts:
        if a.users == 0 or not a.name.startswith("K_"):
            try:
                bpy.data.actions.remove(a)
            except ReferenceError:
                pass
win.scene = scn
log.append("clips " + ", ".join(f"{n}:{int(a.frame_range[0])}-{int(a.frame_range[1])}" for n, a in clips.items()))

pb = rig.pose.bones
MW = rig.matrix_world


def world(bone, f=None):
    if f is not None:
        scn.frame_set(f)
    return MW @ pb[bone].matrix


def frames(a):
    return range(int(a.frame_range[0]), int(a.frame_range[1]) + 1)


# ---------- root motion: смещение таза по горизонтали — в json, клип — на месте ----------
ROOT_CLIPS = ("Draw", "Sheathe", "Attack1", "Attack2", "Attack3", "Jump", "Dodge", "DodgeArmed")
INPLACE = ("Walk", "Run", "WalkArmed", "Idle")
motion = {}
for name, a in clips.items():
    use(rig, a)
    fr = list(frames(a))
    pos = [world(HIPS, f).translation.copy() for f in fr]
    p0 = pos[0]
    total = pos[-1] - p0
    if name in INPLACE:
        drift = [(pos[i] - p0) for i in range(len(fr))]          # циклы: убрать уход вперёд целиком
    elif name in ROOT_CLIPS:
        drift = [(pos[i] - p0) for i in range(len(fr))]
    else:
        continue
    curve = []
    for i, f in enumerate(fr):
        d = drift[i]
        scn.frame_set(f)
        M = MW @ pb[HIPS].matrix
        M.translation = Vector((M.translation.x - d.x, M.translation.y - d.y, M.translation.z))
        pb[HIPS].matrix = MW.inverted() @ M
        pb[HIPS].keyframe_insert("location", frame=f)
        # Blender (x, y, z) → Godot (x, z, -y): вперёд у модели — -Y Blender = +Z Godot
        curve.append([round(d.x, 4), round(-d.y, 4)])
    if name in ROOT_CLIPS:
        motion[name] = {"fps": FPS, "frames": len(fr), "offset": curve}
    log.append(f"{name}: hips moved {round(total.length, 2)} m")

# ---------- меч: на спине и в руке ----------
so, sa = import_glb(os.path.join(W, "greatsword.glb"), "K_tmp")
src = next(o for o in so if o.type == "MESH")
sword_me = src.data
drop_scene(win.scene)
win.scene = scn


def frame_m(origin, ydir, zhint):
    y = ydir.normalized()
    z = (zhint - y * zhint.dot(y)).normalized()
    x = y.cross(z)
    M = Matrix((x, y, z)).transposed().to_4x4()
    M.translation = origin
    return M


FOREARM = {RHAND: find_bone("rightforearm"), LHAND: find_bone("leftforearm")}


def grip_point(bone, f=None):
    """Середина кулака: продолжение предплечья за запястье на 8 см (длины костей Meshy для этого не годятся)."""
    w = world(bone, f).translation
    e = (MW @ pb[FOREARM[bone]].matrix).translation
    return w + (w - e).normalized() * 0.08


def facing(f):
    """Куда смотрит таз на кадре f (горизонталь); в покое рыцарь смотрит на -Y."""
    Mh = (MW @ pb[HIPS].matrix).to_3x3().normalized()
    v = Mh @ HIPS_FWD
    v.z = 0
    return v.normalized()


def attach(name, bone, Mworld):
    ob = bpy.data.objects.new(name, sword_me)
    scn.collection.objects.link(ob)
    ob.parent = rig
    ob.parent_type = "BONE"
    ob.parent_bone = bone
    scn.frame_set(scn.frame_current)
    # мировая матрица ребёнка кости = MW @ bone.matrix @ Translation(0, длина, 0) @ matrix_parent_inverse @ basis
    Mb = MW @ pb[bone].matrix @ Matrix.Translation((0, rig.data.bones[bone].length, 0))
    ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.matrix_basis = Mb.inverted() @ Mworld
    return ob


# покой (без действия): спина — рукоять над правым плечом, клинок к левому бедру, плоскостью к спине
rig.animation_data.action = None
for p in pb:
    p.rotation_quaternion = (1, 0, 0, 0)
    p.location = (0, 0, 0)
    p.rotation_euler = (0, 0, 0)
bpy.context.view_layer.update()
Mc = world(CHEST)
HIPS_FWD = (MW @ pb[HIPS].matrix).to_3x3().normalized().inverted() @ Vector((0, -1, 0))
height = max((o.matrix_world @ v.co).z for o in body for v in o.data.vertices) if body else 1.9
c = Mc.translation
back_grip = Vector((c.x - 0.20, c.y + 0.24, c.z + 0.30))
back_dir = Vector((0.38, 0.06, -0.92))
sword_back = attach("Sword_Back", CHEST, frame_m(back_grip, back_dir, Vector((0, 1, 0))))

# в руке: последний кадр Draw — стойка, клинок вперёд-вверх от правого кулака
use(rig, clips["Draw"])
f_end = int(clips["Draw"].frame_range[1])
R, L = grip_point(RHAND, f_end), grip_point(LHAND, f_end)
fw = facing(f_end)
blade = (fw + Vector((0, 0, 0.75))).normalized()
side = blade.cross(Vector((0, 0, 1))).normalized()
hand_M = frame_m(R, blade, side)                    # плоскость клинка — вбок, кромка — вниз, к врагу
sword_hand = attach("Sword_Hand", RHAND, hand_M)
log.append(f"hands at guard: R {tuple(round(x, 2) for x in R)} L {tuple(round(x, 2) for x in L)} dist {round((R - L).length, 2)}")

# когда рука у рукояти на спине: Draw — взять, Sheathe — отпустить
switch = {}
for name in ("Draw", "Sheathe"):
    a = clips[name]
    use(rig, a)
    best = None
    for f in frames(a):
        d = (grip_point(RHAND, f) - (MW @ pb[CHEST].matrix @ Matrix.Translation((0, rig.data.bones[CHEST].length, 0))
                                     @ sword_back.matrix_basis).translation).length
        if best is None or d < best[1]:
            best = (f, d)
    switch[name] = {"frame": best[0] - int(a.frame_range[0]), "time": round((best[0] - a.frame_range[0]) / FPS, 3),
                    "hand_to_hilt_m": round(best[1], 3)}
log.append(f"switch {switch}")

# ---------- текстуры 2K, экспорт ----------
for img in bpy.data.images:
    if img.size[0] > TEX and img.users:
        img.scale(TEX, TEX * img.size[1] // img.size[0])
ad = rig.animation_data
for tr in list(ad.nla_tracks):
    ad.nla_tracks.remove(tr)
for name, a in clips.items():
    tr = ad.nla_tracks.new()
    tr.name = name
    st = tr.strips.new(name, int(a.frame_range[0]), a)
    if hasattr(st, "action_slot") and len(getattr(a, "slots", [])):
        st.action_slot = a.slots[0]
ad.action = None
scn.frame_set(0)
os.makedirs(OUT, exist_ok=True)
path = os.path.join(OUT, "knight.glb")
bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_active_scene=True,
                          export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_frame_step=1,
                          export_yup=True, export_image_format="JPEG", export_jpeg_quality=88)
for tr in list(ad.nla_tracks):
    ad.nla_tracks.remove(tr)
use(rig, clips["Idle"] if "Idle" in clips else next(iter(clips.values())))
meta = {"_note": "Чёрный рыцарь: root motion клипов (x, z в осях модели Godot, модель смотрит на +Z; метры от начала клипа)"
                 " и смена меча спина ↔ рука.", "fps": FPS, "height": round(height, 2),
        "clips": {n: {"length": round((a.frame_range[1] - a.frame_range[0]) / FPS, 3)} for n, a in clips.items()},
        "root_motion": motion, "sword_switch": switch}
json.dump(meta, open(os.path.join(OUT, "knight_anim.json"), "w", encoding="utf-8"), ensure_ascii=False, indent=1)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "knight.blend"), copy=True)
result.update(glb_mb=round(os.path.getsize(path) / 1e6, 1), height=round(height, 2), switch=switch,
              root={n: m["offset"][-1] for n, m in motion.items()})
