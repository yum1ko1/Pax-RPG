"""Тело рыцаря без плаща и меча (после refine_knight.py): <W>/shots/body_*.png — видно, не осталось ли дыр там, где
срезан плащ и ворот капюшона."""
import importlib
import sys

import bpy

UTIL = r"C:\Users\mbkli\AppData\Local\Programs\Pax Universe\pax_corporations_dev"
sys.path.insert(0, UTIL)
import pax_rpg_blender_util as U  # noqa: E402

importlib.reload(U)
from mathutils import Vector  # noqa: E402

U.DIRS["BACKTOP"] = Vector((0.0, 0.8, 0.6))
U.DIRS["BACK34"] = Vector((-0.7, 0.7, 0.2))
try:
    result
except NameError:
    result = {}
scn = bpy.data.scenes["Knight"]
(bpy.context.window or bpy.context.window_manager.windows[0]).scene = scn
rig = bpy.data.objects["Knight_rig"]
rig.animation_data.action = None
for p in rig.pose.bones:
    p.rotation_quaternion = (1, 0, 0, 0)
    p.location = (0, 0, 0)
hidden = [o for o in scn.objects if o.type == "MESH" and not o.name.startswith("Knight_")]
for o in hidden:
    o.hide_set(True)
bpy.context.view_layer.update()
files = U.shot("body_back", (0, 0, 1.0), 2.2, ("BACK", "BACK34", "BACKTOP"), res=600)
files += U.shot("body_neck", (0, 0, 1.5), 0.8, ("BACK", "BACKTOP", "FRONT34"), res=600)
for o in hidden:
    o.hide_set(False)
result["files"] = [f.split("\\")[-1] for f in files]
