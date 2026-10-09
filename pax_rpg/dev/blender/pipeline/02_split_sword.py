import bpy, bmesh, sys, importlib
import numpy as np
from mathutils import Vector, Matrix
for n in ("Sword", "Hero_rig"):
    o = bpy.data.objects.get(n)
    if o:
        bpy.data.objects.remove(o, do_unlink=True)
body = bpy.data.objects["Hero_male"]; bk = bpy.data.objects["Hero_male_with_sword"]
body.parent = None; body.modifiers.clear(); body.vertex_groups.clear()
old = body.data; body.data = bk.data.copy(); body.data.name = "Hero_male"; bpy.data.meshes.remove(old)
me = body.data
co = np.empty(len(me.vertices) * 3, dtype=np.float32); me.vertices.foreach_get("co", co); co = co.reshape(-1, 3)
d = np.array([0.163, 0.077, 0.984]); d /= np.linalg.norm(d); c = np.array([0.405, 0.022, 0.563])
rel = co - c; t = rel @ d; r = np.linalg.norm(rel - np.outer(t, d), axis=1)
za = c[2] + t * d[2]                                  # высота точки оси напротив вершины
TSUBA_LO, TSUBA_HI, HAND_TOP, TOP = 0.815, 0.866, 1.025, 1.26
sword_v = ((za < TSUBA_LO) & (r < 0.045)) | ((za >= TSUBA_LO) & (za <= TSUBA_HI) & (r < 0.095)) \
    | ((za > HAND_TOP) & (za < TOP) & (r < 0.05))
core_v = (za > TSUBA_HI) & (za <= HAND_TOP) & (r < 0.02)
bm = bmesh.new(); bm.from_mesh(me)
sv = set(np.flatnonzero(sword_v).tolist()); cv = set(np.flatnonzero(core_v).tolist())
sword_faces = [f for f in bm.faces if all(v.index in sv for v in f.verts)]
sbm = bmesh.new(); uv_s = bm.loops.layers.uv.active; uv_d = sbm.loops.layers.uv.new("UVMap"); vm = {}
for f in sword_faces:
    vs = []
    for v in f.verts:
        if v.index not in vm:
            vm[v.index] = sbm.verts.new(v.co)
        vs.append(vm[v.index])
    try:
        nf = sbm.faces.new(vs)
    except ValueError:
        continue
    for a, b in zip(f.loops, nf.loops):
        b[uv_d].uv = a[uv_s].uv
bmesh.ops.holes_fill(sbm, edges=[e for e in sbm.edges if e.is_boundary], sides=40)
axis_pt = lambda zz: Vector(c + d * ((zz - c[2]) / d[2]))
a, b = axis_pt(TSUBA_HI - 0.005), axis_pt(HAND_TOP + 0.01)
rot = Vector((0, 0, 1)).rotation_difference((b - a).normalized()).to_matrix().to_4x4()
core = bmesh.ops.create_cone(sbm, cap_ends=True, segments=16, radius1=0.021, radius2=0.021, depth=(b - a).length,
                             matrix=Matrix.Translation((a + b) / 2) @ rot)
cvs = set(core["verts"])
for f in sbm.faces:
    f.material_index = 1 if all(v in cvs for v in f.verts) else 0
sm = bpy.data.meshes.new("Sword"); sbm.to_mesh(sm); sbm.free()
sm.materials.append(me.materials[0]); sm.materials.append(bpy.data.materials["Sword_grip"])
sword = bpy.data.objects.new("Sword", sm); body.users_collection[0].objects.link(sword)
kill = set(sword_faces) | {f for f in bm.faces if any(v.index in cv for v in f.verts)}
bmesh.ops.delete(bm, geom=list(kill), context="FACES")
bmesh.ops.delete(bm, geom=[v for v in bm.verts if not v.link_faces], context="VERTS")
filled = bmesh.ops.holes_fill(bm, edges=[e for e in bm.edges if e.is_boundary], sides=40)
bm.to_mesh(me); bm.free(); me.update()
gc = (a + b) / 2
sword.data.transform(Matrix.Translation(-gc)); sword.location = gc
# проверка: меч отдельно (сдвинут), кулак крупно
for o in bpy.data.objects:
    o.hide_set(o.name not in ("Hero_male", "Sword"))
sys.path.insert(0, r"C:\Users\mbkli\AppData\Local\Programs\Pax Universe\pax_corporations_dev")
import pax_rpg_blender_util as U; importlib.reload(U)
sword.location = gc + Vector((0.3, 0, 0))
files = U.shot("sep_hand", (0.6, 0.03, 0.85), 0.75, ("FRONT", "FRONT34"))
sword.location = gc
result.update(sword_faces=len(sword_faces), filled=len(filled["faces"]), grip=[round(v, 3) for v in gc], files=files)
