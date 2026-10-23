"""LOD-копии моделей Meshy без дыр и рваных швов — пересборка, а не простое упрощение. ОПЫТ, в игру не идёт:
на домах Meshy (доски и черепица — отдельные перекрывающиеся оболочки) развёртка выходит в ~6600 кусков, запекание —
в пятнах (сверка lod_compare.py: PSNR 19–29 дБ). Годится для цельных моделей, не для домов Meshy.
У Meshy развёртка «в крошку» (почти каждое ребро — шов UV, вершин вдвое больше граней): Decimate без сварки рвал
швы и выедал куски (дыры в домах), со сваркой — тянул шипы; meshoptimizer с сохранением швов снимает лишь 1–10 %.
Здесь копия собирается заново:
  1) геометрия — weld.mjs: сетка сварена по точкам и упрощена meshoptimizer в допуске полпикселя на дальности
     включения копии (дыр нет: сварка и упрощение не размыкают поверхность);
  2) новая развёртка (Smart UV Project) и сглаживание по углу (жёсткие рёбра — жёсткие);
  3) с модели, как она в игре (glb мода + её DDS), запекаются цвет и ORM (как есть, через свечение — без света) и
     нормали (касательные, как glTF/Godot) — рельеф и грани исходника переходят в карту нормалей.
Картинки копии — свои, в glb (дальше — bake_textures.gd bc7 и strip_glb.py, как у всех моделей). Узлы — как у исходника.
    python (модуль bpy 5.2: pip install bpy==5.2.3 pillow) lod_bake.py -- <glb мода> <папка .tex> <геометрия от weld.mjs>
        <выход.glb> <сторона текстуры>
"""
import os
import sys
import math
import tempfile

import bpy
import bmesh  # после bpy: в модуле bpy bmesh появляется только с ним
import numpy as np
import xatlas
from PIL import Image

a = sys.argv[sys.argv.index("--") + 1:]
SRC, TEX, GEO, OUT, SIZE = a[0], a[1], a[2], a[3], int(a[4])
tmp = tempfile.mkdtemp()

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=SRC)
hi = [o for o in bpy.context.scene.objects if o.type == "MESH"]
assert len(hi) == 1 and len(hi[0].data.materials) == 1, "пока — модели из одной сетки с одним материалом"
hi = hi[0]

# картинки исходника — из DDS игры (в glb мода они 1×1); порядок t<N> — обход слотов игры: цвет, нормали, ORM
mat = hi.data.materials[0]
nt = mat.node_tree
bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")


def tex_node(sock):
    # картинка выше по цепочке узлов (через «Разделить цвет», «Карту нормалей»)
    todo = [l.from_node for l in sock.links]
    while todo:
        n = todo.pop(0)
        if n.type == "TEX_IMAGE":
            return n
        todo += [l.from_node for i in n.inputs for l in i.links]
    return None


t_col = tex_node(bsdf.inputs["Base Color"])
t_nrm = tex_node(bsdf.inputs["Normal"])
t_orm = tex_node(bsdf.inputs["Roughness"]) or tex_node(bsdf.inputs["Metallic"])


def dds_png(t, normal):
    # номер t<N>.dds — в пикселе заглушки (mark_glb.py: N, 90, 165)
    px = t.image.pixels[:4]
    n = round(px[0] * 255)
    assert abs(px[1] * 255 - 90) < 2 and abs(px[2] * 255 - 165) < 2, "заглушка без номера: " + t.image.name
    im = Image.open(os.path.join(TEX, "t%d.dds" % n)).convert("RGB")
    if normal and max(im.getchannel("B").getextrema()) == 0:     # BC5: z восстановить из x, y
        import numpy as np
        a = np.asarray(im, dtype=np.float32) / 255.0
        xy = a[..., :2] * 2.0 - 1.0
        a[..., 2] = (np.sqrt(np.clip(1.0 - (xy ** 2).sum(-1), 0.0, 1.0)) + 1.0) * 0.5
        im = Image.fromarray((a * 255.0 + 0.5).astype(np.uint8))
    p = os.path.join(tmp, "t%d.png" % n)
    im.save(p)
    cs = t.image.colorspace_settings.name
    t.image = bpy.data.images.load(p)
    t.image.colorspace_settings.name = cs


for t, nrm in ((t_col, False), (t_nrm, True), (t_orm, False)):
    if t is not None and not t.image.filepath.startswith(tmp):
        dds_png(t, nrm)

# 1) копия: геометрия от weld.mjs (сварена и упрощена), узлы те же
first = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=GEO)
lo = next(o for o in bpy.data.objects if o not in first and o.type == "MESH")
me = lo.data
t0 = sum(len(p.vertices) - 2 for p in hi.data.polygons)
t1 = sum(len(p.vertices) - 2 for p in me.polygons)
for o in bpy.context.view_layer.objects:
    o.select_set(False)
bpy.context.view_layer.objects.active = lo
lo.select_set(True)

# 2) развёртка — xatlas (развёртка для запекания, как у света в Godot: крупные куски, плотная упаковка; Smart UV
# Project дробил дом на тысячи островков и занимал малую долю картинки — мыло и пятна), потом сварка обратно (UV —
# в углах граней) и сглаживание по углу
me.calc_loop_triangles()
V = np.array([v.co[:] for v in me.vertices], dtype=np.float32)
F = np.array([t.vertices[:] for t in me.loop_triangles], dtype=np.uint32)
atl = xatlas.Atlas()
atl.add_mesh(V, F)
po = xatlas.PackOptions()
po.resolution = SIZE
po.padding = 4
po.bilinear = True
po.blockAlign = True
atl.generate(xatlas.ChartOptions(), po)
vmap, idx, uvs = atl[0]
nm = bpy.data.meshes.new(me.name)
nm.from_pydata(V[vmap].tolist(), [], idx.tolist())
uvl = nm.uv_layers.new(name="UVMap")
uvl.data.foreach_set("uv", uvs[idx.ravel()].ravel().astype(np.float32))
bm = bmesh.new()
bm.from_mesh(nm)
bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-7)
bm.to_mesh(nm)
bm.free()
lo.data = nm
me = nm
for p in me.polygons:
    p.use_smooth = True
me.set_sharp_from_angle(angle=math.radians(40))
print("развёртка: %d кусков, заполнено %.0f %%" % (atl.chart_count, 100.0 * float(atl.utilization)), flush=True)

# 3) запекание с исходника на копию
sc = bpy.context.scene
sc.render.engine = "CYCLES"
sc.cycles.device = "CPU"
sc.cycles.samples = 16
bk = sc.render.bake
bk.use_selected_to_active = True
# лучи — от копии к исходнику: копия отходит от него не дальше допуска weld.mjs (≤ 1.5–3.5 см), а у Meshy слои
# (доски, перила, черепица) лежат в сантиметрах друг от друга — длинный луч попадал в соседний слой (тёмные пятна)
bk.cage_extrusion = float(os.environ.get("LOD_CAGE", "0.04"))
bk.max_ray_distance = 2.0 * bk.cage_extrusion
bk.margin = 16
bk.margin_type = "EXTEND"

lm = bpy.data.materials.new("lod")
lm.use_nodes = True
lo.data.materials.clear()
lo.data.materials.append(lm)
ln = lm.node_tree
lb = next(n for n in ln.nodes if n.type == "BSDF_PRINCIPLED")


def target(name, non_color):
    img = bpy.data.images.new(name, SIZE, SIZE, alpha=False, float_buffer=False)
    if non_color:
        img.colorspace_settings.name = "Non-Color"
    n = ln.nodes.new("ShaderNodeTexImage")
    n.image = img
    return n


def bake(kind, node):
    for n in ln.nodes:
        n.select = False
    node.select = True
    ln.nodes.active = node
    for o in bpy.context.view_layer.objects:
        o.select_set(False)
    hi.select_set(True)
    lo.select_set(True)
    bpy.context.view_layer.objects.active = lo
    bpy.ops.object.bake(type=kind, use_clear=True)


def emit_from(img_node):
    # свечение исходника = его картинка как есть (цвет / ORM) — запекается без света и тона
    out = next(n for n in nt.nodes if n.type == "OUTPUT_MATERIAL")
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(img_node.outputs["Color"], em.inputs["Color"])
    old = out.inputs["Surface"].links[0].from_socket
    nt.links.new(em.outputs["Emission"], out.inputs["Surface"])
    return lambda: (nt.links.new(old, out.inputs["Surface"]), nt.nodes.remove(em))


n_col = target("col", False)
undo = emit_from(t_col)
bake("EMIT", n_col)
undo()
n_orm = None
if t_orm is not None:
    n_orm = target("orm", True)
    undo = emit_from(t_orm)
    bake("EMIT", n_orm)
    undo()
n_nrm = target("nrm", True)
bake("NORMAL", n_nrm)

# материал копии — как у glTF: цвет, ORM (G — шероховатость, B — металл), нормали
ln.links.new(n_col.outputs["Color"], lb.inputs["Base Color"])
if n_orm is not None:
    sep = ln.nodes.new("ShaderNodeSeparateColor")
    ln.links.new(n_orm.outputs["Color"], sep.inputs["Color"])
    ln.links.new(sep.outputs["Green"], lb.inputs["Roughness"])
    ln.links.new(sep.outputs["Blue"], lb.inputs["Metallic"])
nm = ln.nodes.new("ShaderNodeNormalMap")
ln.links.new(n_nrm.outputs["Color"], nm.inputs["Color"])
ln.links.new(nm.outputs["Normal"], lb.inputs["Normal"])
for im in (n_col.image, n_nrm.image) + ((n_orm.image,) if n_orm else ()):
    im.file_format = "PNG"
    im.filepath_raw = os.path.join(tmp, im.name + "_bake.png")
    im.save()
lm.use_backface_culling = mat.use_backface_culling

for o in first:                                  # исходник и его узлы — прочь, в glb только копия
    bpy.data.objects.remove(o)
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", export_yup=True, export_image_format="AUTO",
                          export_animations=False, export_skins=False, export_tangents=False)
print(f"LOD {os.path.basename(OUT)}: {t0} → {t1} tris, текстура {SIZE}", flush=True)
