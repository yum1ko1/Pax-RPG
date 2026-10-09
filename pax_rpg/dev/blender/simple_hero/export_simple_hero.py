"""Экспорт простого героя в glb (после build_simple_hero.py) и проверка: glb импортируется обратно во временную
сцену, снимаются кадры Draw — меч должен быть в руке (ограничения Copy Transforms запечены в кости).

Через мост: exec(open(<файл>).read(), {"result": {}}). Пишет <W>/hero_simple.glb, <W>/simple_hero.blend,
<W>/shots/sh_glb_draw*.png.
"""
import importlib
import os
import sys

import bpy

W = r"C:\Users\mbkli\Desktop\pax_rpg_work"
UTIL = r"C:\Users\mbkli\AppData\Local\Programs\Pax Universe\pax_corporations_dev"
ACTIONS = ("Idle", "Walk", "WalkArmed", "Draw", "Sheathe")
sys.path.insert(0, UTIL)
import pax_rpg_blender_util as U  # noqa: E402

importlib.reload(U)
try:
    result
except NameError:
    result = {}

win = bpy.context.window or bpy.context.window_manager.windows[0]
scn = bpy.data.scenes["SimpleHero"]
win.scene = scn
rig = bpy.data.objects["SimpleHero_rig"]


def use(ob, action):
    ob.animation_data.action = action
    if hasattr(ob.animation_data, "action_slot") and len(getattr(action, "slots", [])):
        ob.animation_data.action_slot = action.slots[0]


# В glb — только наши пять анимаций: каждая своей дорожкой NLA (режим ACTIONS забрал бы и действия
# Meshy-героя из этого же файла — у них те же имена костей).
ad = rig.animation_data
for tr in list(ad.nla_tracks):
    ad.nla_tracks.remove(tr)
for name in ACTIONS:
    act = bpy.data.actions[name]
    tr = ad.nla_tracks.new()
    tr.name = name
    st = tr.strips.new(name, int(act.frame_range[0]), act)
    if hasattr(st, "action_slot") and len(getattr(act, "slots", [])):
        st.action_slot = act.slots[0]
ad.action = None
scn.frame_set(0)
path = os.path.join(W, "hero_simple.glb")
bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_active_scene=True,
                          export_animation_mode="NLA_TRACKS", export_force_sampling=True, export_frame_step=1,
                          export_yup=True)
for tr in list(ad.nla_tracks):
    ad.nla_tracks.remove(tr)
use(rig, bpy.data.actions["Idle"])
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(W, "simple_hero.blend"), copy=True)
result["glb_kb"] = round(os.path.getsize(path) / 1024)

# ---- проверка: импорт во временную сцену
before_obj, before_act = set(bpy.data.objects), set(bpy.data.actions)
chk = bpy.data.scenes.new("SH_glb_check")
chk.render.fps = scn.render.fps            # иначе кадры glb пересчитаются под 24 к/с
win.scene = chk
bpy.ops.import_scene.gltf(filepath=path)
new_act = [a for a in bpy.data.actions if a not in before_act]
result["glb_actions"] = sorted(a.name for a in new_act)
arm = next(o for o in chk.objects if o.type == "ARMATURE")
result["glb_bones"] = len(arm.data.bones)
files = []
for a in new_act:
    if a.name.split(".")[0] == "Draw":
        if arm.animation_data and arm.animation_data.nla_tracks:
            for tr in arm.animation_data.nla_tracks:
                tr.mute = True
        use(arm, a)
        for f in (0, 15, 30):
            chk.frame_set(f)
            files += U.shot(f"sh_glb_draw{f:02d}", (0, 0, 1.0), 2.3, ("FRONT34",), res=450)
result["files"] = [p.split("\\")[-1] for p in files]
# ---- убрать проверку
for o in [o for o in bpy.data.objects if o not in before_obj]:
    bpy.data.objects.remove(o, do_unlink=True)
for a in new_act:
    bpy.data.actions.remove(a)
win.scene = scn
bpy.data.scenes.remove(chk)
