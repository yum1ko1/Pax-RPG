"""Окна зданий Гхарна: на ровных участках стен (по этажам, с шагом) ставятся оконные блоки props/window_glass.glb
(рама, решётка, стекло — материал glass в игре отражает небо и свет).
Лучи снаружи к оси здания на разных высотах → точка стены, нормаль, цвет текстуры в точке; тёмные точки
собираются в окна (центр, размер, поворот). Итог — W\\gharn\\windows.json (координаты glTF: Y вверх, метры,
в осях модели) и превью W\\gharn\\windows\\<id>.png (здание + найденные стёкла, для проверки глазами).
    blender -b -P gharn_windows.py
"""
import json
import math
import os

import bmesh
import numpy as np
import bpy
from mathutils import Vector
from mathutils.bvhtree import BVHTree

W = r"C:\Users\mbkli\Desktop\pax_rpg_work\gharn"
IDS = ["guild_hall", "tavern_hall", "house_shop_a", "house_shop_b", "house_shop_c", "khan_palace"]
STEP_DEG = 1.0
STEP_Z = 0.25


def clear():
    for o in list(bpy.data.objects):
        bpy.data.objects.remove(o, do_unlink=True)


def load(pid):
    clear()
    bpy.ops.import_scene.gltf(filepath=os.path.join(W, "final", pid + ".glb"))
    obs = [o for o in bpy.context.scene.objects if o.type == "MESH"]
    bpy.ops.object.select_all(action="DESELECT")
    for o in obs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = obs[0]
    bpy.ops.object.parent_clear(type="CLEAR_KEEP_TRANSFORM")   # масштаб Meshy — у родителя-узла glTF
    if len(obs) > 1:
        bpy.ops.object.join()
    ob = bpy.context.view_layer.objects.active
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    return ob


def base_image(ob):
    """Картинка цвета: вверх по связям от входа Base Color любого BSDF (между ними бывают узлы-смесители)."""
    def up(node, seen):
        if node in seen:
            return None
        seen.add(node)
        if node.type == "TEX_IMAGE" and node.image:
            return node.image
        for inp in node.inputs:
            for link in inp.links:
                r = up(link.from_node, seen)
                if r:
                    return r
        return None
    for slot in ob.material_slots:
        m = slot.material
        if not m or not m.node_tree:
            continue
        for n in m.node_tree.nodes:
            if n.type == "BSDF_PRINCIPLED" and n.inputs["Base Color"].is_linked:
                r = up(n.inputs["Base Color"].links[0].from_node, set())
                if r:
                    return r
    print("no base color image:", ob.name, [n.type for s in ob.material_slots if s.material and s.material.node_tree
                                            for n in s.material.node_tree.nodes], flush=True)
    return None


def analyse(pid):
    ob = load(pid)
    img = base_image(ob)
    if img is None:
        print(pid, "нет текстуры")
        return []
    iw, ih = img.size
    px = np.empty(iw * ih * 4, np.float32)           # RGBA float, снизу вверх
    img.pixels.foreach_get(px)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.triangulate(bm, faces=bm.faces[:])
    bm.faces.ensure_lookup_table()
    uvl = bm.loops.layers.uv.active
    bvh = BVHTree.FromBMesh(bm)
    lo, hi = Vector(ob.bound_box[0]), Vector(ob.bound_box[6])
    c = (lo + hi) / 2
    R = (hi - lo).length
    height = hi.z - lo.z

    def lum_at(face, p):
        a, b, cc = (l.vert.co for l in face.loops)
        # барицентрические координаты
        v0, v1, v2 = b - a, cc - a, p - a
        d00, d01, d11 = v0.dot(v0), v0.dot(v1), v1.dot(v1)
        d20, d21 = v2.dot(v0), v2.dot(v1)
        den = d00 * d11 - d01 * d01 or 1e-9
        v = (d11 * d20 - d01 * d21) / den
        w = (d00 * d21 - d01 * d20) / den
        u = 1 - v - w
        uv = face.loops[0][uvl].uv * u + face.loops[1][uvl].uv * v + face.loops[2][uvl].uv * w
        x = min(iw - 1, max(0, int((uv.x % 1.0) * iw)))
        y = min(ih - 1, max(0, int((uv.y % 1.0) * ih)))
        i = (y * iw + x) * 4
        r, g, bb = float(px[i]), float(px[i + 1]), float(px[i + 2])
        return 0.2126 * r + 0.7152 * g + 0.0722 * bb, (r, g, bb)

    pts = []                                          # (точка, нормаль, яркость, ровно ли вокруг)
    stats = {"hit": 0, "wall": 0, "flat": 0}
    z = lo.z + 1.3
    while z < lo.z + height * 0.82:
        for k in range(int(360 / STEP_DEG)):
            a = math.radians(k * STEP_DEG)
            d = Vector((math.cos(a), math.sin(a), 0))
            hit = bvh.ray_cast(Vector((c.x, c.y, z)) + d * R, -d)
            if hit[0] is None:
                continue
            p, n, fi, _ = hit
            stats["hit"] += 1
            if abs(n.z) > 0.15 or n.dot(d) < 0.55:
                continue
            stats["wall"] += 1
            # ровная стена вокруг (под окно 1×1.3 м): соседние лучи упираются в ту же плоскость
            t = Vector((-n.y, n.x, 0)).normalized()
            flat = True
            for off in (t * 0.45, -t * 0.45, Vector((0, 0, 0.55)), Vector((0, 0, -0.55))):
                h2 = bvh.ray_cast(p + off + n * 0.6, -n)
                if h2[0] is None or abs((h2[0] - (p + off)).dot(n)) > 0.12:
                    flat = False
                    break
            if not flat:
                continue
            stats["flat"] += 1
            lum, _ = lum_at(bm.faces[fi], p)
            pts.append((p, n, lum))
        z += STEP_Z
    print(f"{pid}: bounds {tuple(round(v, 1) for v in lo)} {tuple(round(v, 1) for v in hi)}, stats {stats}", flush=True)
    if not pts:
        return []
    # окна по этажам: ровно на 1.3×1.7 м вокруг, не ниже 2.4 м от земли (двери, крыльцо), шаг ≥ 2.8 м
    floors = [lo.z + 2.2 + k * 3.0 for k in range(6) if lo.z + 2.2 + k * 3.0 + 1.4 < lo.z + height * 0.72]
    wins, taken = [], []
    for p, n, lum in sorted(pts, key=lambda q: math.atan2(q[0].y - c.y, q[0].x - c.x)):
        fz = min(floors, key=lambda f: abs(p.z - (f + 0.65))) if floors else None
        if fz is None or abs(p.z - (fz + 0.65)) > STEP_Z * 0.6:
            continue
        if any((p - q).length < 2.4 for q in taken):
            continue
        t = Vector((-n.y, n.x, 0)).normalized()
        ok = True
        for off in (t * 0.55, -t * 0.55, Vector((0, 0, 0.7)), Vector((0, 0, -0.6)), t * 0.55 + Vector((0, 0, 0.7)),
                    -t * 0.55 - Vector((0, 0, 0.6))):
            h2 = bvh.ray_cast(p + off + n * 1.2, -n)
            if h2[0] is None or abs((h2[0] - (p + off)).dot(n)) > 0.16 or h2[1].dot(n) < 0.7:
                ok = False
                break
        if not ok:
            continue
        taken.append(p)
        cen = p + n * 0.02
        nx, nz = n.x, -n.y                             # Blender (x, y, z) → glTF (x, z, −y)
        wins.append([round(cen.x, 3), round(fz, 3), round(-cen.y, 3), round(math.degrees(math.atan2(nx, nz)), 1), 1.0, 1.3])
    dark = []
    print(f"{pid}: wall {len(pts)}, dark {len(dark)}, windows {len(wins)}", flush=True)
    preview(pid, ob, wins)
    return wins


def preview(pid, ob, wins):
    gm = bpy.data.materials.get("glass_preview") or bpy.data.materials.new("glass_preview")
    gm.diffuse_color = (0.1, 0.9, 1.0, 1)
    for x, y, z, yaw, w, h in wins:
        bpy.ops.mesh.primitive_plane_add(size=1)
        pl = bpy.context.active_object
        pl.scale = (w, h, 1)
        y = y + h / 2
        # плоскость XY → вертикальная, лицом по нормали (glTF yaw → Blender)
        pl.rotation_euler = (math.pi / 2, 0, math.radians(yaw))
        pl.location = (x, -z, y)
        pl.data.materials.append(gm)
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_WORKBENCH"
    sc.display.shading.light = "STUDIO"
    sc.display.shading.color_type = "TEXTURE"
    sc.render.resolution_x, sc.render.resolution_y = 1400, 700
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    sc.collection.objects.link(cam)
    sc.camera = cam
    cam.data.type = "ORTHO"
    d = ob.dimensions
    cam.data.ortho_scale = max(d.x, d.y, d.z) * 1.3
    os.makedirs(os.path.join(W, "windows"), exist_ok=True)
    for i, (ang) in enumerate((0, 180)):
        a = math.radians(ang)
        cen = Vector((0, 0, d.z * 0.45))
        dv = Vector((math.sin(a) * 1.0, -math.cos(a) * 1.0, 0.25)).normalized()
        cam.location = cen + dv * max(d) * 3
        cam.rotation_euler = (cen - cam.location).to_track_quat("-Z", "Y").to_euler()
        sc.render.filepath = os.path.join(W, "windows", f"{pid}_{i}.png")
        bpy.ops.render.render(write_still=True)


out = {pid: analyse(pid) for pid in IDS}
json.dump(out, open(os.path.join(W, "windows.json"), "w"), indent=1)
print("windows.json:", {k: len(v) for k, v in out.items()}, flush=True)
