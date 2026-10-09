"""Плащ Чёрного рыцаря — отдельный предмет (в игре — ткань SoftBody3D, надевается через config/items.json).

Через мост, после refine_knight.py (сцена Knight, тело без плаща): exec(open(<файл>).read(), {"result": {}}).
Строит ровную сетку ткани NX × NZ по спине рыцаря в позе покоя: верхний ряд — по линии плеч (его в игре пришивают
к груди и плечам), дальше полотно спускается до икр и висит отвесно ниже самой выпуклой точки спины (как настоящая
ткань); подол рваный — зубцы разной длины. Без развёртки и швов (номер точки ткани = номер вершины), гладкие
нормали, двусторонний материал; тёмный низ — цветом вершин. Пишет <W>/knight/cape_black.glb и кадры
<W>/shots/cape_*.png.
"""
import importlib
import math
import os
import random
import sys

import bpy
import numpy as np
from mathutils import Vector

UTIL = r"C:\Users\mbkli\AppData\Local\Programs\Pax Universe\pax_corporations_dev"
sys.path.insert(0, UTIL)
import pax_rpg_blender_util as U  # noqa: E402

importlib.reload(U)
W = r"C:\Users\mbkli\Desktop\pax_rpg_work\meshy"
OUT = os.path.join(W, "knight", "cape_black.glb")
try:
    result
except NameError:
    result = {}
log = result.setdefault("log", [])

NX, NZ = 15, 20                     # колонок и рядов вершин
Z_BOT = 0.24                        # низ плаща (до икр), м
GAP = 0.05                          # зазор от спины
HEM = 0.09                          # глубина зубцов подола
COLOR = (0.196, 0.165, 0.235)       # sRGB — цвет ткани старого плаща
random.seed(7)

win = bpy.context.window or bpy.context.window_manager.windows[0]
scn = bpy.data.scenes["Knight"]
win.scene = scn
vl = scn.view_layers[0]
rig = bpy.data.objects["Knight_rig"]
rig.animation_data.action = None
for p in rig.pose.bones:
    p.rotation_quaternion = (1, 0, 0, 0)
    p.location = (0, 0, 0)
vl.update()
MW = rig.matrix_world


def head(b):
    return MW @ rig.pose.bones[b].head


body = [o for o in scn.objects if o.type == "MESH" and o.name.startswith("Knight_body")][0]
co = np.array([tuple(body.matrix_world @ v.co) for v in body.data.vertices])
hips = head("Hips")
ls, rs = head("LeftShoulder"), head("RightShoulder")
z_top = max(ls.z, rs.z) + 0.05
la, ra = head("LeftArm"), head("RightArm")           # плечевые суставы: ключицы у этой модели почти у шеи
half_top = max(abs(la.x - hips.x), abs(ra.x - hips.x)) + 0.02
half_bot = half_top + 0.10
back = co[co[:, 1] > hips.y]                    # +Y — спина (рыцарь смотрит на -Y)
log.append(f"z_top {z_top:.2f}, half width {half_top:.2f}..{half_bot:.2f}, back verts {len(back)}")

verts = []
grid = {}
for i in range(NX):
    u = i / (NX - 1) * 2 - 1                    # -1 … 1 поперёк
    ys = []
    for j in range(NZ):
        t = j / (NZ - 1)
        z = z_top - (z_top - Z_BOT) * t
        x = hips.x + u * (half_top + (half_bot - half_top) * t)
        sel = back[(np.abs(back[:, 0] - x) < 0.06) & (np.abs(back[:, 2] - z) < 0.05)]
        y = float(sel[:, 1].max()) + GAP if len(sel) else (ys[-1] if ys else hips.y + 0.18)
        if ys:
            y = max(y, ys[-1])                  # ниже самой выпуклой точки — отвесно
        ys.append(y)
    for j in range(NZ):
        t = j / (NZ - 1)
        z = z_top - (z_top - Z_BOT) * t
        x = hips.x + u * (half_top + (half_bot - half_top) * t)
        y = ys[j] - (0.04 if j == 0 else 0.0)   # верх чуть заходит на плечи
        if j == NZ - 1:                         # рваный подол: зубцы разной длины
            z += random.uniform(-HEM, HEM * 0.4) + (0.12 if random.random() < 0.25 else 0.0)
        elif j == NZ - 2:
            z += random.uniform(-HEM * 0.3, HEM * 0.3)
        grid[i, j] = len(verts)
        verts.append((x, y, z))
faces = []
for i in range(NX - 1):
    for j in range(NZ - 1):
        faces.append((grid[i, j], grid[i, j + 1], grid[i + 1, j + 1], grid[i + 1, j]))

old = bpy.data.objects.get("Cape_black")
if old is not None:
    bpy.data.objects.remove(old, do_unlink=True)
me = bpy.data.meshes.new("Cape_black")
me.from_pydata(verts, [], faces)
me.update()
me.shade_smooth()
ob = bpy.data.objects.new("Cape_black", me)
scn.collection.objects.link(ob)
# цвет вершин: к подолу и краям темнее (обтрёпанная ткань)
ca = me.color_attributes.new("Col", "FLOAT_COLOR", "POINT")
for (i, j), vi in grid.items():
    t = j / (NZ - 1)
    edge = abs(i / (NX - 1) * 2 - 1)
    k = 1.0 - 0.45 * t ** 2 - 0.2 * edge ** 3
    ca.data[vi].color = (k, k, k, 1.0)
lin = [c ** 2.2 for c in COLOR]
mat = bpy.data.materials.get("CapeCloth") or bpy.data.materials.new("CapeCloth")
mat.use_nodes = True
mat.use_backface_culling = False
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
for n in [n for n in nt.nodes if n.type in ("VERTEX_COLOR", "MIX_RGB", "MIX")]:
    nt.nodes.remove(n)
vc = nt.nodes.new("ShaderNodeVertexColor")
vc.layer_name = "Col"
mul = nt.nodes.new("ShaderNodeMix")
mul.data_type = "RGBA"
mul.blend_type = "MULTIPLY"
mul.inputs["Factor"].default_value = 1.0
mul.inputs[6].default_value = (*lin, 1.0)
nt.links.new(vc.outputs["Color"], mul.inputs[7])
nt.links.new(mul.outputs[2], bsdf.inputs["Base Color"])
bsdf.inputs["Roughness"].default_value = 0.92
me.materials.append(mat)

for o in vl.objects:
    o.select_set(False)
ob.select_set(True)
vl.objects.active = ob
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_animations=False,
                          export_skins=False, export_yup=True, export_texcoords=False, export_tangents=False,
                          export_vertex_color="ACTIVE")
log.append(f"cape_black.glb: {len(verts)} verts, {len(faces)} quads, {os.path.getsize(OUT)} bytes")

# кадры: плащ на рыцаре сзади и сбоку
for n in ("Sword_Hand", "Sword_Drag"):
    if n in bpy.data.objects:
        bpy.data.objects[n].hide_set(True)
files = U.shot("cape_on", (0, 0.1, 0.95), 2.4, ("BACK", "RIGHT", "FRONT34"), res=450)
result["files"] = [p.split("\\")[-1] for p in files]
