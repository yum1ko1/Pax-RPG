"""Осмотр анимаций Mixamo (FBX): кадры, кости, смещение корня, раскадровка 6 кадров сбоку и спереди.
    blender -b -P inspect_fbx.py -- <папка с fbx> <папка для кадров>
"""
import math
import os
import sys

import bpy
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = A[0], A[1]
os.makedirs(OUT, exist_ok=True)
sc = bpy.context.scene
sc.render.engine = "BLENDER_WORKBENCH"
sc.display.shading.light = "STUDIO"
sc.render.resolution_x, sc.render.resolution_y = 220, 300
for f in sorted(os.listdir(SRC)):
    if not f.lower().endswith(".fbx"):
        continue
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)
    for a in list(bpy.data.actions):
        bpy.data.actions.remove(a)
    bpy.ops.import_scene.fbx(filepath=os.path.join(SRC, f))
    arm = [o for o in sc.objects if o.type == "ARMATURE"][0]
    act = arm.animation_data.action
    f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
    hips = [b for b in arm.pose.bones if b.name.lower().endswith("hips")][0]
    sc.frame_set(f0)
    p0 = arm.matrix_world @ hips.head
    sc.frame_set(f1)
    p1 = arm.matrix_world @ hips.head
    names = [b.name for b in arm.pose.bones]
    print(f"== {f}: frames {f0}-{f1} fps {sc.render.fps}, bones {len(names)} ({names[0]}…), root move "
          f"{tuple(round(v, 2) for v in (p1 - p0))}, meshes {len([o for o in sc.objects if o.type == 'MESH'])}", flush=True)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.6 * (arm.scale.x if arm.scale.x < 0.5 else 1.0) * 100 if arm.scale.x < 0.5 else 2.6
    for i in range(6):
        fr = round(f0 + (f1 - f0) * i / 5)
        sc.frame_set(fr)
        c = arm.matrix_world @ hips.head
        cam.data.ortho_scale = 2.8
        cam.location = c + Vector((4.0, 0, 0.1))
        cam.rotation_euler = (math.pi / 2, 0, math.pi / 2)
        sc.render.filepath = os.path.join(OUT, f"{f[:-4]}_{i}.png")
        bpy.ops.render.render(write_still=True)
