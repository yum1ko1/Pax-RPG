"""Проверочные кадры после refine_knight.py: <W>/shots/k2_*.png. Плащ: кадр cape — кости плаща откинуты назад
(видно, какие вершины на них перевешены)."""
import importlib
import json
import math
import sys

import bpy
from mathutils import Quaternion, Vector

UTIL = r"C:\Users\mbkli\AppData\Local\Programs\Pax Universe\pax_corporations_dev"
sys.path.insert(0, UTIL)
import pax_rpg_blender_util as U  # noqa: E402

importlib.reload(U)
U.DIRS["BACK34"] = Vector((-0.7, 0.7, 0.25))          # сзади справа (правая рука рыцаря — -X)
try:
    result
except NameError:
    result = {}
meta = json.load(open(r"C:\Users\mbkli\Desktop\pax_rpg_work\meshy\knight\knight_anim.json", encoding="utf-8"))
scn = bpy.data.scenes["Knight"]
win = bpy.context.window or bpy.context.window_manager.windows[0]
win.scene = scn
rig = bpy.data.objects["Knight_rig"]
sw = {n: bpy.data.objects[n] for n in ("Sword_Back", "Sword_Hand", "Sword_Drag")}
SHOTS = [("Draw", f, "BACK34") for f in (13, 20, 28, 36, 44, 54)] + \
        [("DrawWalk", f, "FRONT34") for f in (0, 20, 36, 54)] + \
        [("RunArmed", t, "RIGHT") for t in (0.0, 0.25, 0.5, 0.75)] + [("Run", 0.3, "BACK")]
files = []


def show(which):
    for n, o in sw.items():
        o.hide_set(n != which)


for clip, t, view in SHOTS:
    a = bpy.data.actions["K_" + clip]
    rig.animation_data.action = a
    rig.animation_data.action_slot = a.slots[0]
    f0, f1 = a.frame_range
    if t == "impact":
        f = int(round(f0 + meta["impact"]["Attack3"] * 30))
    elif isinstance(t, int):
        f = int(f0 + t)
    else:
        f = int(round(f0 + (f1 - f0) * t))
    sw_t = (f - f0) / 30
    if clip == "RunArmed":
        show("Sword_Drag")
    elif clip in ("Run", "Idle"):
        show("Sword_Back")
    elif clip.startswith("Sheathe"):
        show("Sword_Hand" if sw_t < meta["sword_switch"]["Sheathe"]["time"] else "Sword_Back")
    elif clip.startswith("Draw"):
        show("Sword_Hand" if sw_t >= meta["sword_switch"]["Draw"]["time"] else "Sword_Back")
    else:
        show("Sword_Hand")
    scn.frame_set(f)
    files += U.shot(f"k2_{clip.lower()}_{f:03d}", (0, -0.2, 1.0), 3.0, (view,), res=450)
# плащ: откинуть цепочки назад
rig.animation_data.action = None
pb = rig.pose.bones
for p in pb:
    p.rotation_quaternion = (1, 0, 0, 0)
    p.location = (0, 0, 0)
for p in pb:
    if p.name.startswith("Cape_") and p.name.endswith("_0"):
        p.rotation_quaternion = Quaternion(Vector((1, 0, 0)), math.radians(40))
show("Sword_Back")
bpy.context.view_layer.update()
files += U.shot("k2_cape_test", (0, 0, 1.0), 3.0, ("RIGHT", "BACK"), res=450)
files += U.shot("k2_cape_low", (0, 0, 0.35), 1.2, ("RIGHT", "BACK", "LEFT"), res=450)
for p in pb:
    p.rotation_quaternion = (1, 0, 0, 0)
result["files"] = [p.split("\\")[-1] for p in files]
