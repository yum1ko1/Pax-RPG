"""Проверочные кадры Чёрного рыцаря (после assemble_knight.py): <W>/shots/kn_<клип><кадр>.png.

Через мост: exec(open(<файл>).read(), {"result": {}, "SHOTS": [(клип, доля 0..1, вид), ...]}).
Меч показывается там, где он в этот момент: на спине или в руке (по knight_anim.json).
"""
import importlib
import json
import os
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
    SHOTS = [("Draw", t, "FRONT34") for t in (0.0, 0.2, 0.35, 0.55, 1.0)] + \
            [(c, t, "FRONT34") for c in ("Attack1", "Attack2", "Attack3") for t in (0.0, 0.35, 0.6, 1.0)] + \
            [("Sheathe", t, "FRONT34") for t in (0.3, 0.7)] + [("Jump", 0.45, "RIGHT"), ("Walk", 0.3, "RIGHT"),
                                                                ("Run", 0.3, "RIGHT"), ("Idle", 0.0, "FRONT")]
meta = json.load(open(r"C:\Users\mbkli\Desktop\pax_rpg_work\meshy\knight\knight_anim.json", encoding="utf-8"))
scn = bpy.data.scenes["Knight"]
win = bpy.context.window or bpy.context.window_manager.windows[0]
win.scene = scn
rig = bpy.data.objects["Knight_rig"]
back, hand = bpy.data.objects["Sword_Back"], bpy.data.objects["Sword_Hand"]
files = []
for clip, t, view in SHOTS:
    a = bpy.data.actions["K_" + clip]
    rig.animation_data.action = a
    rig.animation_data.action_slot = a.slots[0]
    f0, f1 = a.frame_range
    f = int(round(f0 + (f1 - f0) * t))
    tt = (f - f0) / meta["fps"]
    sw = meta["sword_switch"]
    in_hand = clip.startswith("Attack") or (clip == "Draw" and tt >= sw["Draw"]["time"]) or \
        (clip == "Sheathe" and tt < sw["Sheathe"]["time"])
    hand.hide_set(not in_hand)
    back.hide_set(in_hand)
    scn.frame_set(f)
    files += U.shot(f"kn_{clip.lower()}{int(t * 100):03d}", (0, -0.2, 1.0), 3.0, (view,), res=450)
back.hide_set(False)
hand.hide_set(True)
result["files"] = [p.split("\\")[-1] for p in files]
