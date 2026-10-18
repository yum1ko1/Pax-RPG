"""Копьё за спиной в позах клипов: снимки сбоку и сзади (Sword_Hand скрыт). Проверка, не входит ли копьё в тело.
    blender -b -P spear_check.py -- <model.glb> <out_dir> Idle:0 Walk:10 Run:8 ..."""
import math
import os
import sys

import bpy
from mathutils import Vector

A = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = A[0], A[1]
os.makedirs(OUT, exist_ok=True)
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=SRC)
sc = bpy.context.scene
arm = [o for o in sc.objects if o.type == "ARMATURE"][0]
HIDE = os.environ.get("HIDE", "Sword_Hand,Sword_Drag").split(",")
for o in sc.objects:
    if any(o.name.startswith(h) for h in HIDE if h):
        o.hide_render = True
eng = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in eng else "BLENDER_EEVEE"
sc.render.resolution_x = sc.render.resolution_y = 700
w = bpy.data.worlds.new("w"); sc.world = w
w.color = (0.6, 0.62, 0.7)
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.type = "ORTHO"; cam.data.ortho_scale = 2.2
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun)
sun.data.energy = 4; sun.rotation_euler = (math.radians(40), 0, math.radians(30))
c = Vector((0, 0, 1.0))
for spec in A[2:]:
    clip, fr = spec.split(":")
    act = bpy.data.actions.get(clip) or next((a for a in bpy.data.actions if a.name.startswith(clip + "_") or a.name == clip), None)
    if act is None:
        print("no action", clip); continue
    arm.animation_data_create(); arm.animation_data.action = act
    sc.frame_set(int(fr))
    for name, d in (("side", Vector((1, 0, 0))), ("back", Vector((0, 1, 0))), ("q", Vector((1, 1, 0.3)).normalized())):
        cam.location = c + d * 5
        cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(OUT, "%s_%s_%s.png" % (clip, fr, name))
        bpy.ops.render.render(write_still=True)
print("done", [a.name for a in bpy.data.actions][:40])
