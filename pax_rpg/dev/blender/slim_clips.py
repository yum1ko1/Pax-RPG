"""Облегчить клипы Meshy: в каждом animation_glb_url.glb лежит вся модель (10 МБ), а игре нужна только анимация
скелета. Через мост: exec(open(<файл>).read(), {"result": {}, "SLIM": [(откуда.glb, куда.glb), ...]}).
Импорт → удалить сетки, материалы и картинки → экспорт скелета с анимацией (~0,2 МБ). Узлы и кости — те же имена,
так что дорожки анимации ложатся на полную модель."""
import os

import bpy

try:
    result
except NameError:
    result = {}
out = result.setdefault("slim", [])
for src, dst in SLIM:  # noqa: F821 — задаётся вызывающим
    tmp = bpy.data.scenes.new("SlimTmp")
    win = bpy.context.window or bpy.context.window_manager.windows[0]
    prev = win.scene
    win.scene = tmp
    before = set(bpy.data.actions)
    bpy.ops.import_scene.gltf(filepath=src)
    for o in list(tmp.objects):
        if o.type == "MESH":
            bpy.data.objects.remove(o, do_unlink=True)
    new_acts = [a for a in bpy.data.actions if a not in before]
    for o in tmp.objects:
        o.select_set(True)
        if o.type == "ARMATURE" and new_acts:
            o.animation_data_create()
            o.animation_data.action = new_acts[0]
            if len(new_acts[0].slots):
                o.animation_data.action_slot = new_acts[0].slots[0]
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    bpy.ops.export_scene.gltf(filepath=dst, export_format="GLB", use_active_scene=True, export_animations=True,
                              export_animation_mode="ACTIVE_ACTIONS", export_skins=True, export_yup=True)
    for o in list(tmp.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for a in set(bpy.data.actions) - before:
        bpy.data.actions.remove(a)
    win.scene = prev
    bpy.data.scenes.remove(tmp)
    out.append([os.path.basename(dst), os.path.getsize(dst)])
bpy.data.orphans_purge(do_local_ids=True, do_linked_ids=True, do_recursive=True)
