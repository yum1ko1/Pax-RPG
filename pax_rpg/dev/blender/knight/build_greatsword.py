"""Двуручный меч Чёрного рыцаря (по концепту): чёрная плита-клинок ~1,6 м со скошенным концом, широкая гарда,
длинная рукоять с навершием-шипом, красные трещины маны и камень у основания клинка.

Через мост: exec(open(<файл>).read(), {"result": {}}). Строит в отдельной сцене Greatsword, пишет
<W>/meshy/greatsword.glb. Оси: начало — точка хвата правой руки (под гардой), +Y — вдоль клинка,
+X — по ширине, +Z — по толщине (плоскость клинка — XY).
"""
import math
import os

import bmesh
import bpy
from mathutils import Matrix, Vector

W = r"C:\Users\mbkli\Desktop\pax_rpg_work\meshy"
try:
    result
except NameError:
    result = {}

old = bpy.data.scenes.get("Greatsword")
if old is not None:
    for o in list(old.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.scenes.remove(old)
scn = bpy.data.scenes.new("Greatsword")
win = bpy.context.window or bpy.context.window_manager.windows[0]
win.scene = scn


def mat(name, rgb, rough=0.5, metal=0.0, emit=None, strength=0.0):
    m = bpy.data.materials.get("GS_" + name) or bpy.data.materials.new("GS_" + name)
    try:
        m.use_nodes = True
    except AttributeError:
        pass
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = (*rgb, 1)
    return m


STEEL = mat("steel", (0.035, 0.035, 0.04), rough=0.45, metal=0.9)
EDGE = mat("edge", (0.12, 0.12, 0.13), rough=0.3, metal=1.0)
GRIP = mat("grip", (0.03, 0.02, 0.02), rough=0.8)
RED = mat("mana", (0.6, 0.02, 0.08), emit=(1.0, 0.05, 0.2), strength=6.0)

bm = bmesh.new()
mats = [STEEL, EDGE, GRIP, RED]


def add(t, mi, smooth=False):
    vmap = {v: bm.verts.new(v.co) for v in t.verts}
    for f in t.faces:
        nf = bm.faces.new([vmap[v] for v in f.verts])
        nf.material_index = mi
        nf.smooth = smooth
    t.free()


def box(c, size, mi, rot=None):
    t = bmesh.new()
    bmesh.ops.create_cube(t, size=1.0)
    R = rot.to_4x4() if rot is not None else Matrix.Identity(4)
    bmesh.ops.transform(t, matrix=Matrix.Translation(Vector(c)) @ R @ Matrix.Diagonal((*size, 1)), verts=t.verts)
    add(t, mi)


def cyl(p1, p2, r1, r2, mi, segs=12):
    p1, p2 = Vector(p1), Vector(p2)
    d = p2 - p1
    t = bmesh.new()
    bmesh.ops.create_cone(t, cap_ends=True, segments=segs, radius1=r1, radius2=r2, depth=d.length)
    R = Vector((0, 0, 1)).rotation_difference(d.normalized()).to_matrix().to_4x4()
    bmesh.ops.transform(t, matrix=Matrix.Translation((p1 + p2) / 2) @ R, verts=t.verts)
    add(t, mi, smooth=True)


# клинок: плита с фаской-кромкой и скошенным концом (как у концепта: срез под углом)
G0, L, HW, TH = 0.10, 1.62, 0.15, 0.022            # начало клинка, длина, полуширина, полутолщина
t = bmesh.new()
prof = [(-HW, 0.0), (HW, 0.0), (HW, L - 0.10), (HW - 0.06, L), (-HW, L - 0.26)]   # контур в плоскости XY
top = [t.verts.new((x, G0 + y, TH)) for x, y in prof]
bot = [t.verts.new((x, G0 + y, -TH)) for x, y in prof]
t.faces.new(top)
t.faces.new(list(reversed(bot)))
for i in range(len(prof)):
    j = (i + 1) % len(prof)
    t.faces.new((top[i], bot[i], bot[j], top[j]))
add(t, 0)
for s in (1, -1):                                   # кромки чуть светлее
    box((s * (HW - 0.004), G0 + L * 0.45, 0), (0.012, L * 0.9, TH * 1.6), 1)
# гарда, рукоять, навершие
box((0, G0 - 0.035, 0), (0.46, 0.07, 0.07), 0)
box((0, G0 - 0.035, 0), (0.12, 0.10, 0.09), 1)
cyl((0, G0 - 0.07, 0), (0, -0.30, 0), 0.026, 0.024, 2)
for k in range(5):                                  # обмотка
    y = G0 - 0.10 - k * 0.07
    cyl((0, y, 0), (0, y - 0.018, 0), 0.03, 0.03, 0)
cyl((0, -0.30, 0), (0, -0.34, 0), 0.04, 0.035, 1)
cyl((0, -0.34, 0), (0, -0.46, 0), 0.03, 0.004, 1)   # шип навершия
# мановые трещины и камень у основания клинка (обе стороны)
crack = [((0.0, 0.05), (0.05, 0.16)), ((0.05, 0.16), (0.02, 0.27)), ((0.05, 0.16), (0.11, 0.22)),
         ((0.0, 0.05), (-0.06, 0.13)), ((-0.06, 0.13), (-0.04, 0.24)), ((-0.06, 0.13), (-0.12, 0.17)),
         ((0.02, 0.27), (0.06, 0.36))]
for side in (1, -1):
    for (x1, y1), (x2, y2) in crack:
        a, b = Vector((x1, G0 + y1, 0)), Vector((x2, G0 + y2, 0))
        mid, d = (a + b) / 2, b - a
        ang = math.atan2(d.x, d.y)
        box((mid.x, mid.y, side * (TH + 0.0015)), (0.008, d.length, 0.003), 3, rot=Matrix.Rotation(-ang, 3, "Z"))
    t = bmesh.new()
    bmesh.ops.create_uvsphere(t, u_segments=12, v_segments=8, radius=0.022)
    bmesh.ops.transform(t, matrix=Matrix.Translation((0.07, G0 + 0.62, side * TH)) @ Matrix.Diagonal((1, 1, 0.5, 1)), verts=t.verts)
    add(t, 3, smooth=True)

bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
me = bpy.data.meshes.new("Greatsword")
bm.to_mesh(me)
bm.free()
for m in mats:
    me.materials.append(m)
ob = bpy.data.objects.new("Greatsword", me)
scn.collection.objects.link(ob)
os.makedirs(W, exist_ok=True)
path = os.path.join(W, "greatsword.glb")
bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_active_scene=True, export_yup=True, export_animations=False)
result.update(path=path, tris=sum(len(p.vertices) - 2 for p in me.polygons),
              length=round(G0 + L + 0.46, 2))
