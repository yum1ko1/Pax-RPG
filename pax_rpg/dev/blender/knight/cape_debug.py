"""Отладка плаща без игры: повторяет hero.gd (_wear_cape + _cape_targets) — где ткань должна лежать в позе клипа.
Рыцарь в кадре клипа + сетка целей плаща (до физики): сбоку и сзади, для нескольких клипов и с/без «свисания».
    blender -b -P cape_debug.py -- <knight.glb> <cape_black.json> <items.json> <папка кадров>
"""
import json
import math
import os
import sys

import bpy
from mathutils import Matrix, Vector

A = sys.argv[sys.argv.index("--") + 1:]
KNIGHT, GRID, ITEMS, OUT = A[0], A[1], A[2], A[3]
os.makedirs(OUT, exist_ok=True)
CLIPS = [("Idle", 0.5), ("IdleArmed", 0.5), ("CombatIdle", 0.5), ("WalkArmed", 0.3)]
TOPS = A[4].split(",") if len(A) > 4 else []
G2B = Matrix(((1, 0, 0), (0, 0, -1), (0, 1, 0)))          # glTF (Y вверх) → Blender (Z вверх)

for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=KNIGHT)
rig = [o for o in bpy.context.scene.objects if o.type == "ARMATURE"][0]
for o in bpy.context.scene.objects:
    if o.name.startswith("Sword_Drag"):
        o.hide_render = True
it = json.load(open(ITEMS, encoding="utf-8"))["items"]["cape_black"] if "items" in json.load(open(ITEMS, encoding="utf-8")) \
    else json.load(open(ITEMS, encoding="utf-8"))["cape_black"]
g = json.load(open(GRID))
nx, nz = g["nx"], g["nz"]
rest0 = [G2B @ Vector(p) for p in g["points"]]


def bone(name, pose=True):
    b = rig.pose.bones[name] if pose else rig.data.bones[name]
    return rig.matrix_world @ (b.matrix if pose else b.matrix_local)


def delta(name):
    return bone(name) @ bone(name, False).inverted()


def targets(hang, top=None):
    rest = [p.copy() for p in rest0]
    lift = it.get("lift", [0, 0, 0])
    lv = G2B @ Vector(lift)
    rest = [p + lv for p in rest]
    half0 = max(0.1, max(abs(rest[i].x) for i in range(nx)))
    cl = it.get("collar", [0.075, 0.035, 0.11])
    if os.environ.get("NOCOLLAR"):
        cl = None
    nk = bone("neck", False).translation                   # шея в покое (как hero.gd — rest)
    for i in range(nx if cl else 0):
        u = rest[i].x / half0
        w = 1.0 - smooth(0.35, 0.9, abs(u))
        want = Vector((nk.x + u * cl[2], nk.y + cl[0], nk.z - cl[1]))   # назад (−Z glTF = +Y Blender), вниз
        dd = (want - rest[i]) * w
        for j in range(4):
            rest[j * nx + i] += dd * (1.0 - j / 4.0)
    half = max(0.1, max(abs(rest[i].x) for i in range(nx)))
    t_top, t_low = delta(top or it.get("top_bone", "Spine")), delta(it.get("low_bone", "Hips"))
    sb = it.get("side_bones", ["LeftShoulder", "RightShoulder"])
    t_l, t_r = delta(sb[0]), delta(sb[1])
    zl = t_low.to_3x3() @ Vector((0, -1, 0))               # «вперёд» glTF +Z = Blender −Y
    yaw = Matrix.Rotation(math.atan2(-zl.x, -zl.y), 3, "Z")
    out = []
    for k, p in enumerate(rest):
        row = (k // nx) / (nz - 1)
        wl = smooth(0.15, 0.9, row)
        u = p.x / half
        ws = smooth(0.3, 1.0, abs(u)) * (1.0 - smooth(0.0, 0.35, row))
        up = (t_top @ p).lerp((t_l if u > 0 else t_r) @ p, ws)
        r0 = rest[k % nx]
        hangp = (t_top @ r0) + yaw @ (p - r0)
        low = (t_low @ p).lerp(hangp, hang)
        out.append(up.lerp(low, wl))
    return out


def smooth(a, b, x):
    t = min(1.0, max(0.0, (x - a) / (b - a)))
    return t * t * (3 - 2 * t)


def grid_obj(pts, name, col):
    me = bpy.data.meshes.new(name)
    faces = [(j * nx + i, j * nx + i + 1, (j + 1) * nx + i + 1, (j + 1) * nx + i) for j in range(nz - 1) for i in range(nx - 1)]
    me.from_pydata([tuple(p) for p in pts], [], faces)
    ob = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(ob)
    m = bpy.data.materials.new(name)
    m.diffuse_color = col
    ob.data.materials.append(m)
    return ob


sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.color_type = "MATERIAL"
sc.render.resolution_x, sc.render.resolution_y = 520, 640
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
cam.data.type = "ORTHO"
cam.data.ortho_scale = 2.3
sc.collection.objects.link(cam)
sc.camera = cam
acts = {a.name.split("_")[0].split(".")[0]: a for a in bpy.data.actions}
for clip, frac in CLIPS:
    a = acts.get(clip)
    if a is None:
        print("no clip", clip)
        continue
    rig.animation_data.action = a
    if hasattr(rig.animation_data, "action_slot") and len(getattr(a, "slots", [])):
        rig.animation_data.action_slot = a.slots[0]
    f = a.frame_range[0] + (a.frame_range[1] - a.frame_range[0]) * frac
    sc.frame_set(int(f))
    bpy.context.view_layer.update()
    if TOPS:
        cols = [(1, 0.2, 0.2, 1), (0.2, 0.9, 0.3, 1), (0.2, 0.4, 1, 1)]
        obs = [grid_obj(targets(0.75, t), t, cols[i % 3]) for i, t in enumerate(TOPS)]
    else:
        obs = [grid_obj(targets(0.0), "old", (1, 0.2, 0.2, 1)), grid_obj(targets(float(it.get("hang", 0.75))), "new", (0.2, 0.9, 0.3, 1))]
    fz = delta("Hips").to_3x3() @ Vector((0, -1, 0))      # куда смотрит таз
    yaw0 = math.atan2(fz.x, -fz.y)
    hp = bone("Hips").translation
    for view, ang in [("side", yaw0 + math.radians(90)), ("back", yaw0 + math.radians(180))]:
        d = Vector((math.sin(ang), -math.cos(ang), 0.0))
        cam.location = Vector((hp.x, hp.y, 1.1)) + d * 2.6
        cam.rotation_euler = (math.radians(90), 0, ang)
        for ob in obs:
            ob.hide_render = False
        sc.render.filepath = os.path.join(OUT, f"cape_{clip}_{view}.png")
        bpy.ops.render.render(write_still=True)
    for ob in obs:
        bpy.data.objects.remove(ob, do_unlink=True)
print("done", flush=True)
