"""Портрет для HUD боя: голова персонажа из glb, вид спереди, квадрат. Через мост:
exec(open(<файл>).read(), {"result": {}, "SRC": "<модель.glb>", "OUT": "<портрет.png>", "BONE": "Head"})"""
import importlib
import os
import shutil
import sys

import bpy

UTIL = r"C:\Users\mbkli\AppData\Local\Programs\Pax Universe\pax_corporations_dev"
sys.path.insert(0, UTIL)
import pax_rpg_blender_util as U  # noqa: E402

importlib.reload(U)
try:
    result
except NameError:
    result = {}
win = bpy.context.window or bpy.context.window_manager.windows[0]
prev = win.scene
scn = bpy.data.scenes.new("Portrait")
win.scene = scn
bpy.ops.import_scene.gltf(filepath=SRC)  # noqa: F821
rig = next((o for o in scn.objects if o.type == "ARMATURE"), None)
bone = BONE if rig is not None and BONE in rig.pose.bones else None  # noqa: F821
if bone:
    h = rig.matrix_world @ rig.pose.bones[bone].head
    target = (h.x, h.y, h.z + 0.04)
else:
    zs = [(o.matrix_world @ v.co).z for o in scn.objects if o.type == "MESH" for v in o.data.vertices]
    target = (0.0, 0.0, max(zs) * 0.88)
files = U.shot("portrait_tmp", target, 0.42, ("FRONT34",), res=256)
shutil.copy(files[0], OUT)  # noqa: F821
for o in list(scn.objects):
    bpy.data.objects.remove(o, do_unlink=True)
win.scene = prev
bpy.data.scenes.remove(scn)
bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
result["portrait"] = [OUT, os.path.getsize(OUT), target]  # noqa: F821
