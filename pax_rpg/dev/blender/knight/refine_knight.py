"""Второй этап Чёрного рыцаря — после assemble_knight.py (сцена Knight уже собрана).

Через мост: exec(open(<файл>).read(), {"result": {}}). Делает:
  - IdleArmed — стойка с мечом (первый кадр Attack1 + дыхание), к ней плавно возвращаются удары;
  - RunArmed — бег (клип Run), правая рука опущена назад, меч (Sword_Drag) волочится остриём по земле;
  - Draw / Sheathe заново, своим IK: рука тянется за правое плечо к рукояти, берёт меч, вытаскивает его дугой над
    головой и опускает в стойку; Sheathe — то же назад. Меч на спине ставится ровно туда, где его берёт рука;
  - меч не уходит в землю: в ударах кисть поворачивается так, чтобы остриё оставалось над землёй; кадр, где
    остриё ниже всего в Attack3, — удар о землю (звук);
  - плащ: цепочки костей Cape_<i>_<j> за спиной, вершины плаща (по цвету текстуры) перевешены на них —
    в игре их качает SpringBoneSimulator3D;
  - экспорт <W>/knight/knight.glb и knight_anim.json.
Оси Blender: Z вверх, рыцарь смотрит на -Y, правая рука — -X. Арматура Meshy в сантиметрах (масштаб объекта 0,01):
все цели считаются в мире (метры), позы ставятся через pose_bone.matrix.
"""
import json
import math
import os

import bmesh  # noqa: F401  (на будущее: правка сетки плаща)
import bpy
import numpy as np
from mathutils import Matrix, Quaternion, Vector

W = r"C:\Users\mbkli\Desktop\pax_rpg_work\meshy"
OUT = os.path.join(W, "knight")
FPS = 30
try:
    result
except NameError:
    result = {}
log = result.setdefault("log", [])

win = bpy.context.window or bpy.context.window_manager.windows[0]
scn = bpy.data.scenes["Knight"]
win.scene = scn
vl = scn.view_layers[0]
rig = bpy.data.objects["Knight_rig"]
pb = rig.pose.bones
MW = rig.matrix_world.copy()
MWi = MW.inverted()
body = [o for o in scn.objects if o.type == "MESH" and o.name.startswith("Knight_body")]
meta_path = os.path.join(OUT, "knight_anim.json")
meta = json.load(open(meta_path, encoding="utf-8"))
clips = {a.name[2:]: a for a in bpy.data.actions if a.name.startswith("K_")}
UA, FA, HA = "RightArm", "RightForeArm", "RightHand"
CHEST, HIPS = "Spine02", "Hips"
UP, FWD, RIGHT = Vector((0, 0, 1)), Vector((0, -1, 0)), Vector((-1, 0, 0))
BLADE_LEN = 1.72                         # от хвата до острия (build_greatsword.py: G0 + L)


# ---------- позы ----------
def use(action):
    rig.animation_data_create()
    rig.animation_data.action = action
    if action is not None and hasattr(rig.animation_data, "action_slot") and len(action.slots):
        rig.animation_data.action_slot = action.slots[0]


def capture(action, f):
    use(action)
    scn.frame_set(int(f))
    return {p.name: (p.location.copy(), p.rotation_quaternion.copy()) for p in pb}


def apply(pose):
    use(None)
    for p in pb:
        loc, q = pose[p.name]
        p.location = loc
        p.rotation_quaternion = q
    vl.update()


def blend(a, b, t):
    out = {}
    for n in a:
        qa, qb = a[n][1], b[n][1]
        if qa.dot(qb) < 0:
            qb = -qb
        out[n] = (a[n][0].lerp(b[n][0], t), qa.slerp(qb, t))
    return out


def current():
    return {p.name: (p.location.copy(), p.rotation_quaternion.copy()) for p in pb}


_prev = {}


def new_action(name):
    old = bpy.data.actions.get("K_" + name)
    if old is not None:
        bpy.data.actions.remove(old)
    a = bpy.data.actions.new("K_" + name)
    a.use_fake_user = True
    clips[name] = a
    _prev.clear()
    return a


def key(action, f):
    """Записать текущую позу всех костей в кадр f (действие цепляется только на время записи)."""
    rig.animation_data.action = action
    if len(action.slots) and hasattr(rig.animation_data, "action_slot"):
        rig.animation_data.action_slot = action.slots[0]
    for p in pb:
        q = p.rotation_quaternion
        if p.name in _prev and _prev[p.name].dot(q) < 0:
            p.rotation_quaternion = -q
        _prev[p.name] = p.rotation_quaternion.copy()
        p.keyframe_insert("rotation_quaternion", frame=f)
        p.keyframe_insert("location", frame=f)
    rig.animation_data.action = None


def head(b):
    return MW @ pb[b].head


def rot_w(b):
    return (MW @ pb[b].matrix).to_3x3().normalized()


def turn_bone(b, q):
    """Повернуть кость в мире на q вокруг её головы (масштаб арматуры равномерный — поворот тот же)."""
    h = pb[b].head.copy()
    pb[b].matrix = Matrix.Translation(h) @ q.to_matrix().to_4x4() @ Matrix.Translation(-h) @ pb[b].matrix
    vl.update()


def set_rot_w(b, R):
    h = pb[b].head.copy()
    pb[b].matrix = Matrix.Translation(h) @ R.to_4x4()
    vl.update()


# ---------- IK правой руки (по головам костей: длины костей Meshy негодные) ----------
use(None)
for p in pb:
    p.rotation_quaternion = (1, 0, 0, 0)
    p.location = (0, 0, 0)
vl.update()
L1 = (head(FA) - head(UA)).length
L2 = (head(HA) - head(FA)).length


def ik_arm(Wt, pole):
    S = head(UA)
    v = Wt - S
    d = min(v.length, L1 + L2 - 0.002)
    u = v.normalized()
    a = (L1 * L1 - L2 * L2 + d * d) / (2 * d)
    h = math.sqrt(max(0.0, L1 * L1 - a * a))
    pv = pole - u * pole.dot(u)
    pv.normalize()
    E = S + u * a + pv * h
    turn_bone(UA, (head(FA) - S).rotation_difference(E - S))
    turn_bone(FA, (head(HA) - head(FA)).rotation_difference(S + u * d - head(FA)))


def facing():
    """Вперёд по тазу (горизонталь)."""
    v = rot_w(HIPS) @ HIPS_FWD
    v.z = 0
    return v.normalized()


HIPS_FWD = rot_w(HIPS).inverted() @ FWD


# ---------- меч в руке: смещение относительно кисти ----------
sw_hand = bpy.data.objects["Sword_Hand"]


def sword_frame(ob):
    M = ob.matrix_world
    return M.translation.copy(), M.to_3x3().normalized()


def measure_offset(ob, bone=HA):
    o, R = sword_frame(ob)
    Rh = rot_w(bone)
    return Rh.transposed() @ R, Rh.transposed() @ (o - head(bone))


R_OFF, T_OFF = measure_offset(sw_hand)


def frame3(ydir, zhint):
    y = ydir.normalized()
    z = (zhint - y * zhint.dot(y)).normalized()
    x = y.cross(z)
    return Matrix((x, y, z)).transposed()


def hand_for(R_sword, origin):
    """Поворот и точка запястья, при которых меч в руке встаёт в R_sword / origin."""
    Rh = R_sword @ R_OFF.transposed()
    return Rh, origin - Rh @ T_OFF


def attach(name, bone, Mworld):
    old = bpy.data.objects.get(name)
    me = old.data if old else sw_hand.data
    if old is not None:
        bpy.data.objects.remove(old, do_unlink=True)
    ob = bpy.data.objects.new(name, me)
    scn.collection.objects.link(ob)
    ob.parent = rig
    ob.parent_type = "BONE"
    ob.parent_bone = bone
    vl.update()
    Mb = MW @ pb[bone].matrix @ Matrix.Translation((0, rig.data.bones[bone].length, 0))
    ob.matrix_parent_inverse = Matrix.Identity(4)
    ob.matrix_basis = Mb.inverted() @ Mworld
    vl.update()
    return ob


# ---------- 1. стойка с мечом ----------
a1 = clips["Attack1"]
P_GUARD = capture(a1, a1.frame_range[0])
P_IDLE = capture(clips["Idle"], clips["Idle"].frame_range[0])
act = new_action("IdleArmed")
for f in range(0, 61, 6):
    pose = dict(P_GUARD)
    apply(pose)
    s = math.sin(2 * math.pi * f / 60)
    turn_bone(CHEST, Quaternion(rot_w(CHEST) @ Vector((1, 0, 0)), math.radians(1.5 * s)))
    key(act, f)

# ---------- 2. бег с мечом: рука вниз-назад, меч волочится ----------
run = clips["Run"]
f0, f1 = int(run.frame_range[0]), int(run.frame_range[1])
act = new_action("RunArmed")
drag_made = False
for f in range(f0, f1 + 1):
    pose = capture(run, f)
    apply(pose)
    fw = facing()
    side = fw.cross(UP)                   # вправо от бега
    turn_bone("Spine01", Quaternion(side, math.radians(-8)))        # наклон вперёд — тяжело
    sh = head(UA)
    bob = 0.03 * math.sin(2 * math.pi * (f - f0) / max(1, f1 - f0) * 2)
    ik_arm(sh - fw * 0.30 + side * 0.10 - UP * (0.60 + bob), -fw * 0.4 + side * 0.6)
    if not drag_made:                     # меч волочится: остриё на земле позади
        grip = head(HA) + rot_w(HA) @ T_OFF
        dz = 0.05 - grip.z
        hz = math.sqrt(max(0.01, BLADE_LEN ** 2 - dz * dz))
        tip = grip - fw * hz
        tip.z = 0.05
        Rs = frame3(tip - grip, side)
        Md = Rs.to_4x4()
        Md.translation = grip
        attach("Sword_Drag", HA, Md)
        drag_made = True
    key(act, f)

# ---------- 3. новые Draw / Sheathe ----------
apply(P_IDLE)
fw = facing()
side = fw.cross(UP)
c = head(CHEST)
back_grip = c + side * 0.17 - fw * 0.20 + UP * 0.36           # рукоять над правым плечом (side — вправо), за спиной
back_dir = (-side * 0.40 - fw * 0.06 - UP * 0.91).normalized()  # клинок к левому бедру
# ориентация хвата у плеча: крен меча вокруг клинка — какой удобнее запястью
apply(P_GUARD)
a_fwd = rot_w(HA).transposed() @ (head(HA) - head(FA)).normalized()
apply(P_IDLE)
pole_grab = (UP * 0.7 + side * 0.5 + fw * 0.4).normalized()
best = None
for k in range(36):
    R0 = frame3(back_dir, -fw)
    Rf = R0 @ Matrix.Rotation(math.radians(k * 10), 3, "Y")
    Rh, Wt = hand_for(Rf, back_grip)
    apply(P_IDLE)
    ik_arm(Wt, pole_grab)
    bend = math.degrees((Rh @ a_fwd).angle(head(HA) - head(FA)))
    miss = (head(HA) - Wt).length
    score = bend + miss * 500
    if best is None or score < best[0]:
        best = (score, Rf, Rh, Wt, bend, miss)
_, RF_BACK, RH_GRAB, W_GRAB, bend, miss = best
log.append(f"grab: wrist bend {round(bend)}°, reach miss {round(miss * 100, 1)} cm")
apply(P_IDLE)
ik_arm(W_GRAB, pole_grab)
set_rot_w(HA, RH_GRAB)
P_GRAB = current()
Mback = RF_BACK.to_4x4()
Mback.translation = back_grip
sw_back = attach("Sword_Back", CHEST, Mback)
# над головой: меч вытащен вверх-назад
apply(P_IDLE)
up_dir = (UP * 0.9 - fw * 0.30 - side * 0.15).normalized()
Rh_up, W_up = hand_for(frame3(up_dir, side), head(UA) + UP * 0.40 - fw * 0.02 - side * 0.04)
ik_arm(W_up, (UP * 0.2 + side * 0.9).normalized())
set_rot_w(HA, Rh_up)
P_UP = current()
# на полпути к рукояти
apply(P_IDLE)
W_half = head(UA) + UP * 0.22 + fw * 0.12 - side * 0.05
ik_arm(W_half, pole_grab)
P_HALF = current()


def lean(pose, deg, hips_drop=0.0):
    apply(pose)
    if deg:
        turn_bone("Spine01", Quaternion(facing().cross(UP), math.radians(-deg)))
    if hips_drop:
        pb[HIPS].matrix = MWi @ Matrix.Translation(-UP * hips_drop) @ MW @ pb[HIPS].matrix
        vl.update()
    return current()


DRAW_KEYS = [  # кадр, поза
    (0, P_IDLE),
    (8, P_HALF),
    (13, P_GRAB),
    (17, lean(P_GRAB, -4, 0.03)),            # рывок — меч тяжёлый
    (25, lean(P_UP, -6)),
    (31, lean(P_GUARD, 8, 0.06)),            # меч опускается — вес тянет вниз
    (40, P_GUARD),
]
GRAB_F, DRAW_LEN = 13, 40
act = new_action("Draw")
for f, pose in DRAW_KEYS:
    apply(pose)
    key(act, f)
act = new_action("Sheathe")
for f, pose in reversed(DRAW_KEYS):
    apply(pose)
    key(act, DRAW_LEN - f)
meta["sword_switch"] = {"Draw": {"frame": GRAB_F, "time": round(GRAB_F / FPS, 3)},
                        "Sheathe": {"frame": DRAW_LEN - GRAB_F, "time": round((DRAW_LEN - GRAB_F) / FPS, 3)}}
for n in ("Draw", "Sheathe", "Jump"):
    meta["root_motion"].pop(n, None)

# ---------- 4. меч не уходит в землю; удар о землю ----------
def tip_and_grip(ob):
    o, R = sword_frame(ob)
    return o + R @ Vector((0, BLADE_LEN, 0)), o, R


impact = {}
for name, ob, mode in (("Attack1", sw_hand, "floor"), ("Attack2", sw_hand, "floor"), ("Attack3", sw_hand, "floor"),
                       ("Draw", sw_hand, "floor"), ("Sheathe", sw_hand, "floor"),
                       ("RunArmed", bpy.data.objects["Sword_Drag"], "pin")):
    a = clips[name]
    fr = range(int(a.frame_range[0]), int(a.frame_range[1]) + 1)
    _prev.clear()
    lowest = None
    fixed = 0
    for f in fr:
        pose = capture(a, f)
        apply(pose)
        tip, o, R = tip_and_grip(ob)
        if lowest is None or tip.z < lowest[1]:
            lowest = (f, tip.z)
        want = 0.04
        changed = False
        if (mode == "floor" and tip.z < want) or mode == "pin":
            v = (tip - o).normalized()
            vz = max(-0.999, min(0.999, (want - o.z) / BLADE_LEN))
            hz = math.sqrt(1 - vz * vz)
            hv = Vector((v.x, v.y, 0))
            if hv.length < 1e-4:
                hv = facing()
            hv.normalize()
            v2 = hv * hz + UP * vz
            q = v.rotation_difference(v2)
            if q.angle > 1e-3:
                turn_bone(HA, q)
                changed = True
        if changed:
            key(a, f)
            fixed += 1
    impact[name] = round((lowest[0] - fr[0]) / FPS, 3)
    log.append(f"{name}: tip lowest {round(lowest[1], 2)} m at {impact[name]} s, fixed frames {fixed}")
meta["impact"] = {"Attack3": impact["Attack3"]}

# ---------- 5. плащ: кости и веса ----------
ob = body[0]
me = ob.data
img = None
for m in me.materials:
    if m and m.use_nodes:
        for n in m.node_tree.nodes:
            if n.type == "TEX_IMAGE" and n.image and "normal" not in n.image.name.lower():
                lk = [l for l in m.node_tree.links if l.from_node == n and l.to_socket.name == "Base Color"]
                if lk:
                    img = n.image
CHAINS_X = (-0.30, -0.15, 0.0, 0.15, 0.30)
Z_TOP, Z_BOT, SEG = 1.38, 0.18, 4
cape_ids = []
infl = None
if img is not None:
    w_, h_ = img.size
    px = np.empty(w_ * h_ * 4, dtype=np.float32)
    img.pixels.foreach_get(px)
    px = px.reshape(h_, w_, 4)
    uv = me.uv_layers.active.data
    vuv = np.zeros((len(me.vertices), 2), dtype=np.float32)
    for poly in me.polygons:
        for li in poly.loop_indices:
            vuv[me.loops[li].vertex_index] = uv[li].uv
    xs = np.clip((vuv[:, 0] % 1.0) * (w_ - 1), 0, w_ - 1).astype(int)
    ys = np.clip((vuv[:, 1] % 1.0) * (h_ - 1), 0, h_ - 1).astype(int)
    col = px[ys, xs, :3]
    co = np.array([tuple(ob.matrix_world @ v.co) for v in me.vertices])
    strict = (col[:, 2] > col[:, 1] * 1.25) & (col[:, 2] > 0.06) & (col[:, 0] > col[:, 1] * 1.05)
    loose = (col[:, 2] > col[:, 1] * 1.08) & (col[:, 2] > 0.03)
    chest_y = float((MW @ pb[CHEST].head).y)
    # плащ — связная область: от явно фиолетовых вершин растём по рёбрам в «похоже фиолетовые»
    ev = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", ev)
    ev = ev.reshape(-1, 2)
    nb = [[] for _ in range(len(me.vertices))]
    for a_, b_ in ev:
        nb[a_].append(b_)
        nb[b_].append(a_)
    ok = (co[:, 2] < 1.55) & (co[:, 1] > chest_y - 0.12)
    region = np.zeros(len(co), dtype=bool)
    stack = [int(v) for v in np.flatnonzero(strict & ok)]
    region[stack] = True
    while stack:
        v = stack.pop()
        for u in nb[v]:
            if not region[u] and ok[u] and (loose[u] or strict[u]):
                region[u] = True
                stack.append(u)
    # рваный подол: тёмные лоскуты по краю — добрать 4 кольцами соседей внизу, где плащ (за ногами и по бокам)
    hem = ok & (co[:, 2] < 0.75)
    for _ in range(4):
        add = np.zeros(len(co), dtype=bool)
        add[ev[:, 0]] |= region[ev[:, 1]]
        add[ev[:, 1]] |= region[ev[:, 0]]
        region |= add & hem
    # влияние плаща: рампа сверху, затем сглаживание по соседям — без резких швов (иначе — «иглы»)
    infl = region * np.clip((Z_TOP - co[:, 2]) / 0.28, 0, 1)
    deg = np.bincount(ev.ravel(), minlength=len(co)).astype(np.float64)
    for _ in range(8):
        acc = infl.astype(np.float64).copy()
        np.add.at(acc, ev[:, 0], infl[ev[:, 1]])
        np.add.at(acc, ev[:, 1], infl[ev[:, 0]])
        infl = acc / (1 + deg)
    infl = np.clip(infl * 1.15, 0, 1)
    cape_mask = infl > 0.02
    cape_ids = np.flatnonzero(cape_mask)
log.append(f"cape vertices {len(cape_ids)} of {len(me.vertices)}")

cape_bones = []
if len(cape_ids) > 200:
    cc = co[np.flatnonzero(infl > 0.5)]
    zs = [Z_TOP - (Z_TOP - Z_BOT) * j / SEG for j in range(SEG + 1)]
    bpy.context.view_layer.objects.active = rig
    use(None)
    bpy.ops.object.mode_set(mode="EDIT")
    eb = rig.data.edit_bones
    for nm in [b.name for b in eb if b.name.startswith("Cape_")]:
        eb.remove(eb[nm])
    for i, x in enumerate(CHAINS_X):
        pts = []
        for z in zs:
            sel = cc[(np.abs(cc[:, 0] - x) < 0.09) & (np.abs(cc[:, 2] - z) < 0.09)]
            y = float(np.percentile(sel[:, 1], 70)) if len(sel) else 0.12
            pts.append(MWi @ Vector((x, y, z)))
        par = eb[CHEST]
        for j in range(SEG):
            b = eb.new(f"Cape_{i}_{j}")
            b.head, b.tail = pts[j], pts[j + 1]
            b.parent = par
            b.use_connect = j > 0
            par = b
            cape_bones.append(b.name)
    bpy.ops.object.mode_set(mode="OBJECT")
    # веса: две ближние цепочки по X, вдоль цепочки — по высоте; верх плавно остаётся на старых весах
    for nm in cape_bones:
        if nm not in ob.vertex_groups:
            ob.vertex_groups.new(name=nm)
    groups = {g.index: g for g in ob.vertex_groups}
    for vid in (int(v) for v in cape_ids):
        x, y, z = (float(c) for c in co[vid])
        t = float(infl[vid])
        if t <= 0:
            continue
        v = me.vertices[vid]
        for g in v.groups:
            if not groups[g.group].name.startswith("Cape_"):
                groups[g.group].add([vid], g.weight * (1 - t), "REPLACE")
        fx = float(np.clip(np.interp(x, CHAINS_X, range(len(CHAINS_X))), 0, len(CHAINS_X) - 1))
        fz = float(np.clip((Z_TOP - z) / (Z_TOP - Z_BOT) * SEG - 0.5, 0, SEG - 1))
        for ci, wx in ((int(fx), 1 - (fx - int(fx))), (min(int(fx) + 1, len(CHAINS_X) - 1), fx - int(fx))):
            for sj, wz in ((int(fz), 1 - (fz - int(fz))), (min(int(fz) + 1, SEG - 1), fz - int(fz))):
                w = t * wx * wz
                if w > 1e-3:
                    g = ob.vertex_groups[f"Cape_{ci}_{sj}"]
                    g.add([vid], w, "ADD")
    meta["cape"] = {"chains": [[f"Cape_{i}_0", f"Cape_{i}_{SEG - 1}"] for i in range(len(CHAINS_X))]}
log.append(f"cape bones {len(cape_bones)}")

# ---------- экспорт ----------
for img2 in bpy.data.images:
    if img2.size[0] > 2048 and img2.users:
        img2.scale(2048, 2048 * img2.size[1] // img2.size[0])
ad = rig.animation_data
for tr in list(ad.nla_tracks):
    ad.nla_tracks.remove(tr)
for name, a in clips.items():
    tr = ad.nla_tracks.new()
    tr.name = name
    st = tr.strips.new(name, int(a.frame_range[0]), a)
    if hasattr(st, "action_slot") and len(a.slots):
        st.action_slot = a.slots[0]
use(None)
scn.frame_set(0)
path = os.path.join(OUT, "knight.glb")
bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_active_scene=True,
                          export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_frame_step=1,
                          export_yup=True, export_image_format="JPEG", export_jpeg_quality=88)
for tr in list(ad.nla_tracks):
    ad.nla_tracks.remove(tr)
use(clips["IdleArmed"])
meta["clips"] = {n: {"length": round((a.frame_range[1] - a.frame_range[0]) / FPS, 3)} for n, a in clips.items()}
json.dump(meta, open(meta_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT, "knight.blend"), copy=True)
result.update(glb_mb=round(os.path.getsize(path) / 1e6, 1), impact=meta.get("impact"), switch=meta["sword_switch"],
              clips=sorted(clips))
