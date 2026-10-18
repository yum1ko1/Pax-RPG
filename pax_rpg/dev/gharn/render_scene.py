"""Превью планировки города в Blender (без игры): зона из config/<город>.json — модели (исходники с текстурами,
models_graded), коробки материалов, гирлянды фонарей со светом, вывески, жаровни; ночь Юрумы (луна, тёплые огни).
Снимает ракурсы — для левел-дизайна по рендерам.
    blender -b -P render_scene.py -- <gharn.json> <папка моделей gharn> <out_dir> <x0,z0,x1,z1> [кадр ...]
кадр: имя:ex,ey,ez:tx,ty,tz[:lens] (в осях игры: y — вверх, город входят с +z к −z)."""
import json
import math
import os
import random
import sys

import bpy
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
LAY, MODELS, OUT, RECT = A[0], A[1], A[2], [float(v) for v in A[3].split(",")]
SHOTS = A[4:]
os.makedirs(OUT, exist_ok=True)
lay = json.load(open(LAY, encoding="utf-8"))
MATS = {"stone": (0.49, 0.48, 0.45), "stone_cut": (0.55, 0.53, 0.49), "stone_dark": (0.36, 0.35, 0.33),
        "earth": (0.6, 0.45, 0.28), "wood": (0.3, 0.2, 0.13), "plaster": (0.75, 0.7, 0.6), "red": (0.55, 0.06, 0.05),
        "arena_wall": (0.2, 0.17, 0.15), "arena_seat": (0.28, 0.22, 0.17), "arena_sand": (0.45, 0.36, 0.25)}


def g2b(p):                                   # игра (x, y вверх, z) → Blender (x, −z, y)
    return Vector((p[0], -p[2], p[1]))


def inside(p, m=0.0):
    return RECT[0] - m <= p[0] <= RECT[2] + m and RECT[1] - m <= p[2] <= RECT[3] + m


for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
sc = bpy.context.scene
eng = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in eng else "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 1280, 720
try:
    sc.eevee.use_shadows = True
    sc.eevee.use_gtao = True
    sc.eevee.use_bloom = True
except Exception:
    pass
try:
    sc.view_settings.view_transform = "AgX"
except Exception:
    sc.view_settings.view_transform = "Filmic"
sc.view_settings.exposure = float(os.environ.get("EXPOSURE", "0.6"))


def mat(name, col, emit=None, strength=0.0, rough=0.85):
    m = bpy.data.materials.get(name)
    if m:
        return m
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*col, 1)
    b.inputs["Roughness"].default_value = rough
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1)
        b.inputs["Emission Strength"].default_value = strength
    return m


# мир: ночь — тёмно-лиловое небо, луна
w = bpy.data.worlds.new("night")
sc.world = w
w.use_nodes = True
bg = w.node_tree.nodes["Background"]
bg.inputs[0].default_value = (0.035, 0.03, 0.08, 1)
bg.inputs[1].default_value = 1.0
moon = bpy.data.objects.new("moon", bpy.data.lights.new("moon", "SUN"))
moon.data.energy = 0.35
moon.data.color = (0.55, 0.6, 1.0)
moon.rotation_euler = (math.radians(55), 0, math.radians(-30))
sc.collection.objects.link(moon)

# земля
bpy.ops.mesh.primitive_plane_add(size=1)
gnd = bpy.context.object
cx, cz = (RECT[0] + RECT[2]) / 2, (RECT[1] + RECT[3]) / 2
gnd.location = g2b((cx, 0, cz))
gnd.scale = (RECT[2] - RECT[0] + 80, RECT[3] - RECT[1] + 80, 1)
gnd.data.materials.append(mat("ground", (0.16, 0.13, 0.12), rough=0.95))
for x0, x1, z0, z1 in ((-5.0, 5.0, 14, 90), (-78, 78, -8.5, 8.5)):   # мостовая (в игре — маска земли): темнее, холоднее
    bpy.ops.mesh.primitive_plane_add(size=1)
    o = bpy.context.object
    o.location = g2b(((x0 + x1) / 2, 0.01, (z0 + z1) / 2))
    o.scale = (x1 - x0, z1 - z0, 1)
    o.data.materials.append(mat("cobble", (0.09, 0.085, 0.09), rough=0.9))

cache = {}
TEX = int(os.environ.get("TEX", "1024"))


def model(rel):
    if rel in cache:
        return cache[rel]
    path = os.path.join(MODELS, rel.replace("models/gharn/", ""))
    if not os.path.exists(path):
        cache[rel] = None
        return None
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for img in bpy.data.images:                 # превью: текстуры 1K — 4K всего города не влезают в память
        if img.size[0] > TEX and not img.get("small"):
            try:
                img.scale(TEX, max(1, int(img.size[1] * TEX / img.size[0])))
            except Exception:
                pass
            img["small"] = 1
    col = bpy.data.collections.new(rel)
    for o in new:
        for c in o.users_collection:
            c.objects.unlink(o)
        col.objects.link(o)
    cache[rel] = col
    return col


lanterns = []
for e in lay["items"]:
    p = e.get("p")
    if p is None:
        continue
    if "lanterns" in e:
        l = e["lanterns"]
        if inside((l[0], 0, l[1]), 5) or inside((l[2], 0, l[3]), 5):
            lanterns.append((l, e.get("seed", 0)))
        continue
    if not inside(p, 4):
        continue
    r = math.radians(float(e.get("r", 0)))
    if e.get("m"):
        col = model(e["m"])
        if col is None:
            continue
        inst = bpy.data.objects.new("i", None)
        inst.instance_type = "COLLECTION"
        inst.instance_collection = col
        inst.location = g2b(p)
        inst.rotation_euler = (0, 0, r)
        s = float(e.get("s", 1.0))
        inst.scale = (s, s, s)
        sc.collection.objects.link(inst)
    elif "box" in e:
        bx = e["box"]
        bpy.ops.mesh.primitive_cube_add(size=1)
        o = bpy.context.object
        o.location = g2b(p)
        o.scale = (bx[0], bx[2], bx[1])
        o.rotation_euler = (math.radians(float(e.get("rx", 0))), 0, r)
        c = MATS.get(e.get("mat", "stone"), (0.5, 0.5, 0.5))
        o.data.materials.append(mat("box_" + e.get("mat", "stone"), c))
    elif "sign" in e:
        bpy.ops.mesh.primitive_cube_add(size=1)
        o = bpy.context.object
        o.location = g2b((p[0], 1.6, p[2]))
        o.scale = (0.7, 0.08, 1.6)
        o.rotation_euler = (0, 0, r)
        o.data.materials.append(mat("sign", (0.3, 0.03, 0.03), (1.0, 0.25, 0.1), 0.6))
    elif e.get("brazier"):
        lt = bpy.data.objects.new("br", bpy.data.lights.new("br", "POINT"))
        lt.data.energy = 120
        lt.data.color = (1.0, 0.5, 0.2)
        lt.location = g2b((p[0], 1.2, p[2]))
        sc.collection.objects.link(lt)

paper = mat("paper", (0.9, 0.3, 0.1), (1.0, 0.36, 0.08), float(os.environ.get("PAPER", "1.2")))
rope = mat("rope", (0.24, 0.16, 0.1))
for l, seed in lanterns:
    rng = random.Random(seed)
    a = Vector((l[0], 0, l[1]))
    b = Vector((l[2], 0, l[3]))
    h = float(l[4]) if len(l) > 4 else 4.2
    d = b - a
    n = max(2, int(d.length / 3.4))
    for i in range(n):
        f = (i + 0.5) / n
        sag = math.sin(f * math.pi) * 0.35
        q = a.lerp(b, f)
        s = rng.uniform(0.75, 1.25)
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.38 * s, segments=16, ring_count=8)
        o = bpy.context.object
        o.scale.z = 0.86 / 0.76
        o.location = g2b((q.x, h - sag - 0.55 * s, q.z))
        o.data.materials.append(paper)
    bpy.ops.mesh.primitive_cylinder_add(radius=0.028, depth=d.length)   # верёвка
    o = bpy.context.object
    m_ = a.lerp(b, 0.5)
    o.location = g2b((m_.x, h, m_.z))
    o.rotation_euler = (0, math.pi / 2, math.atan2(-d.z, d.x))
    o.data.materials.append(rope)
    if not (len(l) > 5 and int(l[5]) == 0):
        lt = bpy.data.objects.new("lan", bpy.data.lights.new("lan", "POINT"))
        lt.data.energy = float(os.environ.get("LAN_W", "220"))
        lt.data.color = (1.0, 0.55, 0.25)
        m = a.lerp(b, 0.5)
        lt.location = g2b((m.x, h - 0.8, m.z))
        sc.collection.objects.link(lt)

cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
sc.collection.objects.link(cam)
sc.camera = cam
for s in SHOTS:
    parts = s.split(":")
    name = parts[0]
    e = [float(v) for v in parts[1].split(",")]
    t = [float(v) for v in parts[2].split(",")]
    cam.data.lens = float(parts[3]) if len(parts) > 3 else 24
    cam.location = g2b(e)
    cam.rotation_euler = (g2b(t) - g2b(e)).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(OUT, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("shot", name)
