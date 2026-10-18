"""Снимок модели (дом и т. п.) для эталона: 3/4 спереди, дневной свет, свои текстуры glb.
    blender -b -P house_shot.py -- <model.glb> <out.png>"""
import sys, math, bpy
from mathutils import Vector
A = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT = A[0], A[1]
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
bpy.ops.import_scene.gltf(filepath=SRC)
sc = bpy.context.scene
ms = [o for o in sc.objects if o.type == "MESH"]
pts = [o.matrix_world @ Vector(c) for o in ms for c in o.bound_box]
lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
c = (lo + hi) / 2
r = (hi - lo).length / 2
eng = [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items]
sc.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in eng else "BLENDER_EEVEE"
sc.render.resolution_x, sc.render.resolution_y = 1400, 1050
sc.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in sc.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
w = bpy.data.worlds.new("w"); sc.world = w; w.use_nodes = True
w.node_tree.nodes["Background"].inputs[0].default_value = (0.55, 0.6, 0.7, 1)
w.node_tree.nodes["Background"].inputs[1].default_value = 0.6
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); sc.collection.objects.link(cam); sc.camera = cam
cam.data.lens = 45
d = Vector((0.75, -1.0, 0.35)).normalized()
cam.location = c + d * r * 2.6
cam.rotation_euler = (c - cam.location).to_track_quat("-Z", "Y").to_euler()
sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN")); sc.collection.objects.link(sun)
sun.data.energy = 3.5; sun.rotation_euler = (math.radians(50), 0, math.radians(35))
sc.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("shot", OUT)
