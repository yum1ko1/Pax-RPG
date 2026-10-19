"""Модели Meshy (нормированы к ~2 ед.) → реальный размер в метрах, основание на нуле, центр основания в начале
координат (как ставит город). Картинки — как были (4K), формат JPEG.
    blender -b -P norm_meshy.py -- <in.glb> <out.glb> <height|width:N> [yaw градусов]
Печатает габариты и (для ворот) положение опор у земли — для коробок коллизии в планировке.
"""
import bpy, sys, math
from mathutils import Vector, Matrix

a = sys.argv[sys.argv.index("--") + 1:]
SRC, OUT, SPEC = a[0], a[1], a[2]
YAW = float(a[3]) if len(a) > 3 else 0.0
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
ms = [o for o in bpy.context.scene.objects if o.type == "MESH"]
bpy.ops.object.select_all(action="DESELECT")
for o in ms:
    o.select_set(True)
bpy.context.view_layer.objects.active = ms[0]
if len(ms) > 1:
    bpy.ops.object.join()
o = bpy.context.view_layer.objects.active
o.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
vs = [o.matrix_world @ v.co for v in o.data.vertices]
mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
kind, val = SPEC.split(":")
k = float(val) / ((mx.z - mn.z) if kind == "height" else (mx.x - mn.x))
c = Vector(((mn.x + mx.x) / 2, (mn.y + mx.y) / 2, mn.z))
M = Matrix.Rotation(math.radians(YAW), 4, "Z") @ Matrix.Scale(k, 4) @ Matrix.Translation(-c)
o.data.transform(M)
o.data.update()
vs = [v.co for v in o.data.vertices]
mn = Vector((min(v.x for v in vs), min(v.y for v in vs), min(v.z for v in vs)))
mx = Vector((max(v.x for v in vs), max(v.y for v in vs), max(v.z for v in vs)))
print(f"NORM {OUT}: size {mx.x - mn.x:.2f} x {mx.y - mn.y:.2f} x {mx.z - mn.z:.2f} m, verts {len(vs)}")
# опоры у земли (нижние 4 % высоты): кластеры по X
low = sorted(v.x for v in vs if v.z < mn.z + 0.04 * (mx.z - mn.z))
cl = []
for x in low:
    if cl and x - cl[-1][-1] < 0.25:
        cl[-1].append(x)
    else:
        cl.append([x])
print("NORM feet x:", [(round(min(g), 2), round(max(g), 2)) for g in cl if len(g) > 20])
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_image_format="JPEG",
                          export_jpeg_quality=93)
