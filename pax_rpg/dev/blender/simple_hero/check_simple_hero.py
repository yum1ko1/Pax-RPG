"""Проверочные рендеры простого героя (после build_simple_hero.py): <W>/shots/sh_*.png.

Через мост: exec(open(<файл>).read(), {"result": {}, "SHOTS": [(действие, кадр, вид), ...]}) — без SHOTS
снимается стандартный набор.
"""
import importlib
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
try:
    SHOTS
except NameError:
    SHOTS = [("Idle", 0, "FRONT"), ("Idle", 0, "RIGHT"), ("Idle", 0, "BACK")] + \
        [("Draw", f, "FRONT34") for f in (0, 5, 9, 12, 15, 20, 30)] + \
        [("Walk", f, "RIGHT") for f in (0, 6, 12, 18)] + [("WalkArmed", f, "FRONT34") for f in (0, 6)]

scn = bpy.data.scenes["SimpleHero"]
win = bpy.context.window or bpy.context.window_manager.windows[0]
win.scene = scn
rig = bpy.data.objects["SimpleHero_rig"]
files = []
for act, f, view in SHOTS:
    rig.animation_data.action = bpy.data.actions[act]
    scn.frame_set(f)
    files += U.shot(f"sh_{act.lower()}{f:02d}", (0, 0, 1.0), 2.3, (view,), res=450)
rig.animation_data.action = bpy.data.actions["Idle"]
scn.frame_set(0)
result["files"] = [p.split("\\")[-1] for p in files]
