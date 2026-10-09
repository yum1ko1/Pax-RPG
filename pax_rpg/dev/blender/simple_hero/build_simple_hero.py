"""Простой герой Юрумы — демон с катаной из примитивов: риг, анимации, экспорт glb для мода.

Запускать в открытом Blender (через мост): exec(open(<этот файл>).read(), {"result": {}}).
Строит всё в отдельной сцене SimpleHero (остальные сцены файла не трогает), сохраняет копию
<W>/simple_hero.blend и <W>/hero_simple.glb. Анимации: Idle, Walk, WalkArmed, Draw, Sheathe.

Части тела жёсткие: каждая весит 100 % на одну кость — кисти и локти не мнутся. Кисть-«варежка».
Меч: кость Weapon копирует WeaponBack (на спине, ребёнок Chest) или WeaponHand (в правой руке) —
переключение ключом влияния ограничения «Hand». Правая рука ставится своим IK: кисть держит рукоять, крен
меча вокруг клинка подбирается так, чтобы запястье почти не гнулось, а поворот уходит в предплечье.
Ось Z вверх, герой смотрит на -Y, правая сторона — -X.
"""
import math
import os
import sys

import bmesh
import bpy
from mathutils import Matrix, Quaternion, Vector

W = r"C:\Users\mbkli\Desktop\pax_rpg_work"
UTIL = r"C:\Users\mbkli\AppData\Local\Programs\Pax Universe\pax_corporations_dev"
FPS = 30
try:
    result
except NameError:
    result = {}

if bpy.context.object is not None and bpy.context.object.mode != "OBJECT":
    bpy.ops.object.mode_set(mode="OBJECT")
os.makedirs(W, exist_ok=True)
if not os.path.exists(os.path.join(W, "hero2_rigged.blend")) and "Hero2_rig" in bpy.data.objects:
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(W, "hero2_rigged.blend"), copy=True)   # работа по Meshy-модели

# ---------- сцена ----------
old = bpy.data.scenes.get("SimpleHero")
if old is not None:
    for o in list(old.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.scenes.remove(old)
for a in [a for a in bpy.data.actions if a.name.startswith("SH_")]:
    bpy.data.actions.remove(a)
scn = bpy.data.scenes.new("SimpleHero")
scn.render.fps = FPS
win = bpy.context.window or bpy.context.window_manager.windows[0]
win.scene = scn
vl = scn.view_layers[0]


# ---------- материалы ----------
def mat(name, rgb, rough=0.6, metal=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.get("SH_" + name) or bpy.data.materials.new("SH_" + name)
    try:
        m.use_nodes = True
    except AttributeError:
        pass
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*rgb, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit is not None:
        b.inputs["Emission Color"].default_value = (*emit, 1.0)
        b.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = (*rgb, 1.0)
    return m


SKIN = mat("skin", (0.80, 0.72, 0.70))
CLOTH = mat("cloth", (0.86, 0.88, 0.92), rough=0.8)
NAVY = mat("navy", (0.015, 0.025, 0.08), rough=0.7)
BLUE = mat("sash", (0.03, 0.15, 0.55), rough=0.6)
HORN = mat("horn", (0.02, 0.015, 0.03), rough=0.3)
HAIR = mat("hair", (0.93, 0.94, 0.98), rough=0.5)
EYE = mat("eye", (0.9, 0.05, 0.08), emit=(1.0, 0.1, 0.1), strength=4.0)
BLADE = mat("blade", (0.62, 0.82, 0.95), rough=0.2, metal=0.8, emit=(0.1, 0.7, 1.0), strength=0.6)
GOLD = mat("gold", (0.80, 0.55, 0.15), rough=0.35, metal=1.0)
IRON = mat("iron", (0.05, 0.05, 0.06), rough=0.4, metal=0.7)
LACQ = mat("lacquer", (0.012, 0.01, 0.02), rough=0.25)


# ---------- геометрия: всё в один bmesh с жёсткими весами ----------
class Mesh:
    def __init__(self):
        self.bm = bmesh.new()
        self.dl = self.bm.verts.layers.deform.verify()
        self.mats = []
        self.groups = []

    def _idx(self, lst, x):
        if x not in lst:
            lst.append(x)
        return lst.index(x)

    def merge(self, t, m, g, smooth=True):
        mi, gi = self._idx(self.mats, m), self._idx(self.groups, g)
        vmap = {}
        for v in t.verts:
            nv = self.bm.verts.new(v.co)
            nv[self.dl][gi] = 1.0
            vmap[v] = nv
        for f in t.faces:
            nf = self.bm.faces.new([vmap[v] for v in f.verts])
            nf.material_index = mi
            nf.smooth = smooth
        t.free()

    def sphere(self, c, r, m, g, rot=None, segs=16, rings=10, cut=None):
        t = bmesh.new()
        bmesh.ops.create_uvsphere(t, u_segments=segs, v_segments=rings, radius=1.0)
        R = rot.to_4x4() if rot is not None else Matrix.Identity(4)
        bmesh.ops.transform(t, matrix=Matrix.Translation(Vector(c)) @ R @ Matrix.Diagonal((*r, 1.0)), verts=t.verts)
        if cut is not None:       # cut(центр грани) -> True: грань убрать (открыть лицо под волосами)
            bmesh.ops.delete(t, geom=[f for f in t.faces if cut(f.calc_center_median())], context="FACES")
        self.merge(t, m, g)

    def cyl(self, p1, p2, r1, r2, m, g, segs=16, flat=1.0, smooth=True):
        p1, p2 = Vector(p1), Vector(p2)
        d = p2 - p1
        t = bmesh.new()
        bmesh.ops.create_cone(t, cap_ends=True, cap_tris=False, segments=segs, radius1=r1, radius2=r2, depth=d.length)
        R = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
        M = Matrix.Translation((p1 + p2) / 2) @ R @ Matrix.Diagonal((1.0, flat, 1.0, 1.0))
        bmesh.ops.transform(t, matrix=M, verts=t.verts)
        self.merge(t, m, g, smooth)

    def box(self, c, size, m, g, rot=None):
        t = bmesh.new()
        bmesh.ops.create_cube(t, size=1.0)
        R = rot.to_4x4() if rot is not None else Matrix.Identity(4)
        bmesh.ops.transform(t, matrix=Matrix.Translation(Vector(c)) @ R @ Matrix.Diagonal((*size, 1.0)), verts=t.verts)
        self.merge(t, m, g, smooth=False)

    def tube(self, pts, radii, m, g, segs=10, flat=1.0, M=None):
        """Трубка по ломаной с переменным радиусом (рога, хвост волос, ножны). flat — сплющить по второй оси."""
        pts = [Vector(p) for p in pts]
        t = bmesh.new()
        rings = []
        n = None
        for i, p in enumerate(pts):
            tan = (pts[min(i + 1, len(pts) - 1)] - pts[max(i - 1, 0)]).normalized()
            if n is None:
                ref = Vector((0, 0, 1)) if abs(tan.z) < 0.9 else Vector((1, 0, 0))
                n = tan.cross(ref).normalized()
            else:
                n = (n - tan * n.dot(tan)).normalized()
            b = tan.cross(n)
            rings.append([t.verts.new(p + radii[i] * (math.cos(a) * n + flat * math.sin(a) * b))
                          for a in (2 * math.pi * k / segs for k in range(segs))])
        for r0, r1 in zip(rings, rings[1:]):
            for k in range(segs):
                t.faces.new((r0[k], r0[(k + 1) % segs], r1[(k + 1) % segs], r1[k]))
        t.faces.new(list(reversed(rings[0])))
        t.faces.new(rings[-1])
        if M is not None:
            bmesh.ops.transform(t, matrix=M, verts=t.verts)
        self.merge(t, m, g)

    def to_object(self, name, rig):
        bmesh.ops.recalc_face_normals(self.bm, faces=self.bm.faces)
        me = bpy.data.meshes.new(name)
        self.bm.to_mesh(me)
        self.bm.free()
        for m in self.mats:
            me.materials.append(m)
        ob = bpy.data.objects.new(name, me)
        scn.collection.objects.link(ob)
        for g in self.groups:
            ob.vertex_groups.new(name=g)
        ob.parent = rig
        mod = ob.modifiers.new("Armature", "ARMATURE")
        mod.object = rig
        return ob


def frame(origin, ydir, zhint):
    """Матрица: Y — ydir, Z — ближе всего к zhint, начало — origin."""
    y = Vector(ydir).normalized()
    z = Vector(zhint) - y * Vector(zhint).dot(y)
    z.normalize()
    x = y.cross(z)
    M = Matrix((x, y, z)).transposed().to_4x4()
    M.translation = Vector(origin)
    return M


# ---------- скелет (имена — гуманоидный профиль Godot) ----------
BONES = [  # имя, голова, хвост, родитель
    ("Root", (0, 0, 0), (0, 0, 0.12), None),
    ("Hips", (0, 0, 0.95), (0, 0, 1.05), "Root"),
    ("Spine", (0, 0, 1.05), (0, 0, 1.18), "Hips"),
    ("Chest", (0, 0, 1.18), (0, 0, 1.40), "Spine"),
    ("Neck", (0, 0, 1.40), (0, 0, 1.50), "Chest"),
    ("Head", (0, 0, 1.50), (0, 0, 1.76), "Neck"),
]
for side, s in (("Left", 1), ("Right", -1)):
    BONES += [
        (side + "Shoulder", (s * 0.04, 0, 1.37), (s * 0.17, 0, 1.37), "Chest"),
        (side + "UpperArm", (s * 0.19, 0, 1.36), (s * 0.235, 0, 1.08), side + "Shoulder"),
        (side + "LowerArm", (s * 0.235, 0, 1.08), (s * 0.28, 0, 0.84), side + "UpperArm"),
        (side + "Hand", (s * 0.28, 0, 0.84), (s * 0.305, 0, 0.71), side + "LowerArm"),
        (side + "UpperLeg", (s * 0.10, 0, 0.92), (s * 0.11, 0, 0.50), "Hips"),
        (side + "LowerLeg", (s * 0.11, 0, 0.50), (s * 0.12, 0, 0.10), side + "UpperLeg"),
        (side + "Foot", (s * 0.12, 0, 0.10), (s * 0.12, -0.15, 0.03), side + "LowerLeg"),
    ]
CONNECTED = {"UpperArm": False, "LowerArm": True, "Hand": True, "LowerLeg": True, "Foot": True}

arm = bpy.data.armatures.new("SimpleHero_rig")
rig = bpy.data.objects.new("SimpleHero_rig", arm)
scn.collection.objects.link(rig)
rig.show_in_front = True
vl.objects.active = rig
rig.select_set(True)
bpy.ops.object.mode_set(mode="EDIT")
eb = arm.edit_bones
for name, h, t, par in BONES:
    b = eb.new(name)
    b.head, b.tail = Vector(h), Vector(t)
    b.roll = 0.0
    if par:
        b.parent = eb[par]
        b.use_connect = any(name.endswith(k) and v for k, v in CONNECTED.items())
# точка хвата в правой руке: центр кисти; клинок вперёд (-Y), обух вверх
H_GRIP = Vector((-0.295, -0.005, 0.765))
WH_REST = frame(H_GRIP, (0, -1, 0), (0, 0, 1))
for name, par in (("WeaponHand", "RightHand"), ("Weapon", "Root")):
    b = eb.new(name)
    b.head, b.tail = Vector((0, 0, 0)), Vector((0, 0.1, 0))
    b.matrix = WH_REST
    b.parent = eb[par]
bpy.ops.object.mode_set(mode="OBJECT")
for b in arm.bones:
    b.use_deform = b.name not in ("Root", "WeaponHand")
pb = rig.pose.bones
for p in pb:
    p.rotation_mode = "QUATERNION"


def rest(b):
    return arm.bones[b].matrix_local.copy()


def aq(b, axis, deg):
    """Поворот кости вокруг оси в осях арматуры (в покое) — в локальный кватернион."""
    R = rest(b).to_quaternion()
    return R.inverted() @ Quaternion(Vector(axis), math.radians(deg)) @ R


def reset():
    for p in pb:
        p.rotation_quaternion = (1, 0, 0, 0)
        p.location = (0, 0, 0)


# ---------- правая рука: свой двухкостный IK ----------
L1 = (rest("RightUpperArm").translation - rest("RightLowerArm").translation).length
L2 = (rest("RightLowerArm").translation - rest("RightHand").translation).length
K = rest("RightHand").inverted() @ WH_REST            # кисть -> точка хвата
LA_H = (rest("RightLowerArm").inverted() @ rest("RightHand")).to_3x3()


def elbow(S, Wp, pole):
    v = Wp - S
    d = v.length
    u = v / d
    a = (L1 * L1 - L2 * L2 + d * d) / (2 * d)
    h = math.sqrt(max(0.0, L1 * L1 - a * a))
    pv = Vector(pole) - u * Vector(pole).dot(u)
    pv.normalize()
    return S + u * a + pv * h


def solve_arm(grip, blade, pole):
    """Правая рука держит рукоять в точке grip, клинок смотрит в blade. Возвращает (кадр хвата, ошибка, изгиб кисти°)."""
    grip, blade = Vector(grip), Vector(blade).normalized()
    for n in ("RightUpperArm", "RightLowerArm", "RightHand"):
        pb[n].rotation_quaternion = (1, 0, 0, 0)
    vl.update()
    S = pb["RightUpperArm"].head.copy()
    base = blade.orthogonal().normalized()
    best = None
    for k in range(72):                     # крен меча вокруг клинка — какой удобнее запястью
        F = frame(grip, blade, Quaternion(blade, 2 * math.pi * k / 72) @ base)
        Hw = F @ K.inverted()
        Wp = Hw.translation
        d = (Wp - S).length
        over = max(0.0, d - (L1 + L2 - 0.004))
        if over > 0:
            Wp = S + (Wp - S) * ((L1 + L2 - 0.004) / d)
        E = elbow(S, Wp, pole)
        bend = math.degrees(Hw.col[1].xyz.angle(Wp - E))
        score = bend + over * 2000
        if best is None or score < best[0]:
            best = (score, F, Hw, Wp, E, bend)
    _, F, Hw, Wp, E, bend = best
    M0 = pb["RightUpperArm"].matrix.copy()
    q = M0.col[1].xyz.rotation_difference((E - S).normalized())
    pb["RightUpperArm"].matrix = Matrix.Translation(S) @ (q.to_matrix() @ M0.to_3x3()).to_4x4()
    vl.update()
    R_la = Hw.to_3x3() @ LA_H.inverted()    # предплечье с тем же поворотом, что у кисти (кручение — в предплечье)
    q = R_la.col[1].rotation_difference((Wp - E).normalized())
    pb["RightLowerArm"].matrix = Matrix.Translation(pb["RightLowerArm"].head) @ (q.to_matrix() @ R_la).to_4x4()
    vl.update()
    pb["RightHand"].matrix = Matrix.Translation(pb["RightHand"].head) @ Hw.to_3x3().to_4x4()
    vl.update()
    return F, (pb["WeaponHand"].matrix.translation - grip).length, bend


# ---------- место меча на спине: из позы хвата ----------
BACK_GRIP = Vector((-0.20, 0.17, 1.55))                   # рукоять над правым плечом
BACK_DIR = Vector((0.45, 0.05, -0.89)).normalized()       # клинок к левому бедру
GRAB_POLE = (-0.7, -0.25, 0.65)                           # локоть вверх-наружу
reset()
F_back, grab_err, grab_bend = solve_arm(BACK_GRIP, BACK_DIR, GRAB_POLE)
WB_REST = F_back.copy()                                   # Chest в этой позе не повёрнут — покой = поза
bpy.ops.object.mode_set(mode="EDIT")
b = arm.edit_bones.new("WeaponBack")
b.head, b.tail = Vector((0, 0, 0)), Vector((0, 0.1, 0))
b.matrix = WB_REST
b.parent = arm.edit_bones["Chest"]
bpy.ops.object.mode_set(mode="OBJECT")
arm.bones["WeaponBack"].use_deform = False
pb = rig.pose.bones
pb["WeaponBack"].rotation_mode = "QUATERNION"
for cname, sub, inf in (("Back", "WeaponBack", 1.0), ("Hand", "WeaponHand", 0.0)):
    c = pb["Weapon"].constraints.new("COPY_TRANSFORMS")
    c.name, c.target, c.subtarget, c.influence = cname, rig, sub, inf
reset()
vl.update()

# ---------- тело ----------
body = Mesh()
# ноги: широкие хакама, обмотки, таби
for side, s in (("Left", 1), ("Right", -1)):
    body.cyl((s * 0.10, 0, 0.97), (s * 0.112, 0, 0.50), 0.115, 0.135, CLOTH, side + "UpperLeg")
    body.cyl((s * 0.112, 0, 0.53), (s * 0.122, 0, 0.17), 0.13, 0.155, CLOTH, side + "LowerLeg")
    body.cyl((s * 0.12, 0, 0.21), (s * 0.12, 0, 0.07), 0.05, 0.048, NAVY, side + "LowerLeg")
    body.box((s * 0.12, -0.045, 0.035), (0.085, 0.24, 0.07), NAVY, side + "Foot")
    body.sphere((s * 0.12, -0.16, 0.035), (0.042, 0.03, 0.034), NAVY, side + "Foot")
# таз, пояс и концы пояса
body.cyl((0, 0, 0.84), (0, 0, 1.03), 0.165, 0.15, CLOTH, "Hips", flat=0.8)
body.cyl((0, 0, 0.97), (0, 0, 1.07), 0.16, 0.152, BLUE, "Hips", flat=0.8)
body.sphere((0.05, -0.135, 1.01), (0.035, 0.025, 0.03), BLUE, "Hips")
body.box((0.035, -0.14, 0.86), (0.035, 0.012, 0.26), BLUE, "Hips", rot=Matrix.Rotation(0.12, 3, "Y"))
body.box((0.075, -0.13, 0.88), (0.035, 0.012, 0.22), BLUE, "Hips", rot=Matrix.Rotation(-0.10, 3, "Y"))
# торс
body.cyl((0, 0, 1.03), (0, 0, 1.22), 0.125, 0.14, SKIN, "Spine", flat=0.72)
body.sphere((0, 0.005, 1.29), (0.185, 0.125, 0.15), SKIN, "Chest")
# шея и голова
body.cyl((0, 0, 1.38), (0, 0, 1.53), 0.05, 0.045, SKIN, "Neck")
body.sphere((0, -0.005, 1.62), (0.092, 0.102, 0.118), SKIN, "Head")
body.sphere((0, -0.06, 1.54), (0.06, 0.05, 0.04), SKIN, "Head")                    # подбородок
for s in (1, -1):
    body.sphere((s * 0.034, -0.093, 1.635), (0.014, 0.008, 0.009), EYE, "Head")
    body.tube([(s * 0.085, 0.0, 1.62), (s * 0.125, 0.025, 1.655), (s * 0.15, 0.04, 1.68)],
              [0.022, 0.012, 0.002], SKIN, "Head", segs=8, flat=0.35)                # острые уши
    body.tube([(s * 0.05, -0.07, 1.70), (s * 0.085, -0.07, 1.775), (s * 0.115, -0.035, 1.84),
               (s * 0.125, 0.02, 1.885), (s * 0.11, 0.08, 1.91)],
              [0.024, 0.02, 0.015, 0.009, 0.002], HORN, "Head", segs=10)            # рога
# волосы: шапка с открытым лицом, пучок, хвост
body.sphere((0, 0.018, 1.64), (0.103, 0.115, 0.125), HAIR, "Head", segs=20, rings=12,
            cut=lambda c: c.y < -0.035 and c.z < 1.69)
body.cyl((0, 0.025, 1.73), (0, 0.03, 1.765), 0.032, 0.03, NAVY, "Head")
body.sphere((0, 0.03, 1.80), (0.052, 0.05, 0.048), HAIR, "Head")
body.tube([(0, 0.07, 1.79), (0, 0.13, 1.74), (0, 0.155, 1.64), (0, 0.15, 1.56)],
          [0.03, 0.03, 0.022, 0.004], HAIR, "Head", segs=10)
# руки
for side, s in (("Left", 1), ("Right", -1)):
    body.sphere((s * 0.19, 0, 1.355), (0.068, 0.065, 0.06), SKIN, side + "Shoulder")
    body.cyl((s * 0.19, 0, 1.36), (s * 0.235, 0, 1.08), 0.05, 0.042, SKIN, side + "UpperArm")
    body.sphere((s * 0.235, 0, 1.08), (0.042, 0.042, 0.042), SKIN, side + "LowerArm")
    body.cyl((s * 0.235, 0, 1.08), (s * 0.28, 0, 0.84), 0.041, 0.033, SKIN, side + "LowerArm")
    body.cyl((s * 0.257, 0, 0.97), (s * 0.282, 0, 0.83), 0.047, 0.04, NAVY, side + "LowerArm")   # наруч
    body.sphere((s * 0.293, -0.004, 0.77), (0.026, 0.047, 0.065), SKIN, side + "Hand",
                rot=Matrix.Rotation(s * 0.19, 3, "Y"))
    body.tube([(s * 0.29, -0.035, 0.815), (s * 0.295, -0.058, 0.78), (s * 0.30, -0.055, 0.75)],
              [0.014, 0.012, 0.009], SKIN, side + "Hand", segs=8)                    # большой палец
hero = body.to_object("SimpleHero_body", rig)


# ---------- катана (в осях точки хвата: Y — вдоль клинка, Z — обух) и ножны ----------
def blade_pts(y0, y1, n, lift):
    return [Vector((0, y0 + (y1 - y0) * i / n, lift * (i / n) ** 2)) for i in range(n + 1)]


def katana(m: Mesh, M):
    t = bmesh.new()                         # клинок: сечение-ромб, изгиб вверх к острию, острие — точка
    secs = []
    for p in blade_pts(0.07, 0.76, 8, 0.03):
        secs.append([t.verts.new(p + Vector(o)) for o in ((0, 0, 0.015), (0.0035, 0, 0.002), (0, 0, -0.015), (-0.0035, 0, 0.002))])
    tip = t.verts.new(Vector((0, 0.81, 0.036)))
    for a, b in zip(secs, secs[1:]):
        for k in range(4):
            t.faces.new((a[k], a[(k + 1) % 4], b[(k + 1) % 4], b[k]))
    for k in range(4):
        t.faces.new((secs[-1][k], secs[-1][(k + 1) % 4], tip))
    t.faces.new(list(reversed(secs[0])))
    bmesh.ops.transform(t, matrix=M, verts=t.verts)
    m.merge(t, BLADE, "Weapon", smooth=False)
    R = M.to_3x3()
    P = lambda *v: M @ Vector(v)
    m.cyl(P(0, 0.058, 0), P(0, 0.068, 0), 0.038, 0.038, IRON, "Weapon", segs=20)             # цуба
    m.box(P(0, 0.078, 0.0), (0.012, 0.02, 0.034), GOLD, "Weapon", rot=R)                       # хабаки
    m.cyl(P(0, -0.17, 0), P(0, 0.058, 0), 0.016, 0.015, NAVY, "Weapon", segs=12, flat=0.8)     # рукоять
    m.sphere(P(0, -0.175, 0), (0.018, 0.012, 0.016), GOLD, "Weapon", rot=R)                    # навершие


def saya(m: Mesh, M):
    pts = blade_pts(0.065, 0.83, 10, 0.033)                 # тонкая сторона — поперёк клинка (X)
    m.tube(pts, [0.012] * len(pts), LACQ, "Chest", segs=12, flat=1.85, M=M)
    pts = [M @ p for p in pts]
    m.cyl(M @ Vector((0, 0.062, 0)), M @ Vector((0, 0.09, 0)), 0.025, 0.025, GOLD, "Chest", segs=12)   # койгути
    m.sphere(pts[-1], (0.024, 0.024, 0.024), GOLD, "Chest")                                           # кодзири


kat = Mesh()
katana(kat, WH_REST)
sword = kat.to_object("SimpleHero_katana", rig)
sh = Mesh()
saya(sh, WB_REST)
scabbard = sh.to_object("SimpleHero_saya", rig)


# ---------- анимации ----------
def new_action(name):
    a = bpy.data.actions.new(name)
    a.use_fake_user = True
    rig.animation_data_create()
    rig.animation_data.action = a
    return a


_prev = {}


def key(f, hand_infl):
    pb["Weapon"].constraints["Hand"].influence = hand_infl
    for p in pb:
        q = p.rotation_quaternion
        if p.name in _prev and _prev[p.name].dot(q) < 0:   # тот же знак, что у прошлого ключа — без кувырков
            p.rotation_quaternion = -q
        _prev[p.name] = p.rotation_quaternion.copy()
        p.keyframe_insert("rotation_quaternion", frame=f)
        p.keyframe_insert("location", frame=f)
    pb["Weapon"].constraints["Hand"].keyframe_insert("influence", frame=f)


def relaxed_arms(swing=0.0, side_only=None):
    for side, s in (("Left", 1), ("Right", -1)):
        if side_only and side != side_only:
            continue
        pb[side + "UpperArm"].rotation_quaternion = aq(side + "UpperArm", (1, 0, 0), swing * s) @ aq(side + "UpperArm", (0, 1, 0), 4 * s)
        pb[side + "LowerArm"].rotation_quaternion = aq(side + "LowerArm", (1, 0, 0), -10 - 12 * max(0.0, -swing * s) / 20)


def walk_body(f, n=24):
    p = 2 * math.pi * f / n
    sn, cs = math.sin(p), math.cos(p)
    for side, s in (("Left", 1), ("Right", -1)):
        th = -28 * sn * s                                    # бедро: минус — вперёд
        knee = 6 + 48 * max(0.0, cs * s)                     # колено гнётся, пока нога летит вперёд
        pb[side + "UpperLeg"].rotation_quaternion = aq(side + "UpperLeg", (1, 0, 0), th)
        pb[side + "LowerLeg"].rotation_quaternion = aq(side + "LowerLeg", (1, 0, 0), knee)
        pb[side + "Foot"].rotation_quaternion = aq(side + "Foot", (1, 0, 0), -(th + knee) * 0.85)
    pb["Hips"].location = (0, 0.018 * math.cos(2 * p) - 0.022, 0)   # пружинистый шаг
    pb["Hips"].rotation_quaternion = aq("Hips", (0, 0, 1), -6 * sn)
    pb["Spine"].rotation_quaternion = aq("Spine", (1, 0, 0), 5)
    pb["Chest"].rotation_quaternion = aq("Chest", (0, 0, 1), 9 * sn)
    pb["Head"].rotation_quaternion = aq("Head", (0, 0, 1), -4 * sn) @ aq("Head", (1, 0, 0), -3)
    return sn


# Idle — дыхание, 60 кадров
new_action("Idle")
_prev.clear()
for f in range(0, 61, 6):
    t = 2 * math.pi * f / 60
    reset()
    relaxed_arms(1.5 * math.sin(t))
    pb["Chest"].rotation_quaternion = aq("Chest", (1, 0, 0), -1.5 * math.sin(t))
    pb["Head"].rotation_quaternion = aq("Head", (1, 0, 0), 1.5 * math.sin(t + 0.6))
    pb["Hips"].location = (0, -0.004 * (1 - math.cos(t)), 0)
    key(f, 0.0)

# Walk — цикл 24 кадра, меч за спиной
new_action("Walk")
_prev.clear()
for f in range(0, 25, 2):
    reset()
    sn = walk_body(f)
    relaxed_arms(22 * sn)
    key(f, 0.0)

# стойка с мечом: k 0..1 — насколько глубоко
def stance(k, lean=0.0, turn=0.0):
    pb["Hips"].location = (0, -0.07 * k, 0)
    pb["Hips"].rotation_quaternion = aq("Hips", (0, 0, 1), 12 * k)
    pb["RightUpperLeg"].rotation_quaternion = aq("RightUpperLeg", (1, 0, 0), -32 * k)
    pb["RightLowerLeg"].rotation_quaternion = aq("RightLowerLeg", (1, 0, 0), 30 * k)
    pb["RightFoot"].rotation_quaternion = aq("RightFoot", (1, 0, 0), 2 * k)
    pb["LeftUpperLeg"].rotation_quaternion = aq("LeftUpperLeg", (1, 0, 0), 20 * k) @ aq("LeftUpperLeg", (0, 1, 0), 6 * k)
    pb["LeftLowerLeg"].rotation_quaternion = aq("LeftLowerLeg", (1, 0, 0), 12 * k)
    pb["LeftFoot"].rotation_quaternion = aq("LeftFoot", (1, 0, 0), -26 * k)
    pb["Spine"].rotation_quaternion = aq("Spine", (1, 0, 0), lean)
    pb["Chest"].rotation_quaternion = aq("Chest", (0, 0, 1), turn)
    pb["LeftUpperArm"].rotation_quaternion = aq("LeftUpperArm", (1, 0, 0), 35 * k) @ aq("LeftUpperArm", (0, 1, 0), 4 - 14 * k)
    pb["LeftLowerArm"].rotation_quaternion = aq("LeftLowerArm", (1, 0, 0), -10 - 15 * k)


READY_GRIP, READY_DIR = Vector((-0.17, -0.36, 1.06)), Vector((0.12, -0.80, 0.58))
ARMED_POLE = (-0.8, 0.4, -0.3)                 # локоть вниз-наружу
# (кадр, рука в ножнах? grip, клинок, полюс, стойка, наклон, поворот груди, влияние Hand)
DRAW = [
    (0, None, None, None, 0.0, 0, 0, 0.0),
    (5, (-0.30, -0.10, 1.62), (0.3, 0.4, -0.85), GRAB_POLE, 0.15, -3, -8, 0.0),
    (9, BACK_GRIP, BACK_DIR, GRAB_POLE, 0.0, 0, 0, 0.0),
    (10, BACK_GRIP, BACK_DIR, GRAB_POLE, 0.0, 0, 0, 1.0),
    (15, (-0.24, -0.08, 1.80), (0.25, 0.30, 0.92), (-0.8, 0.2, 0.3), 0.35, -6, -10, 1.0),
    (20, (-0.02, -0.42, 1.02), (0.55, -0.45, -0.70), ARMED_POLE, 1.0, 12, 18, 1.0),
    (23, (0.03, -0.40, 0.97), (0.60, -0.35, -0.72), ARMED_POLE, 1.05, 14, 20, 1.0),
    (30, READY_GRIP, READY_DIR, ARMED_POLE, 0.8, 6, 8, 1.0),
    (36, READY_GRIP, READY_DIR, ARMED_POLE, 0.8, 6, 8, 1.0),
]
errs = {}


def draw_pose(row):
    _, grip, blade, pole, k, lean, turn, _ = row
    reset()
    relaxed_arms()
    stance(k, lean, turn)
    if grip is not None:
        vl.update()
        # точки хвата заданы для неповёрнутой груди — повернуть вместе с ней
        C = pb["Chest"].matrix @ rest("Chest").inverted()
        _, e, bend = solve_arm(C @ Vector(grip), C.to_3x3() @ Vector(blade), pole)
        return round(e, 4), round(bend, 1)
    return None


for name, rows in (("Draw", DRAW), ("Sheathe", [(36 - r[0],) + r[1:] for r in reversed(DRAW)])):
    new_action(name)
    _prev.clear()
    for row in rows:
        errs[f"{name}{row[0]}"] = draw_pose(row)
        key(row[0], row[7])

# WalkArmed — ноги как в Walk, правая рука держит меч у бедра остриём вперёд-вверх
new_action("WalkArmed")
_prev.clear()
for f in range(0, 25, 2):
    reset()
    sn = walk_body(f)
    relaxed_arms(22 * sn, side_only="Left")
    vl.update()
    C = pb["Chest"].matrix @ rest("Chest").inverted()
    _, e, bend = solve_arm(C @ READY_GRIP, C.to_3x3() @ READY_DIR, ARMED_POLE)
    errs[f"WalkArmed{f}"] = (round(e, 4), round(bend, 1))
    key(f, 1.0)

rig.animation_data.action = bpy.data.actions["Idle"]
if hasattr(rig.animation_data, "action_slot") and len(getattr(bpy.data.actions["Idle"], "slots", [])):
    rig.animation_data.action_slot = bpy.data.actions["Idle"].slots[0]
scn.frame_start, scn.frame_end = 0, 60
scn.frame_set(0)

result.update(grab_err=round(grab_err, 4), grab_bend=round(grab_bend, 1), errs=errs,
              tris=sum(len(p.vertices) - 2 for o in (hero, sword, scabbard) for p in o.data.polygons))
