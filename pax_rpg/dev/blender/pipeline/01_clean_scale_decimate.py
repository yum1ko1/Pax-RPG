import bpy, bmesh, time
t0 = time.time()
CUT = -0.4415          # верх подставки Meshy
HEIGHT = 1.8           # м, с рогами
src = bpy.data.objects["blend_Mesh_0"]
hi = src.copy(); hi.data = src.data.copy(); hi.name = "Hero_male_hi"
coll = bpy.data.collections.get("Hero") or bpy.data.collections.new("Hero")
if coll.name not in bpy.context.scene.collection.children:
    bpy.context.scene.collection.children.link(coll)
coll.objects.link(hi)
bm = bmesh.new(); bm.from_mesh(hi.data)
bmesh.ops.delete(bm, geom=[v for v in bm.verts if v.co.z < CUT], context="VERTS")
boundary = [e for e in bm.edges if e.is_boundary]
filled = bmesh.ops.holes_fill(bm, edges=boundary, sides=0)
zmax = max(v.co.z for v in bm.verts)
k = HEIGHT / (zmax - CUT)
for v in bm.verts:
    v.co.z -= CUT
    v.co *= k
bm.to_mesh(hi.data); bm.free()
hi.data.update()
tris_hi = sum(len(p.vertices) - 2 for p in hi.data.polygons)
# игровая версия
lo = hi.copy(); lo.data = hi.data.copy(); lo.name = "Hero_male"
coll.objects.link(lo)
mod = lo.modifiers.new("Decimate", "DECIMATE")
mod.ratio = 70000 / tris_hi
mod.use_collapse_triangulate = True
with bpy.context.temp_override(object=lo, active_object=lo, selected_objects=[lo]):
    bpy.ops.object.modifier_apply(modifier=mod.name)
tris_lo = sum(len(p.vertices) - 2 for p in lo.data.polygons)
for o in bpy.data.collections["Meshy_src"].objects:
    o.hide_set(True)
hi.hide_set(True)
lo.location = (0, 0, 0)
result.update(tris_hi=tris_hi, tris_lo=tris_lo, verts_lo=len(lo.data.vertices), holes=len(filled["faces"]),
              dims_lo=[round(x, 3) for x in lo.dimensions], seconds=round(time.time() - t0, 1))
