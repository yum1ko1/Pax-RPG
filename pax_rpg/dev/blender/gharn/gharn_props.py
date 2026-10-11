"""Простые и модульные модели Гхарна — процедурно (Blender 4.2+/5.x, фоново: blender -b -P gharn_props.py).
По листам концепт-арта (Obsidian: Гхарн — промпты концепт-арта, «Листы объектов»): бочки, ящики, мешки,
фонари, дороги, кладка, ступени, частокол, юрты, туги и знамёна, быт, шаманские вещи.
Каждая модель — один меш (несколько материалов), пивот — центр основания, метры; экспорт glb (Y-вверх) в
W\\gharn\\props\\<id>.glb; лист-превью — W\\gharn\\props\\_sheet.png (+ _sheet_close.png).
    blender -b -P gharn_props.py -- [--only id1,id2] [--no-render]
"""
import math
import os
import random
import sys

import bmesh
import bpy
from mathutils import Vector

OUT = r"C:\Users\mbkli\Desktop\pax_rpg_work\gharn\props"
ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
ONLY = set(ARGS[ARGS.index("--only") + 1].split(",")) if "--only" in ARGS else None
random.seed(7)

# ---------------------------------------------------------------- материалы (палитра Гхарна)


def lin(h):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    return [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]


MATS = {}
LAST = [None]                      # последний созданный объект (для rock() внутри циклов)


def mat(name, color, rough=0.85, metal=0.0, emit=None, strength=4.0):
    if name in MATS:
        return MATS[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes.get("Principled BSDF")
    b.inputs["Base Color"].default_value = (*lin(color), 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*lin(emit), 1)
        b.inputs["Emission Strength"].default_value = strength
    m.diffuse_color = (*lin(emit or color), 1)
    MATS[name] = m
    return m


WOOD = lambda: mat("wood_dark", "#3B2A22")
WOOD_L = lambda: mat("wood_light", "#7A5638")
WOOD_W = lambda: mat("wood_weathered", "#5E4A3A")
IRON = lambda: mat("iron", "#26262A", 0.5, 0.9)
RED = lambda: mat("lacquer_red", "#B3262E", 0.45)
STONE = lambda: mat("stone_grey", "#7E7A73", 0.95)
STONE_D = lambda: mat("stone_dark", "#5B5853", 0.95)
STONE_C = lambda: mat("stone_cut", "#8C877D", 0.9)
EARTH = lambda: mat("earth_ochre", "#9A7448", 1.0)
GROUT = lambda: mat("earth_grout", "#6E5536", 1.0)
FELT = lambda: mat("felt_white", "#E8DFCC", 0.95)
FELT_G = lambda: mat("felt_grey", "#9C958A", 0.95)
LEATHER = lambda: mat("leather", "#5A2E22", 0.7)
HIDE = lambda: mat("hide", "#8A6A4A", 0.8)
BURLAP = lambda: mat("burlap", "#B59A6A", 1.0)
WICKER = lambda: mat("wicker", "#A8844E", 0.9)
ROPE = lambda: mat("rope", "#8B7350", 0.95)
GOLD = lambda: mat("gold_trophy", "#D8A93A", 0.3, 1.0)
BLACK = lambda: mat("cloth_black", "#141214", 0.9)
PAPER = lambda: mat("paper_lantern", "#C8352C", 0.6, 0, "#FF5A2A", 3.0)
FLAME = lambda: mat("flame_light", "#FFB45A", 0.5, 0, "#FFA040", 6.0)
MANA = lambda: mat("mana_crystal", "#FF7FC0", 0.2, 0, "#FF5FB0", 5.0)
MANA_CLOTH = lambda: mat("mana_cloth", "#D85AA8", 0.8, 0, "#FF6FC0", 1.5)
TEAL = lambda: mat("cloth_teal", "#3FA7A0", 0.9)
YELLOW = lambda: mat("cloth_yellow", "#D9A93A", 0.9)
BONE = lambda: mat("bone", "#D9CDB2", 0.7)
HAIR = lambda: mat("horsehair", "#1E1A18", 0.9)

# ---------------------------------------------------------------- геометрия


def new_obj(name, bm, material):
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    ob.data.materials.append(material)
    LAST[0] = ob
    return ob


def box(size, loc=(0, 0, 0), material=None, rot=(0, 0, 0), bevel=0.0, jitter=0.0, name="box"):
    """Брусок: size (x, y, z), loc — центр."""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    for v in bm.verts:
        v.co = Vector((v.co.x * size[0], v.co.y * size[1], v.co.z * size[2]))
        if jitter:
            v.co += Vector((random.uniform(-jitter, jitter) for _ in range(3)))
    if bevel:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=1, affect="EDGES")
    ob = new_obj(name, bm, material or WOOD())
    ob.location = loc
    ob.rotation_euler = rot
    return ob


def lathe(profile, loc=(0, 0, 0), material=None, seg=16, cap_top=True, cap_bot=True, name="lathe", rot=(0, 0, 0)):
    """Тело вращения: profile — [(радиус, высота)] снизу вверх."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        ring = [bm.verts.new((r * math.cos(2 * math.pi * i / seg), r * math.sin(2 * math.pi * i / seg), z))
                for i in range(seg)]
        rings.append(ring)
    for a, b in zip(rings, rings[1:]):
        for i in range(seg):
            j = (i + 1) % seg
            bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap_bot and profile[0][0] > 1e-4:
        bm.faces.new(list(reversed(rings[0])))
    if cap_top and profile[-1][0] > 1e-4:
        bm.faces.new(rings[-1])
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    ob = new_obj(name, bm, material or WOOD())
    ob.location = loc
    ob.rotation_euler = rot
    return ob


def cyl(r, h, loc=(0, 0, 0), material=None, seg=12, rot=(0, 0, 0), r2=None, name="cyl"):
    """Цилиндр (или конус, r2) от основания loc вверх на h (до поворота)."""
    return lathe([(r, 0), (r if r2 is None else r2, h)], loc, material, seg, rot=rot, name=name)


def rock(size, loc, material=None, rot_z=None, jitter=0.18):
    s = [x * random.uniform(0.85, 1.15) for x in size]
    return box(s, loc, material or STONE(), (0, 0, rot_z if rot_z is not None else random.uniform(-0.15, 0.15)),
               bevel=min(s) * 0.12, jitter=min(s) * jitter, name="rock")


def join(name, parts):
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    ob.name = name
    ob.data.name = name
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    # пивот — центр основания
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    bpy.ops.object.shade_flat()
    return ob

# ---------------------------------------------------------------- модели


def barrel(kind):
    h, r = (1.0, 0.42) if kind == "kumis" else (0.9, 0.38)
    prof = [(r * (0.86 + 0.14 * math.sin(math.pi * t / 8)), h * t / 8) for t in range(9)]
    p = [lathe(prof, material=WOOD_W() if kind == "water" else WOOD(), seg=18)]
    for t in (0.12, 0.5, 0.88):
        rr = r * (0.86 + 0.14 * math.sin(math.pi * t)) + 0.012
        p.append(cyl(rr, 0.05, (0, 0, h * t - 0.025), IRON(), 18))
    if kind == "kumis":
        p.append(lathe([(r * 0.9, h), (r * 0.95, h + 0.04), (r * 0.6, h + 0.07), (0.0, h + 0.075)], material=LEATHER(), seg=18))
        p.append(cyl(r * 0.88, 0.03, (0, 0, h - 0.06), ROPE(), 18))
    else:
        p.append(cyl(r * 0.84, 0.03, (0, 0, h - 0.02), WOOD_L(), 18))
        p.append(box((0.5, 0.06, 0.04), (0, 0, h + 0.03), WOOD_L()))
    return p


def crate(saerith=False):
    s = 0.8
    p = [box((s - 0.06, s - 0.06, s - 0.06), (0, 0, s / 2), WOOD_L(), bevel=0.01)]
    for x in (-1, 1):
        for y in (-1, 1):
            p.append(box((0.08, 0.08, s), (x * (s / 2 - 0.04), y * (s / 2 - 0.04), s / 2), WOOD()))
    for z in (0.04, s - 0.04):
        for y in (-1, 1):
            p.append(box((s, 0.08, 0.08), (0, y * (s / 2 - 0.04), z), WOOD()))
        for x in (-1, 1):
            p.append(box((0.08, s, 0.08), (x * (s / 2 - 0.04), 0, z), WOOD()))
    if saerith:  # трофейный ящик Саэрита: золотой диск с драконом
        p.append(cyl(0.2, 0.02, (0, -s / 2 - 0.0, s / 2), GOLD(), 20, rot=(math.pi / 2, 0, 0)))
        p.append(box((0.22, 0.03, 0.06), (0, -s / 2 - 0.025, s / 2), RED(), rot=(0, 0.6, 0)))
    return p


def sack():
    prof = [(0.0, 0), (0.24, 0.02), (0.30, 0.15), (0.28, 0.38), (0.16, 0.52), (0.07, 0.58), (0.09, 0.66), (0.0, 0.68)]
    p = [lathe(prof, material=BURLAP(), seg=12)]
    p.append(cyl(0.08, 0.04, (0, 0, 0.56), ROPE(), 10))
    return p


def basket():
    prof = [(0.18, 0), (0.22, 0.05), (0.27, 0.32), (0.25, 0.32), (0.20, 0.06), (0.0, 0.06)]
    return [lathe(prof, material=WICKER(), seg=16, cap_top=False), cyl(0.28, 0.03, (0, 0, 0.3), WOOD_L(), 16)]


def lantern_post():
    p = [box((0.22, 0.22, 3.3), (0, 0, 1.65), WOOD(), bevel=0.015), box((0.5, 0.5, 0.25), (0, 0, 0.125), STONE(), bevel=0.04)]
    p.append(box((0.9, 0.12, 0.12), (0.45, 0, 3.05), WOOD()))                    # кронштейн
    p.append(box((0.5, 0.08, 0.08), (0.25, 0, 2.8), WOOD(), rot=(0, math.radians(-42), 0)))
    p.append(cyl(0.02, 0.35, (0.82, 0, 2.65), ROPE(), 6))                           # подвес
    p.append(lathe([(0.0, 2.05), (0.17, 2.1), (0.22, 2.3), (0.22, 2.5), (0.17, 2.65), (0.0, 2.68)], material=PAPER(), seg=12,
                   loc=(0.82, 0, 0)))
    p.append(cyl(0.2, 0.04, (0.82, 0, 2.03), BLACK(), 12))
    p.append(cyl(0.18, 0.04, (0.82, 0, 2.66), BLACK(), 12))
    p.append(lathe([(0.26, 3.17), (0.0, 3.4)], material=IRON(), seg=4, loc=(0, 0, 0)))  # шип на столбе
    return p


def stone_lantern():
    p = [box((0.9, 0.9, 0.25), (0, 0, 0.125), STONE_D(), bevel=0.04, jitter=0.02),
         lathe([(0.22, 0.25), (0.18, 0.9), (0.24, 1.0)], material=STONE(), seg=8),
         box((0.75, 0.75, 0.15), (0, 0, 1.07), STONE(), bevel=0.03, jitter=0.015)]
    for a in range(4):                                     # столбики светового короба
        x, y = (0.24 if a % 2 else -0.24), (0.24 if a < 2 else -0.24)
        p.append(box((0.12, 0.12, 0.42), (x, y, 1.35), STONE()))
    p.append(box((0.38, 0.38, 0.34), (0, 0, 1.35), FLAME()))
    p.append(lathe([(0.0, 1.56), (0.62, 1.58), (0.55, 1.68), (0.2, 1.82), (0.08, 1.95), (0.0, 2.02)], material=STONE_D(), seg=4,
                   rot=(0, 0, math.pi / 4)))
    return p


def lantern_string(length=6.0):
    p = []
    n = 14
    pts = [Vector((-length / 2 + length * i / n, 0, 4.2 - 0.6 * math.sin(math.pi * i / n))) for i in range(n + 1)]
    for a, b in zip(pts, pts[1:]):
        d = b - a
        c = cyl(0.015, d.length, a, ROPE(), 5)
        c.rotation_euler = (0, math.atan2(d.x, d.z), 0)
        p.append(c)
    for i in (2, 5, 8, 11):
        x, z = pts[i].x, pts[i].z
        p.append(lathe([(0.0, z - 0.42), (0.11, z - 0.38), (0.14, z - 0.25), (0.11, z - 0.12), (0.0, z - 0.08)],
                       material=PAPER(), seg=10, loc=(x, 0, 0)))
        p.append(cyl(0.01, 0.1, (x, 0, z - 0.1), ROPE(), 4))
    for e in (-length / 2, length / 2):                    # опорные шесты
        p.append(cyl(0.07, 4.3, (e, 0, 0), WOOD(), 8))
    return p


def road_cobble():
    p = [box((4, 4, 0.1), (0, 0, -0.05), GROUT())]
    y = -2.0
    while y < 1.95:
        h = random.uniform(0.45, 0.7)
        x = -2.0 + random.uniform(0, 0.3)
        while x < 1.95:
            w = random.uniform(0.5, 0.9)
            w = min(w, 2.0 - x)
            if w > 0.15 and h > 0.1:
                hh = min(h, 2.0 - y)
                rock((w - 0.06, hh - 0.06, 0.12), (x + w / 2, y + hh / 2, 0.02), random.choice([STONE(), STONE_C(), STONE_D()]),
                     rot_z=random.uniform(-0.04, 0.04), jitter=0.08)
                p.append(LAST[0])
            x += w
        y += h
    return p


def road_dirt():
    bm = bmesh.new()
    bmesh.ops.create_grid(bm, x_segments=16, y_segments=16, size=2.0)
    for v in bm.verts:
        rut = -0.05 * math.exp(-((abs(v.co.x) - 0.7) ** 2) / 0.02)     # две колеи от телег
        v.co.z = rut + random.uniform(-0.015, 0.015)
    ob = new_obj("dirt", bm, EARTH())
    p = [ob]
    for _ in range(10):                                                 # камешки и солома
        rock((0.08, 0.06, 0.04), (random.uniform(-1.9, 1.9), random.uniform(-1.9, 1.9), 0.0), STONE_D())
        p.append(LAST[0])
    return p


def boardwalk():
    p = []
    for i in range(10):
        x = -1.9 + i * 0.42
        p.append(box((0.38, 1.5, 0.06), (x, 0, 0.2 + random.uniform(-0.005, 0.005)), random.choice([WOOD(), WOOD_W()]),
                     rot=(0, 0, random.uniform(-0.01, 0.01))))
    for y in (-0.6, 0.6):
        p.append(box((4.1, 0.12, 0.17), (0, y, 0.085), WOOD()))
    return p


def wall_rubble(length=4.0, height=2.0, depth=0.8):
    p = []
    z = 0.0
    row = 0
    while z < height - 0.05:
        h = random.uniform(0.28, 0.42) * (1.25 if row == 0 else 1.0)
        h = min(h, height - z)
        x = -length / 2 + (0.2 if row % 2 else 0)
        while x < length / 2 - 0.05:
            w = min(random.uniform(0.45, 0.8), length / 2 - x)
            rock((w - 0.03, depth * random.uniform(0.9, 1.0), h - 0.03), (x + w / 2, 0, z + h / 2),
                 random.choice([STONE(), STONE_D()]), jitter=0.12)
            p.append(LAST[0])
            x += w
        z += h
        row += 1
    p.append(box((length, depth * 0.85, height * 0.98), (0, 0, height * 0.49), GROUT()))   # глина в швах
    return p


def wall_hob(length=4.0, height=2.0, depth=0.6):
    p = []
    rows = 5
    h = height / rows
    for r in range(rows):
        off = 0.3 if r % 2 else 0.0
        n = 4
        w = length / n
        for i in range(-1, n):
            x0 = -length / 2 + off + i * w
            x1 = min(x0 + w, length / 2)
            x0 = max(x0, -length / 2)
            if x1 - x0 < 0.05:
                continue
            p.append(box((x1 - x0 - 0.02, depth, h - 0.02), ((x0 + x1) / 2, 0, r * h + h / 2), STONE_C(), bevel=0.012))
    p.append(box((length + 0.1, depth + 0.1, 0.12), (0, 0, height + 0.06), STONE_D(), bevel=0.02))   # карниз
    p.append(box((0.3, 0.05, 0.22), (0, -depth / 2 - 0.02, height * 0.6), IRON()))                     # номерная табличка
    return p


def stairs_stone(width=3.0, steps=5):
    p = []
    for i in range(steps):
        p.append(rock((width, 0.42, 0.22), (0, i * 0.4, 0.11 + i * 0.22), random.choice([STONE(), STONE_D()]), rot_z=0.0, jitter=0.06))
        p.append(box((width - 0.1, 0.4, 0.22 * (i + 1)), (0, i * 0.4, 0.11 * (i + 1)), GROUT()))
    return p


def palisade(length=4.0):
    p = []
    n = 10
    for i in range(n):
        x = -length / 2 + (i + 0.5) * length / n
        h = random.uniform(3.4, 4.0)
        r = random.uniform(0.17, 0.21)
        p.append(cyl(r, h, (x, 0, 0), WOOD_W() if i % 3 else WOOD(), 8))
        p.append(cyl(r, 0.5, (x, 0, h), WOOD_L(), 8, r2=0.0))
    for z in (1.0, 2.6):
        p.append(box((length, 0.14, 0.18), (0, 0.22, z), WOOD()))
    p.append(box((length + 0.2, 1.4, 0.6), (0, 0, 0.0), STONE_D(), bevel=0.1, jitter=0.05))
    return p


def yurt(r=2.5, kind="small"):
    h = 1.6 if kind == "small" else 2.1
    felt = FELT() if kind == "large" else FELT_G()
    p = [lathe([(r, 0), (r, h)], material=felt, seg=24, cap_top=False, cap_bot=False)]
    p.append(lathe([(r + 0.12, h), (r * 0.55, h + r * 0.38), (r * 0.18, h + r * 0.5), (0.0, h + r * 0.5)], material=felt, seg=24))
    p.append(cyl(r * 0.2, 0.18, (0, 0, h + r * 0.48), WOOD(), 16))                                  # тоно
    for z in (0.35, h - 0.25):
        p.append(cyl(r + 0.02, 0.06, (0, 0, z), ROPE(), 24))
    p.append(box((1.0 if kind == "small" else 1.2, 0.16, 1.5), (0, -r - 0.02, 0.75), RED()))       # дверь
    p.append(box((1.25 if kind == "small" else 1.45, 0.2, 0.14), (0, -r - 0.02, 1.55), WOOD()))
    for x in (-1, 1):
        p.append(box((0.12, 0.2, 1.6), (x * (0.56 if kind == "small" else 0.66), -r - 0.02, 0.8), WOOD()))
    p.append(cyl(r + 0.05, 0.12, (0, 0, 0), WOOD_W(), 24))
    if kind == "large":                                                                               # узор-клык на войлоке
        for a in range(6):
            ang = a * math.pi / 3 + 0.5
            p.append(box((0.5, 0.03, 0.25), (math.cos(ang) * (r + 0.01), math.sin(ang) * (r + 0.01), h * 0.62), RED(),
                         rot=(0, 0, ang + math.pi / 2)))
    return p


def tug_banner():
    p = [cyl(0.06, 4.2, (0, 0, 0), WOOD(), 8), cyl(0.25, 0.06, (0, 0, 3.8), IRON(), 12)]
    p.append(lathe([(0.0, 4.2), (0.09, 4.3), (0.0, 4.75)], material=IRON(), seg=6))                  # наконечник
    for i in range(9):
        a = i * 2 * math.pi / 9
        c = cyl(0.05, 1.1, (math.cos(a) * 0.17, math.sin(a) * 0.17, 2.75), HAIR(), 5, r2=0.01)
        p.append(c)
    p.append(box((0.4, 0.4, 0.3), (0, 0, 0.15), STONE(), bevel=0.04))
    return p


def banner_clan():
    p = [cyl(0.06, 5.0, (0, 0, 0), WOOD(), 8), box((1.4, 0.06, 0.06), (0, 0, 4.75), WOOD())]
    p.append(box((1.2, 0.02, 2.6), (0, 0.05, 3.4), RED()))
    p.append(box((0.18, 0.025, 1.0), (0.05, 0.035, 3.6), BLACK(), rot=(0, 0.35, 0)))                 # клык — эмблема Гхарна
    p.append(box((0.12, 0.025, 0.5), (-0.1, 0.035, 3.1), BLACK(), rot=(0, -0.5, 0)))
    for x in (-0.55, 0.55):
        p.append(cyl(0.04, 0.3, (x, 0.05, 1.8), HAIR(), 5, r2=0.0, rot=(math.pi, 0, 0)))
    p.append(lathe([(0.0, 5.0), (0.07, 5.08), (0.0, 5.4)], material=IRON(), seg=6))
    return p


def hitching_post():
    return [box((0.18, 0.18, 1.2), (x, 0, 0.6), WOOD(), bevel=0.02) for x in (-1.2, 1.2)] + \
           [box((2.8, 0.14, 0.14), (0, 0, 1.05), WOOD_W()), cyl(0.12, 0.05, (-1.2, 0, 1.2), IRON(), 8)]


def trough():
    return [box((2.0, 0.6, 0.1), (0, 0, 0.35), WOOD_W()), box((2.0, 0.08, 0.4), (0, 0.26, 0.5), WOOD_W()),
            box((2.0, 0.08, 0.4), (0, -0.26, 0.5), WOOD_W()), box((0.08, 0.6, 0.4), (0.96, 0, 0.5), WOOD_W()),
            box((0.08, 0.6, 0.4), (-0.96, 0, 0.5), WOOD_W()), box((0.15, 0.7, 0.3), (0.7, 0, 0.15), WOOD()),
            box((0.15, 0.7, 0.3), (-0.7, 0, 0.15), WOOD()), box((1.84, 0.44, 0.02), (0, 0, 0.62), mat("water", "#3C6E8C", 0.1))]


def bench_long():
    return [box((2.4, 0.4, 0.08), (0, 0, 0.55), WOOD_W(), bevel=0.01)] + \
           [box((0.1, 0.36, 0.51), (x, 0, 0.255), WOOD()) for x in (-1.0, 1.0)]


def table_long():
    return [box((2.8, 0.95, 0.09), (0, 0, 0.95), WOOD_W(), bevel=0.01)] + \
           [box((0.14, 0.14, 0.9), (x, y, 0.45), WOOD()) for x in (-1.2, 1.2) for y in (-0.35, 0.35)] + \
           [box((2.4, 0.1, 0.1), (0, 0, 0.3), WOOD())]


def weapon_rack():
    p = [box((1.8, 0.4, 0.1), (0, 0, 0.05), WOOD()), box((0.1, 0.1, 1.7), (-0.85, 0, 0.85), WOOD()),
         box((0.1, 0.1, 1.7), (0.85, 0, 0.85), WOOD()), box((1.8, 0.12, 0.1), (0, 0, 1.45), WOOD())]
    for i in range(5):
        x = -0.6 + i * 0.3
        p.append(cyl(0.025, 1.9, (x, 0.08, 0.05), WOOD_L(), 6, rot=(0.08, 0, 0)))
        p.append(lathe([(0.0, 1.95), (0.05, 2.0), (0.0, 2.25)], material=IRON(), seg=4, loc=(x, 0.0, 0.0)))
    return p


def training_dummy():
    p = [cyl(0.09, 1.9, (0, 0, 0), WOOD(), 8), box((1.0, 0.12, 0.12), (0, 0, 1.45), WOOD())]
    p.append(lathe([(0.0, 0.85), (0.26, 0.9), (0.3, 1.2), (0.28, 1.55), (0.0, 1.62)], material=BURLAP(), seg=10))
    p.append(lathe([(0.0, 1.6), (0.17, 1.65), (0.18, 1.8), (0.0, 1.95)], material=BURLAP(), seg=10))
    p.append(cyl(0.3, 0.05, (0, 0, 1.25), ROPE(), 10))
    p.append(box((0.6, 0.6, 0.12), (0, 0, 0.06), WOOD_W()))
    return p


def cauldron():
    p = [lathe([(0.0, 0.35), (0.35, 0.4), (0.48, 0.6), (0.45, 0.85), (0.42, 0.88), (0.38, 0.85), (0.0, 0.8)], material=IRON(), seg=16)]
    for a in range(3):
        ang = a * 2 * math.pi / 3
        c = cyl(0.04, 2.0, (math.cos(ang) * 0.75, math.sin(ang) * 0.75, 0), WOOD(), 6)
        c.rotation_euler = (math.sin(ang) * 0.36, -math.cos(ang) * 0.36, 0)
        p.append(c)
    p.append(cyl(0.01, 0.9, (0, 0, 0.9), IRON(), 4))
    for i in range(7):                                                  # костёр
        a = i * 2 * math.pi / 7
        rock((0.18, 0.14, 0.12), (math.cos(a) * 0.55, math.sin(a) * 0.55, 0.06), STONE_D())
        p.append(LAST[0])
    p.append(lathe([(0.25, 0.02), (0.0, 0.32)], material=FLAME(), seg=6))
    return p


def ovoo_cairn():
    p = []
    z = 0.0
    for i, s in enumerate([0.9, 0.75, 0.6, 0.45, 0.32]):
        rock((s, s * 0.9, 0.3), (random.uniform(-0.04, 0.04), random.uniform(-0.04, 0.04), z + 0.15), STONE())
        p.append(LAST[0])
        z += 0.27
    p.append(cyl(0.035, 1.4, (0, 0, z - 0.1), WOOD(), 6))
    for i, m in enumerate([TEAL(), RED(), YELLOW(), MANA_CLOTH()]):
        p.append(box((0.06, 0.02, 0.5), (0.05 * (i - 1.5), 0.03, z + 0.8), m, rot=(0.25, 0.3 * (i - 1.5), 0)))
    return p


def mana_crystal():
    p = [rock((0.6, 0.5, 0.2), (0, 0, 0.1), STONE_D())]
    for i in range(6):
        a = i * 2 * math.pi / 6 + random.uniform(-0.3, 0.3)
        h = random.uniform(0.35, 0.9)
        c = lathe([(0.08, 0.0), (0.09, h * 0.75), (0.0, h)], material=MANA(), seg=6,
                  loc=(math.cos(a) * 0.12, math.sin(a) * 0.12, 0.12))
        c.rotation_euler = (math.sin(a) * 0.4, -math.cos(a) * 0.4, 0)
        p.append(c)
    return p


def mana_flags_line(length=5.0):
    p = [cyl(0.05, 3.0, (x, 0, 0), WOOD(), 6) for x in (-length / 2, length / 2)]
    rope = cyl(0.012, length, (-length / 2, 0, 2.8), ROPE(), 5, rot=(0, math.pi / 2, 0))
    p.append(rope)
    for i in range(9):
        x = -length / 2 + (i + 1) * length / 10
        m = MANA_CLOTH() if i % 2 == 0 else random.choice([TEAL(), YELLOW(), RED()])
        p.append(box((0.3, 0.015, 0.4), (x, 0, 2.58), m, rot=(0, 0, random.uniform(-0.1, 0.1))))
    return p


def stall_frame():
    p = [box((2.6, 1.2, 0.9), (0, 0, 0.45), WOOD_W(), bevel=0.02), box((2.7, 1.3, 0.06), (0, 0, 0.93), WOOD())]
    for x in (-1.3, 1.3):
        for y in (-0.6, 0.6):
            p.append(cyl(0.05, 2.4 if y < 0 else 2.1, (x, y, 0), WOOD(), 6))
    awn = box((3.0, 1.7, 0.03), (0, 0, 2.25), random.choice([TEAL(), YELLOW(), RED()]), rot=(math.radians(-10), 0, 0))
    p.append(awn)
    for i in range(6):                                                  # товар
        rock((0.25, 0.2, 0.15), (-1.0 + i * 0.4, random.uniform(-0.3, 0.3), 1.03), random.choice([GOLD(), BURLAP(), HIDE()]))
        p.append(LAST[0])
    return p


def quest_board():
    p = [box((0.2, 0.2, 2.6), (x, 0, 1.3), WOOD()) for x in (-1.2, 1.2)]
    p.append(box((2.4, 0.1, 1.4), (0, 0, 1.6), WOOD_W(), bevel=0.01))
    p.append(lathe([(1.6, 2.45), (0.0, 2.75)], material=WOOD(), seg=4, rot=(0, 0, math.pi / 4)))
    for i in range(9):                                                  # листки заказов и ножи
        x, z = random.uniform(-1.0, 1.0), random.uniform(1.0, 2.2)
        p.append(box((0.28, 0.01, 0.36), (x, -0.06, z), mat("paper", "#E6D8B8", 0.9), rot=(0, random.uniform(-0.15, 0.15), 0)))
        if i % 3 == 0:
            p.append(box((0.03, 0.18, 0.03), (x, -0.13, z + 0.12), IRON()))
    return p


PROPS = {
    "barrel_kumis": lambda: barrel("kumis"), "barrel_water": lambda: barrel("water"),
    "crate": lambda: crate(False), "crate_saerith": lambda: crate(True),
    "sack_grain": sack, "basket": basket,
    "lantern_post": lantern_post, "stone_lantern": stone_lantern, "lantern_string": lantern_string,
    "road_cobble": road_cobble, "road_dirt": road_dirt, "boardwalk": boardwalk,
    "wall_rubble": wall_rubble, "wall_hob": wall_hob, "stairs_stone": stairs_stone,
    "palisade_segment": palisade,
    "yurt_small": lambda: yurt(2.5, "small"), "yurt_large": lambda: yurt(4.0, "large"),
    "tug_banner": tug_banner, "banner_clan": banner_clan,
    "hitching_post": hitching_post, "trough": trough, "bench_long": bench_long, "table_long": table_long,
    "weapon_rack": weapon_rack, "training_dummy": training_dummy, "cauldron": cauldron,
    "ovoo_cairn": ovoo_cairn, "mana_crystal": mana_crystal, "mana_flags_line": mana_flags_line,
    "stall_frame": stall_frame, "quest_board": quest_board,
}

# ---------------------------------------------------------------- сборка, экспорт, превью


def main():
    os.makedirs(OUT, exist_ok=True)
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    built = []
    for pid, fn in PROPS.items():
        if ONLY and pid not in ONLY:
            continue
        random.seed(hash(pid) & 0xffff)
        parts = fn()
        ob = join(pid, parts)
        bpy.ops.object.select_all(action="DESELECT")
        ob.select_set(True)
        bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, pid + ".glb"), use_selection=True, export_yup=True,
                                  export_apply=True, export_animations=False)
        tris = sum(len(p.vertices) - 2 for p in ob.data.polygons)
        dims = ob.dimensions
        print(f"{pid}: {tris} tris, {dims.x:.2f} x {dims.y:.2f} x {dims.z:.2f} m", flush=True)
        built.append(ob)
    if "--no-render" in ARGS:
        return
    # лист-превью: сетка, подписи
    cols = 8
    cell = 7.0
    for i, ob in enumerate(built):
        ob.location = ((i % cols) * cell, -(i // cols) * cell, 0)
        bpy.ops.object.text_add(location=(ob.location.x - 2.6, ob.location.y - 3.2, 0.02))
        t = bpy.context.active_object
        t.data.body = ob.name
        t.data.size = 0.55
        t.data.materials.append(mat("label", "#FFFFFF"))
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "MATERIAL"
    sc.display.shading.show_shadows = True
    sc.display.shading.show_cavity = True
    sc.render.resolution_x, sc.render.resolution_y = 2400, 1500
    w = bpy.data.worlds.new("w") if not sc.world else sc.world
    sc.world = w
    rows = (len(built) + cols - 1) // cols
    cx, cy = (cols - 1) * cell / 2, -(rows - 1) * cell / 2
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = cols * cell * 1.02
    cam.location = (cx, cy - 40, 34)
    cam.rotation_euler = (math.radians(50), 0, 0)
    sc.render.filepath = os.path.join(OUT, "_sheet.png")
    bpy.ops.render.render(write_still=True)
    print("sheet:", sc.render.filepath, flush=True)


main()
