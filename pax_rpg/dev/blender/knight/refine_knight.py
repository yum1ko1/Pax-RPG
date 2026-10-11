"""Второй этап Чёрного рыцаря — после assemble_knight.py (сцена Knight уже собрана).

Через мост: exec(open(<файл>).read(), {"result": {}}). Делает:
  - IdleArmed — стойка с мечом (первый кадр Attack1 + дыхание), к ней плавно возвращаются удары;
  - RunArmed — бег (клип Run), правая рука опущена назад, меч (Sword_Drag) волочится остриём по земле;
  - Draw / Sheathe: меч висит открыто на зажиме (плашмя к спине, наискось), его снимают рывком с крюка и
    перекатывают через правое плечо, левая рука ловит рукоять — см. раздел 3; путь задан для меча, руки — IK;
  - меч не уходит в землю: в ударах кисть поворачивается так, чтобы остриё оставалось над землёй; кадр, где
    остриё ниже всего в Attack3, — удар о землю (звук);
  - плащ снимается с модели: вершины плаща (по цвету текстуры) отрезаются и выбрасываются — плащ теперь
    отдельный предмет, его строит build_cape.py;
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
# Тяжёлый меч не мотается за плечом: направление бега одно на весь цикл (таз в беге виляет — по нему рука
# ходила бы из стороны в сторону), рука следует за плечом лишь на треть его тряски, кисть держит меч
# в одном повороте — меч плывёт за рыцарем, а не дёргается.
fw, side = FWD.copy(), FWD.cross(UP)
shs = []
for f in range(f0, f1 + 1):
    apply(capture(run, f))
    turn_bone("Spine01", Quaternion(side, math.radians(-8)))
    shs.append(head(UA))
sh_mean = sum(shs, Vector()) / len(shs)
RH_RUN = None
for f in range(f0, f1 + 1):
    pose = capture(run, f)
    apply(pose)
    turn_bone("Spine01", Quaternion(side, math.radians(-8)))        # наклон вперёд — тяжело
    sh = sh_mean + (head(UA) - sh_mean) * 0.35
    ik_arm(sh - fw * 0.30 + side * 0.10 - UP * 0.60, -fw * 0.4 + side * 0.6)
    if RH_RUN is None:
        RH_RUN = rot_w(HA)
    set_rot_w(HA, RH_RUN)
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

# ---------- 3. Draw / Sheathe: как на самом деле снимают со спины меч в рост человека ----------
# Двуручник 2,2 м из ножен за спиной не вытянуть — руки не хватит. Поэтому он висит открыто, на зажиме-крюке:
# рукоять над правым плечом, клинок наискось к левому бедру, плашмя к спине. Достаём:
#   1) правая рука через плечо берёт рукоять (локоть вверх);
#   2) рывок вверх-назад — клинок снимается с крюка и отходит от спины;
#   3) меч перекатывается через правое плечо: рукоять идёт вперёд над плечом, остриё описывает дугу за спиной
#      и встаёт вверх — клинок ни разу не тянется вдоль себя;
#   4) с высоты над головой меч падает вперёд-вниз, левая рука ловит рукоять у навершия, вес приседает рыцаря,
#      и оба выходят в стойку.
# Убираем — тот же путь назад, медленнее у крюка: меч поднимается над головой, переваливается через плечо,
# остриё уходит вниз за спину, рукоять ложится на зажим, рука отпускает.
# Путь задан для самого меча (точка хвата + направление клинка + поворот плашмя); руки догоняют его IK.
LUA, LFA, LHA = "LeftArm", "LeftForeArm", "LeftHand"
use(None)
for p in pb:
    p.rotation_quaternion = (1, 0, 0, 0)
    p.location = (0, 0, 0)
vl.update()
LL1 = (head(LFA) - head(LUA)).length
LL2 = (head(LHA) - head(LFA)).length


def ik_left(Wt, pole):
    S = head(LUA)
    v = Wt - S
    d = min(v.length, LL1 + LL2 - 0.002)
    u = v.normalized()
    a = (LL1 * LL1 - LL2 * LL2 + d * d) / (2 * d)
    h = math.sqrt(max(0.0, LL1 * LL1 - a * a))
    pv = (pole - u * pole.dot(u)).normalized()
    E = S + u * a + pv * h
    turn_bone(LUA, (head(LFA) - S).rotation_difference(E - S))
    turn_bone(LFA, (head(LHA) - head(LFA)).rotation_difference(S + u * d - head(LFA)))


def elbow_pole(ua, fa, ha):
    s_, e_, w_ = head(ua), head(fa), head(ha)
    m = (s_ + w_) / 2
    return (e_ - m).normalized()


apply(P_IDLE)
fw = facing()
side = fw.cross(UP)                       # вправо
c = head(CHEST)
sh_r = head(UA)
# зажим на спине: рукоять над правым плечом, чуть отступив от спины; клинок к левому бедру
back_grip = c + side * 0.16 - fw * 0.24 + UP * 0.34
back_dir = (-side * 0.42 - UP * 0.90 - fw * 0.04).normalized()
# стойка: где меч и левая рука в ней
apply(P_GUARD)
O_G, R_G = sword_frame(sw_hand)
L_REL = R_G.transposed() @ (head(LHA) - O_G)
LR_REL = R_G.transposed() @ rot_w(LHA)
POLE_G = elbow_pole(UA, FA, HA)
POLE_GL = elbow_pole(LUA, LFA, LHA)
apply(P_IDLE)
POLE_IL = elbow_pole(LUA, LFA, LHA)


def sframe(d, zhint):
    return frame3(d, zhint).to_quaternion()


# ключи пути меча: (u — доля пути, точка хвата, поворот меча, полюс локтя правой руки)
Z_BACK = -fw                               # плашмя к спине (нормаль плашки — назад от спины)
q_back = sframe(back_dir, Z_BACK)
q_guard = R_G.to_quaternion()
KEYS = [
    (0.00, back_grip, q_back, UP * 0.6 + side * 0.6 + fw * 0.3),
    (0.14, back_grip + UP * 0.12 - fw * 0.10 + side * 0.05,                          # рывок с крюка
     sframe((back_dir - fw * 0.35).normalized(), Z_BACK), UP * 0.6 + side * 0.6 + fw * 0.3),
    (0.38, sh_r + UP * 0.28 - fw * 0.02 + side * 0.04,                                # над плечом, остриё назад
     sframe((-fw * 0.85 + UP * 0.35 - side * 0.25).normalized(), side), UP * 0.4 + side * 0.9),
    (0.58, sh_r + UP * 0.45 + fw * 0.16 - side * 0.14,                                # над головой, остриё вверх
     sframe((UP * 0.80 - fw * 0.55 - side * 0.10).normalized(), side), side * 0.9 + fw * 0.2),
    (0.80, O_G + UP * -0.06 + fw * 0.06,                                              # упал вперёд — вес тянет
     (Quaternion(side, math.radians(-14)) @ q_guard), POLE_G),
    (1.00, O_G, q_guard, POLE_G),
]
# плашка не перекручивается: знак нормали у каждого ключа — ближе к следующему (стойка задана)
for i in range(len(KEYS) - 2, -1, -1):
    u_, o_, q_, p_ = KEYS[i]
    flip = q_ @ Quaternion(Vector((0, 1, 0)), math.pi)
    nxt = KEYS[i + 1][2]
    if abs(flip.dot(nxt)) > abs(q_.dot(nxt)):
        KEYS[i] = (u_, o_, flip, p_)
q_back = KEYS[0][2]


def catmull(p0, p1, p2, p3, t):
    t2, t3 = t * t, t * t * t
    return 0.5 * (2 * p1 + (p2 - p0) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (3 * p1 - p0 - 3 * p2 + p3) * t3)


def path(u):
    """Меч на доле пути u: точка хвата, поворот, полюс локтя."""
    for i in range(len(KEYS) - 1):
        if u <= KEYS[i + 1][0] or i == len(KEYS) - 2:
            break
    u0, u1 = KEYS[i][0], KEYS[i + 1][0]
    t = min(1.0, max(0.0, (u - u0) / (u1 - u0)))
    P = [KEYS[max(0, min(len(KEYS) - 1, j))][1] for j in (i - 1, i, i + 1, i + 2)]
    o = catmull(*P, t)
    qa, qb = KEYS[i][2], KEYS[i + 1][2]
    if qa.dot(qb) < 0:
        qb = -qb
    pole = KEYS[i][3].lerp(KEYS[i + 1][3], t)
    return o, qa.slerp(qb, t), pole


def smooth(x):
    x = min(1.0, max(0.0, x))
    return x * x * (3 - 2 * x)


GRAB_F, DRAW_LEN = 13, 54                 # кадр хвата; конец доставания
apply(P_IDLE)
RH_GRAB, W_GRAB = hand_for(q_back.to_matrix(), back_grip)
ik_arm(W_GRAB, KEYS[0][3])
set_rot_w(HA, RH_GRAB)
log.append(f"grab: reach miss {round((head(HA) - W_GRAB).length * 100, 1)} cm")
P_GRAB = current()
Mback = q_back.to_matrix().to_4x4()
Mback.translation = back_grip
sw_back = attach("Sword_Back", CHEST, Mback)
# рука тянется к рукояти: кисть перед плечом, выше — не сквозь голову и наплечник
apply(P_IDLE)
ik_arm(sh_r + UP * 0.30 + fw * 0.16 + side * 0.10, UP * 0.3 + side * 0.9)
P_HALF = current()


def draw_pose(f):
    """Поза доставания на кадре f (0..DRAW_LEN)."""
    if f <= GRAB_F:
        t = f / GRAB_F
        pose = blend(P_IDLE, P_HALF, smooth(t / 0.55)) if t < 0.55 else blend(P_HALF, P_GRAB, smooth((t - 0.55) / 0.45))
        apply(pose)
        return
    u = (f - GRAB_F) / (DRAW_LEN - GRAB_F)
    u = u * u * (3 - 2 * u) * 0.6 + u * 0.4     # мягкий старт с крюка и тяжёлая посадка, середина — дуга
    base = blend(P_IDLE, P_GUARD, smooth((u - 0.35) / 0.55))
    apply(base)
    # корпус: рывок назад на снятии, наклон вперёд, когда меч падает, и присед от веса
    if u < 0.3:
        lean = -5 * math.sin(math.pi * u / 0.3)
    elif u < 0.5:
        lean = 0.0
    else:
        lean = 10 * math.sin(math.pi * (u - 0.5) / 0.5)
    turn_bone("Spine01", Quaternion(side, math.radians(-lean)))
    drop = 0.08 * math.sin(math.pi * min(1, max(0, (u - 0.62) / 0.38)))
    if drop:
        pb[HIPS].matrix = MWi @ Matrix.Translation(-UP * drop) @ MW @ pb[HIPS].matrix
        vl.update()
    o, q, pole = path(u)
    Rh, Wt = hand_for(q.to_matrix(), o)
    ik_arm(Wt, pole)
    set_rot_w(HA, Rh)
    # левая рука: ловит рукоять, когда меч пошёл вниз (u 0.55..0.75), дальше держит у навершия
    k = smooth((u - 0.55) / 0.2)
    if k > 0:
        R = q.to_matrix()
        lw = o + R @ L_REL
        idle_l = head(LHA)
        ik_left(idle_l.lerp(lw, k), POLE_IL.lerp(POLE_GL, k).normalized())
        if k > 0.5:
            set_rot_w(LHA, R @ LR_REL)


act = new_action("Draw")
for f in range(0, DRAW_LEN + 1):
    if f <= GRAB_F and f not in (0, 5, 9, GRAB_F):
        continue                          # тянущаяся рука — по ключам, Blender сгладит
    draw_pose(f)
    key(act, f)
# Убрать: путь назад, у крюка медленнее (меч надо попасть рукоятью в зажим)
SH_MAP = [(0, DRAW_LEN), (11, 41), (26, 26), (38, GRAB_F + 2), (45, GRAB_F), (58, 0)]
SHEATHE_LEN = SH_MAP[-1][0]
act = new_action("Sheathe")
for s_f in range(0, SHEATHE_LEN + 1):
    for j in range(len(SH_MAP) - 1):
        if s_f <= SH_MAP[j + 1][0]:
            break
    (a0, d0), (a1, d1) = SH_MAP[j], SH_MAP[j + 1]
    df = d0 + (d1 - d0) * (s_f - a0) / (a1 - a0)
    if df < GRAB_F and s_f % 3:
        continue
    draw_pose(df)
    key(act, s_f)
REL_F = SH_MAP[-2][0]                     # кадр, где рука отпускает меч на зажиме
meta["sword_switch"] = {"Draw": {"frame": GRAB_F, "time": round(GRAB_F / FPS, 3)},
                        "Sheathe": {"frame": REL_F, "time": round(REL_F / FPS, 3)}}
for n in ("Draw", "Sheathe", "Jump"):
    meta["root_motion"].pop(n, None)

# На ходу: ноги и таз — из шага (Walk по кругу), всё выше пояса — из доставания. Рука берёт меч относительно
# груди, а меч на спине висит на груди — хват совпадает и при шаге.
LEGS = {HIPS} | {f"{s_}{b_}" for s_ in ("Left", "Right") for b_ in ("UpLeg", "Leg", "Foot", "ToeBase")}
walk = clips["Walk"]
w0, w1 = int(walk.frame_range[0]), int(walk.frame_range[1])
for src in ("Draw", "Sheathe"):
    a = clips[src]
    s0, s1 = int(a.frame_range[0]), int(a.frame_range[1])
    act = new_action(src + "Walk")
    for f in range(s0, s1 + 1):
        up_ = capture(a, f)
        lg = capture(walk, w0 + (f - s0) % max(1, w1 - w0))
        apply({n: (lg[n] if n in LEGS else up_[n]) for n in up_})
        key(act, f - s0)

# ---------- 3б. уворот с мечом: кувырок, правая рука прижимает меч к боку клинком назад (как в беге) ----------
RARM = ("RightShoulder", UA, FA, HA)
P_CARRY = capture(clips["RunArmed"], clips["RunArmed"].frame_range[0])
da = clips["DodgeArmed"]
d0, d1 = int(da.frame_range[0]), int(da.frame_range[1])
src = da.copy()
act = new_action("DodgeArmed")
for f in range(d0, d1 + 1):
    pose = capture(src, f)
    pose.update({n: P_CARRY[n] for n in RARM})
    apply(pose)
    key(act, f - d0)
bpy.data.actions.remove(src)
# ---------- 4. меч не уходит в землю; удар о землю ----------
def tip_and_grip(ob):
    o, R = sword_frame(ob)
    return o + R @ Vector((0, BLADE_LEN, 0)), o, R


impact = {}
for name, ob, mode in (("Attack1", sw_hand, "floor"), ("Attack2", sw_hand, "floor"), ("Attack3", sw_hand, "floor"),
                       ("Draw", sw_hand, "floor"), ("Sheathe", sw_hand, "floor"),
                       ("DrawWalk", sw_hand, "floor"), ("SheatheWalk", sw_hand, "floor"),
                       ("DodgeArmed", sw_hand, "floor"),
                       ("RunArmed", bpy.data.objects["Sword_Drag"], "pin")):
    a = clips[name]
    fr = range(int(a.frame_range[0]), int(a.frame_range[1]) + 1)
    _prev.clear()
    lowest = None
    fixed = 0
    tips = {}
    for f in fr:
        pose = capture(a, f)
        apply(pose)
        tip, o, R = tip_and_grip(ob)
        tips[f] = tip.z
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
    # удар о землю — первый кадр касания перед самой низкой точкой (а не сама низшая точка: она позже)
    touch = lowest[0]
    while touch - 1 in tips and tips[touch - 1] < 0.12:
        touch -= 1
    impact[name] = round((touch - fr[0]) / FPS, 3)
    log.append(f"{name}: tip lowest {round(lowest[1], 2)} m at {impact[name]} s, fixed frames {fixed}")
meta["impact"] = {"Attack3": impact["Attack3"]}

# ---------- 5. плащ: какие вершины — плащ ----------
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
    # спина ниже плеч и весь ворот капюшона вокруг шеи (он тоже ткань плаща, спереди тоже)
    ok = (co[:, 2] < 1.85) & ((co[:, 1] > chest_y - 0.12) | (co[:, 2] > 1.35))
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
    # подол до самых сапог: за серединой ног (сзади) и ниже колен — 9 колец
    hips_y = float((MW @ pb[HIPS].head).y)
    hem = ok & (co[:, 2] < 0.8) & (co[:, 1] > hips_y - 0.03)
    for _ in range(6):
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

# Плащ снимается с тела: грани, где влияние плаща больше трети, отрезаются в объект Knight_cape и убираются из сцены.
CAPE_TARGET, PIN_BAND = 900, 0.08
if len(cape_ids) > 200:
    face_in = np.zeros(len(me.polygons), dtype=bool)
    for poly in me.polygons:
        vs = list(poly.vertices)
        face_in[poly.index] = float(np.mean(infl[vs])) > 0.35 or float(np.mean(region[vs])) > 0.5
    old_cape = bpy.data.objects.get("Knight_cape")
    if old_cape is not None:
        bpy.data.objects.remove(old_cape, do_unlink=True)
    for o in vl.objects:
        o.select_set(False)
    vl.objects.active = ob
    ob.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_mode(type="FACE")
    bpy.ops.mesh.select_all(action="DESELECT")
    bpy.ops.object.mode_set(mode="OBJECT")
    me.polygons.foreach_set("select", face_in.tolist())
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    cape = [o for o in vl.objects if o.select_get() and o != ob][0]
    cape.name = "Knight_cape"
    log.append(f"cape removed from the body: {len(cape.data.vertices)} verts")
    bpy.data.objects.remove(cape, do_unlink=True)   # плащ с модели снят: плащ — отдельный предмет (build_cape.py)
meta.pop("cape", None)

# Горжет — латный ворот от плеч до шлема: под срезанным плащом и воротом капюшона у модели Meshy пусто (одна оболочка),
# горжет закрывает шею и рваный край на плечах. Кольца эллипсов (z, полуоси x / y, сдвиг по y), низ едет с грудью
# (Spine), верх — с шеей (neck).
GORGET = [(1.39, 0.29, 0.20, -0.05), (1.44, 0.24, 0.17, -0.06), (1.50, 0.17, 0.14, -0.07),
          (1.56, 0.125, 0.12, -0.08), (1.635, 0.112, 0.112, -0.08)]
use(None)
for p_ in pb:
    p_.rotation_quaternion = (1, 0, 0, 0)
    p_.location = (0, 0, 0)
vl.update()
old = bpy.data.objects.get("Knight_gorget")
if old is not None:
    bpy.data.objects.remove(old, do_unlink=True)
SEGS = 36
gv, gf = [], []
nx0 = head("neck").x
for z, rx, ry, dy in GORGET:
    for k in range(SEGS):
        a_ = 2 * math.pi * k / SEGS
        gv.append((nx0 + rx * math.cos(a_), head("neck").y + dy + 0.0 + ry * math.sin(a_), z))
for r in range(len(GORGET) - 1):
    for k in range(SEGS):
        k2 = (k + 1) % SEGS
        gf.append((r * SEGS + k, r * SEGS + k2, (r + 1) * SEGS + k2, (r + 1) * SEGS + k))
gme = bpy.data.meshes.new("Knight_gorget")
gme.from_pydata(gv, [], gf)
gme.update()
gme.shade_smooth()
gob = bpy.data.objects.new("Knight_gorget", gme)
scn.collection.objects.link(gob)
gmat = bpy.data.materials.get("Gorget") or bpy.data.materials.new("Gorget")
gmat.use_nodes = True
gmat.use_backface_culling = False
gb = next(n for n in gmat.node_tree.nodes if n.type == "BSDF_PRINCIPLED")
gb.inputs["Base Color"].default_value = (0.018, 0.018, 0.022, 1.0)
gb.inputs["Metallic"].default_value = 0.85
gb.inputs["Roughness"].default_value = 0.42
gme.materials.append(gmat)
g_lo, g_hi = gob.vertex_groups.new(name="Spine"), gob.vertex_groups.new(name="neck")
for r, (z, *_x) in enumerate(GORGET):
    t = r / (len(GORGET) - 1)
    ids = list(range(r * SEGS, (r + 1) * SEGS))
    g_lo.add(ids, 1 - t, "REPLACE")
    g_hi.add(ids, t, "REPLACE")
gob.parent = rig
gob.matrix_parent_inverse = rig.matrix_world.inverted()
mod_ = gob.modifiers.new("Armature", "ARMATURE")
mod_.object = rig
log.append(f"gorget: {len(gv)} verts")
# прыжок финального удара: высота таза по кадрам (для настройки полёта в игре)
a3 = clips["Attack3"]
hz = []
for f in range(int(a3.frame_range[0]), int(a3.frame_range[1]) + 1):
    capture(a3, f)
    hz.append(round(head(HIPS).z, 2))
log.append(f"Attack3 hips z every 3 frames: {hz[::3]}")

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
