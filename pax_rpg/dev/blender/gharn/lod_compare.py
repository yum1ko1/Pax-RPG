"""Сверка LOD-копии с моделью: тот же кадр (4 стороны, солнце + небо), Cycles; картинка «модель | копия | разница×4»
и PSNR по кадрам. Размер кадра — сколько модель занимает на экране на дальности включения копии (или крупнее — строже).
    lod_compare.py -- <glb мода> <папка .tex> <копия.glb> <папка .tex копии или -> <выход.png> <px модели на экране>
"""
import os
import sys
import math
import tempfile

import bpy
import numpy as np
from mathutils import Vector
from PIL import Image

a = sys.argv[sys.argv.index("--") + 1:]
SRC, TEX, LOD, LTEX, OUT, PX = a[0], a[1], a[2], a[3], a[4], int(a[5])
tmp = tempfile.mkdtemp()


def tex_node(nt, sock):
    todo = [l.from_node for l in sock.links]
    while todo:
        n = todo.pop(0)
        if n.type == "TEX_IMAGE":
            return n
        todo += [l.from_node for i in n.inputs for l in i.links]
    return None


def load(path, tex):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    o = next(o for o in bpy.context.scene.objects if o.type == "MESH")
    if tex != "-":
        nt = o.data.materials[0].node_tree
        b = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        for s, normal in (("Base Color", False), ("Normal", True), ("Roughness", False)):
            t = tex_node(nt, b.inputs[s])
            if t is None or t.image.filepath.startswith(tmp):
                continue
            px = t.image.pixels[:4]                 # номер t<N>.dds — в пикселе заглушки (mark_glb.py)
            n = round(px[0] * 255)
            im = Image.open(os.path.join(tex, "t%d.dds" % n)).convert("RGB")
            if normal and max(im.getchannel("B").getextrema()) == 0:     # BC5: z из x, y
                a = np.asarray(im, dtype=np.float32) / 255.0
                xy = a[..., :2] * 2.0 - 1.0
                a[..., 2] = (np.sqrt(np.clip(1.0 - (xy ** 2).sum(-1), 0.0, 1.0)) + 1.0) * 0.5
                im = Image.fromarray((a * 255.0 + 0.5).astype(np.uint8))
            p = os.path.join(tmp, "%s_t%d.png" % (os.path.basename(path), n))
            im.save(p)
            cs = t.image.colorspace_settings.name
            t.image = bpy.data.images.load(p)
            t.image.colorspace_settings.name = cs
    return o


def shots(path, tex):
    o = load(path, tex)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 64
    sc.cycles.use_denoising = False
    sc.render.resolution_x = sc.render.resolution_y = PX
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    w = bpy.data.worlds.new("w")
    w.color = (0.35, 0.4, 0.5)
    sc.world = w
    sun = bpy.data.objects.new("sun", bpy.data.lights.new("sun", "SUN"))
    sun.data.energy = 3.0
    sun.rotation_euler = (math.radians(50), 0, math.radians(35))
    sc.collection.objects.link(sun)
    bb = [o.matrix_world @ Vector(c) for c in o.bound_box]
    ctr = sum(bb, Vector()) / 8
    r = max((p - ctr).length for p in bb)
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 2.05 * r
    sc.collection.objects.link(cam)
    sc.camera = cam
    out = []
    for k in range(4):
        ang = math.radians(30 + 90 * k)
        d = Vector((math.cos(ang), math.sin(ang), 0.45)).normalized()
        cam.location = ctr + d * r * 4
        cam.rotation_euler = (-d).to_track_quat("-Z", "Y").to_euler()
        f = os.path.join(tmp, "%s_%d.png" % (os.path.basename(path), k))
        sc.render.filepath = f
        bpy.ops.render.render(write_still=True)
        out.append(np.asarray(Image.open(f).convert("RGB"), dtype=np.float32))
    return out


A = shots(SRC, TEX)
B = shots(LOD, LTEX)
rows = []
for k, (x, y) in enumerate(zip(A, B)):
    mse = float(((x - y) ** 2).mean())
    print("кадр %d: PSNR %.1f дБ" % (k, 10 * math.log10(255 ** 2 / max(mse, 1e-9))), flush=True)
    d = np.clip(np.abs(x - y) * 4, 0, 255)
    rows.append(np.concatenate([x, y, d], axis=1))
Image.fromarray(np.concatenate(rows, axis=0).astype(np.uint8)).save(OUT)
