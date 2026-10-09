"""Помощник для живого Blender (через blender_live.ps1): крупные планы для проверки.

    import sys; sys.path.insert(0, r"<папка>"); import pax_rpg_blender_util as U
    U.shot("hand", (0.46, 0, 0.88), 0.4, ("FRONT", "RIGHT"))
Рендер workbench с текстурами, ортографический, 900×900 → <W>/shots/<name>_<view>.png.
"""
import os

import bpy
from mathutils import Vector

W = r"C:\Users\mbkli\Desktop\pax_rpg_work"
DIRS = {"FRONT": Vector((0, -1, 0)), "BACK": Vector((0, 1, 0)), "RIGHT": Vector((1, 0, 0)),
        "LEFT": Vector((-1, 0, 0)), "TOP": Vector((0, 0, 1)), "FRONT34": Vector((0.7, -0.7, 0.15))}


def shot(name, target, size, views=("FRONT",), res=900):
    scene = bpy.context.scene
    prev_cam = scene.camera
    eng = scene.render.engine
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"; sh.color_type = "TEXTURE"; sh.show_cavity = True
    scene.render.resolution_x = scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    cam_data = bpy.data.cameras.get("PaxShot") or bpy.data.cameras.new("PaxShot")
    cam_data.type = "ORTHO"; cam_data.ortho_scale = size; cam_data.clip_end = 100
    cam = bpy.data.objects.get("PaxShot") or bpy.data.objects.new("PaxShot", cam_data)
    if cam.name not in scene.collection.objects:
        scene.collection.objects.link(cam)
    scene.camera = cam
    # в рендер — только то, что видно в окне (скрытое в окне иначе всё равно рисуется)
    saved = {o.name: o.hide_render for o in bpy.data.objects}
    for o in bpy.data.objects:
        o.hide_render = o.hide_get() if o.name in bpy.context.view_layer.objects else True
    os.makedirs(os.path.join(W, "shots"), exist_ok=True)
    out = []
    t = Vector(target)
    for v in views:
        d = DIRS[v].normalized()
        cam.location = t + d * 5
        cam.rotation_euler = (t - cam.location).to_track_quat("-Z", "Y").to_euler()
        path = os.path.join(W, "shots", f"{name}_{v.lower()}.png")
        scene.render.filepath = path
        bpy.ops.render.render(write_still=True)
        out.append(path)
    for name, hr in saved.items():
        if name in bpy.data.objects:
            bpy.data.objects[name].hide_render = hr
    scene.camera = prev_cam
    scene.render.engine = eng
    return out
