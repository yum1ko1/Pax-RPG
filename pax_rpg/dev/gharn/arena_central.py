"""Центральная арена Гхарна и подход к Ставке Хаана (Blender, процедурно, точная геометрия под коллизию города):
яма r PIT с мозаикой и кольцами мощения, парапет, трибуны ярусами, кольцевая галерея на высоте H с балюстрадой
из мрамора, наружные лестницы на четыре стороны, четыре беседки на диагоналях галереи, мощёное кольцо площади;
отдельной моделью — парадная лестница к террасе дворца (два марша с площадкой) и облицовка террасы.
Материалы — CC0 4K Poly Haven (тайлятся по UV в метрах), без наложения поверхностей друг на друга.
    blender -b -P arena_central.py -- <папка pbr> <выход arena.glb> <выход palace_stairs.glb | - (вместе с ареной)> [превью png]
Оси Blender: X — восток, Y — север (в игре север = −Z), Z — вверх.
"""
import bpy, bmesh, math, os, sys
from mathutils import Vector, Matrix

a = sys.argv[sys.argv.index("--") + 1:]
PBR, OUT_A, OUT_S = a[0], a[1], a[2]
PREV = a[3] if len(a) > 3 else None

PIT = 13.5          # яма (бой)
PAR = 0.6           # толщина парапета
PAR_H = 1.1
TIERS = 3           # ярусы трибун
TIER_D = 1.0
H = 1.8             # высота галереи над ямой и площадью
GAL_IN = PIT + PAR + TIERS * TIER_D           # 17.1
GAL_OUT = 21.0
STAIR_N = 12                                  # ступеней на H
STEP_H = H / STAIR_N
STEP_D = 0.3
OUT_ST = GAL_OUT + STAIR_N * STEP_D           # 24.1
PLAZA = 31.0
GAP_PIT = 4.4                                 # проход в яму (м) — север и юг
GAP_OUT = 6.0                                 # наружные лестницы — ширина
SEG = 192
# подход к дворцу (в осях игры: терраса +3 м, её фасад z = -36; лестница от z = -28)
PAL_Y0, PAL_Y1, PAL_H, PAL_W = 28.0, 36.0, 3.0, 14.0

bpy.ops.wm.read_factory_settings(use_empty=True)
scn = bpy.context.scene


def mat(name, tex, tint=(1, 1, 1, 1), rough=None, metal=0.0, nor_strength=1.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Metallic"].default_value = metal
    if tex:
        d = nt.nodes.new("ShaderNodeTexImage"); d.image = bpy.data.images.load(os.path.join(PBR, tex + "_diff.jpg"))
        if tint != (1, 1, 1, 1):
            mix = nt.nodes.new("ShaderNodeMix"); mix.data_type = "RGBA"; mix.blend_type = "MULTIPLY"
            mix.inputs["Factor"].default_value = 1.0
            nt.links.new(d.outputs["Color"], mix.inputs[6]); mix.inputs[7].default_value = tint
            nt.links.new(mix.outputs[2], b.inputs["Base Color"])
        else:
            nt.links.new(d.outputs["Color"], b.inputs["Base Color"])
        r = nt.nodes.new("ShaderNodeTexImage"); r.image = bpy.data.images.load(os.path.join(PBR, tex + "_rough.jpg"))
        r.image.colorspace_settings.name = "Non-Color"
        nt.links.new(r.outputs["Color"], b.inputs["Roughness"])
        n = nt.nodes.new("ShaderNodeTexImage"); n.image = bpy.data.images.load(os.path.join(PBR, tex + "_nor.jpg"))
        n.image.colorspace_settings.name = "Non-Color"
        nm = nt.nodes.new("ShaderNodeNormalMap"); nm.inputs["Strength"].default_value = nor_strength
        nt.links.new(n.outputs["Color"], nm.inputs["Color"]); nt.links.new(nm.outputs["Normal"], b.inputs["Normal"])
    else:
        b.inputs["Base Color"].default_value = tint
        b.inputs["Roughness"].default_value = rough if rough is not None else 0.4
    return m


M = {
    "mosaic": mat("arena_mosaic", "old_mosaic_floor"),
    "paving": mat("arena_paving", "patterned_paving", (0.78, 0.66, 0.72, 1)),
    "slab": mat("arena_slab", "monastery_stone_floor", (0.86, 0.82, 0.86, 1)),
    "band": mat("arena_band", "castle_wall_slates", (0.7, 0.66, 0.72, 1)),
    "wall": mat("arena_wall", "stone_block_wall", (0.78, 0.72, 0.76, 1)),
    "marble": mat("arena_marble", "marble_01", (0.93, 0.9, 0.9, 1)),
    "lacquer": mat("arena_lacquer", "lacquered_cherry_wood", (1.0, 0.42, 0.38, 1)),
    "roof": mat("arena_roof", "roof_tiles_14", (0.55, 0.5, 0.6, 1)),
    "gold": mat("arena_gold", None, (0.78, 0.56, 0.24, 1), rough=0.32, metal=1.0),
}
ORDER = list(M)


class Builder:
    def __init__(self, name):
        self.bm = bmesh.new()
        self.uv = self.bm.loops.layers.uv.new("UVMap")
        self.name = name

    def face(self, pts, mi, uvs):
        vs = [self.bm.verts.new(p) for p in pts]
        f = self.bm.faces.new(vs)
        f.material_index = mi
        for l, uv in zip(f.loops, uvs):
            l[self.uv].uv = uv
        return f

    def quad_plane(self, p, uvf, mi):
        """Четырёхугольник с UV по функции uvf(point) → (u, v)."""
        return self.face(p, mi, [uvf(Vector(q)) for q in p])

    def finish(self):
        me = bpy.data.meshes.new(self.name)
        self.bm.normal_update()
        self.bm.to_mesh(me)
        self.bm.free()
        for k in ORDER:
            me.materials.append(M[k])
        o = bpy.data.objects.new(self.name, me)
        scn.collection.objects.link(o)
        for p in me.polygons:
            p.use_smooth = False
        return o


def mi(k):
    return ORDER.index(k)


def pol(r, ang, z=0.0):
    return Vector((math.cos(ang) * r, math.sin(ang) * r, z))


TILE = {"mosaic": 4.0, "paving": 4.5, "slab": 3.0, "band": 2.0, "wall": 3.0, "marble": 1.5, "lacquer": 2.0, "roof": 2.0}


def plan_uv(k):
    t = TILE.get(k, 2.0)
    return lambda q: (q.x / t, q.y / t)


def annulus(B, r0, r1, z, k, a0=0.0, a1=2 * math.pi, seg=SEG, gaps=()):
    """Кольцо пола (только верх). gaps: [(угол, полуширина м)] — вырезы (проходы)."""
    n = max(8, int(seg * (a1 - a0) / (2 * math.pi)))
    uvf = plan_uv(k)
    for i in range(n):
        t0 = a0 + (a1 - a0) * i / n
        t1 = a0 + (a1 - a0) * (i + 1) / n
        tm = (t0 + t1) / 2
        if any(_in_gap(tm, g, r1) for g in gaps):
            continue
        p = [pol(r0, t0, z), pol(r1, t0, z), pol(r1, t1, z), pol(r0, t1, z)] if r0 > 0 else [pol(r1, t0, z), pol(r1, t1, z), Vector((0, 0, z))]
        B.quad_plane(p, uvf, mi(k))


def _in_gap(t, g, r):
    ga, half = g
    d = (t - ga + math.pi) % (2 * math.pi) - math.pi
    return abs(d) * r < half


def ring_wall(B, r, z0, z1, k, facing_out, gaps=(), seg=SEG):
    """Вертикальная стенка кольца (наружу или внутрь), UV — по длине дуги и высоте."""
    t = TILE[k]
    n = seg
    for i in range(n):
        t0 = 2 * math.pi * i / n
        t1 = 2 * math.pi * (i + 1) / n
        if any(_in_gap((t0 + t1) / 2, g, r) for g in gaps):
            continue
        a0, a1 = (t0, t1) if facing_out else (t1, t0)
        p = [pol(r, a0, z0), pol(r, a1, z0), pol(r, a1, z1), pol(r, a0, z1)]
        s0, s1 = a0 * r / t, a1 * r / t
        B.face(p, mi(k), [(s0, z0 / t), (s1, z0 / t), (s1, z1 / t), (s0, z1 / t)])


def gap_side(B, r0, r1, z0, z1, gang, half, k):
    """Торцы вырезов: плоские стенки вдоль прохода (с обеих сторон)."""
    t = TILE[k]
    for s in (-1, 1):
        # точки на r0 и r1, смещённые вбок на half от оси прохода
        ax = Vector((math.cos(gang), math.sin(gang), 0)); side = Vector((-ax.y, ax.x, 0)) * s
        p0 = ax * r0 + side * half; p1 = ax * r1 + side * half
        pts = [p0 + Vector((0, 0, z0)), p1 + Vector((0, 0, z0)), p1 + Vector((0, 0, z1)), p0 + Vector((0, 0, z1))]
        if s < 0:
            pts = pts[::-1]
        B.face(pts, mi(k), [(0, z0 / t), ((r1 - r0) / t, z0 / t), ((r1 - r0) / t, z1 / t), (0, z1 / t)][::(1 if s > 0 else -1)])


def cuboid(B, c, size, rot, k_top, k_side, rx=0.0):
    """Коробка: c — центр, size (x,y,z), rot — поворот вокруг Z (рад). UV в метрах."""
    R = Matrix.Rotation(rot, 3, "Z") @ Matrix.Rotation(rx, 3, "X")
    hx, hy, hz = size[0] / 2, size[1] / 2, size[2] / 2
    corners = [Vector((sx * hx, sy * hy, sz * hz)) for sz in (-1, 1) for sy in (-1, 1) for sx in (-1, 1)]
    w = [c + R @ q for q in corners]
    F = [((0, 2, 3, 1), k_side, "z"), ((4, 5, 7, 6), k_top, "z"), ((0, 1, 5, 4), k_side, "y"), ((2, 6, 7, 3), k_side, "y"),
         ((0, 4, 6, 2), k_side, "x"), ((1, 3, 7, 5), k_side, "x")]
    for idx, k, ax in F:
        t = TILE.get(k, 2.0)
        loc = [corners[i] for i in idx]
        if ax == "z":
            uvs = [(q.x / t + c.x / t, q.y / t + c.y / t) for q in loc]
        elif ax == "y":
            uvs = [(q.x / t, (q.z + c.z) / t) for q in loc]
        else:
            uvs = [(q.y / t, (q.z + c.z) / t) for q in loc]
        B.face([w[i] for i in idx], mi(k), uvs)


def stairs(B, ang, r0, z0, r1, z1, width, k_tread, k_riser, steps):
    """Лестница вдоль радиуса ang от (r0, z0) к (r1, z1): ступени-коробки до земли (z = min)."""
    ax = Vector((math.cos(ang), math.sin(ang), 0))
    zb = min(z0, z1)
    for i in range(steps):
        u0, u1 = i / steps, (i + 1) / steps
        ra, rb = r0 + (r1 - r0) * u0, r0 + (r1 - r0) * u1
        zt = z0 + (z1 - z0) * (u1 if z1 > z0 else u0)
        zt = z0 + (z1 - z0) * ((i + 1) / steps) if z1 > z0 else z0 - (z0 - z1) * (i / steps)
        c = ax * ((ra + rb) / 2) + Vector((0, 0, (zt + zb) / 2))
        cuboid(B, c, (abs(rb - ra), width, zt - zb), ang, k_tread, k_riser)


def balustrade(B, path, z, k_post="marble", k_rail="marble", post_every=2.2, h=0.95):
    """Балюстрада по ломаной path [(x, y)]: столбики, верхний и нижний поручни, фигурные балясины."""
    for (x0, y0), (x1, y1) in zip(path[:-1], path[1:]):
        p0, p1 = Vector((x0, y0, z)), Vector((x1, y1, z))
        d = p1 - p0
        L = d.length
        if L < 0.05:
            continue
        rot = math.atan2(d.y, d.x)
        cuboid(B, (p0 + p1) / 2 + Vector((0, 0, h - 0.06)), (L + 0.02, 0.24, 0.12), rot, k_rail, k_rail)    # поручень
        cuboid(B, (p0 + p1) / 2 + Vector((0, 0, 0.09)), (L + 0.02, 0.26, 0.18), rot, k_rail, k_rail)        # цоколь
        nb = max(1, int(L / 0.32))
        for i in range(nb):                                   # балясины
            q = p0 + d * ((i + 0.5) / nb)
            cuboid(B, q + Vector((0, 0, 0.18 + (h - 0.3) / 2)), (0.1, 0.1, h - 0.3), rot + math.pi / 4, k_rail, k_rail)
    for (x, y) in path:                                       # столбы с навершием
        p = Vector((x, y, z))
        cuboid(B, p + Vector((0, 0, (h + 0.25) / 2)), (0.32, 0.32, h + 0.25), 0.0, k_post, k_post)
        cuboid(B, p + Vector((0, 0, h + 0.33)), (0.22, 0.22, 0.16), math.pi / 4, "gold", "gold")


def arc_path(r, a0, a1, step=2.4):
    n = max(1, int(abs(a1 - a0) * r / step))
    return [(math.cos(a0 + (a1 - a0) * i / n) * r, math.sin(a0 + (a1 - a0) * i / n) * r) for i in range(n + 1)]


def pavilion(B, c, size=4.0, hcol=3.2):
    """Беседка: четыре лакированные колонны на мраморном подиуме, балки, вальмовая крыша с загнутыми углами."""
    s = size / 2
    cuboid(B, c + Vector((0, 0, 0.15)), (size + 0.6, size + 0.6, 0.3), 0.0, "marble", "marble")
    for sx in (-1, 1):
        for sy in (-1, 1):
            p = c + Vector((sx * (s - 0.25), sy * (s - 0.25), 0.3))
            for k in range(8):                                   # колонна — восьмигранник
                a0, a1 = k * math.pi / 4, (k + 1) * math.pi / 4
                r = 0.18
                q0, q1 = Vector((math.cos(a0) * r, math.sin(a0) * r, 0)), Vector((math.cos(a1) * r, math.sin(a1) * r, 0))
                B.face([p + q0, p + q1, p + q1 + Vector((0, 0, hcol)), p + q0 + Vector((0, 0, hcol))], mi("lacquer"),
                       [(k * 0.15, 0), ((k + 1) * 0.15, 0), ((k + 1) * 0.15, hcol / 2), (k * 0.15, hcol / 2)])
            cuboid(B, p + Vector((0, 0, 0.12)), (0.5, 0.5, 0.24), 0.0, "marble", "marble")
    zt = 0.3 + hcol                                  # от подиума беседки (c — его центр на полу галереи)
    for sy in (-1, 1):                                            # балки и золотая обвязка
        cuboid(B, c + Vector((0, sy * (s - 0.25), zt + 0.15)), (size + 0.2, 0.3, 0.3), 0.0, "lacquer", "lacquer")
        cuboid(B, c + Vector((sy * (s - 0.25), 0, zt + 0.15)), (0.3, size + 0.2, 0.3), 0.0, "lacquer", "lacquer")
        cuboid(B, c + Vector((0, sy * (s - 0.25), zt - 0.05)), (size, 0.32, 0.1), 0.0, "gold", "gold")
    # крыша: четыре ската от карниза (с загибом вверх на углах) к коньку
    e = s + 1.3
    zr = zt + 0.3
    ridge = 0.9
    top = zr + 1.9
    corners = [Vector((-e, -e, zr + 0.45)), Vector((e, -e, zr + 0.45)), Vector((e, e, zr + 0.45)), Vector((-e, e, zr + 0.45))]
    mids = [Vector((0, -e, zr)), Vector((e, 0, zr)), Vector((0, e, zr)), Vector((-e, 0, zr))]
    rid = [Vector((-ridge, 0, top)), Vector((ridge, 0, top))]
    t = TILE["roof"]
    def tri(p, k="roof"):
        B.face([c + q for q in p], mi(k), [((q.x + q.y) / t, q.z / t * 1.6) for q in p])
    # юг/север — трапеции из двух половин с прогибом по середине
    tri([corners[0], mids[0], rid[0] + Vector((0, 0, 0))]); tri([mids[0], corners[1], rid[1]]); tri([mids[0], rid[1], rid[0]])
    tri([corners[2], mids[2], rid[1]]); tri([mids[2], corners[3], rid[0]]); tri([mids[2], rid[0], rid[1]])
    tri([corners[1], mids[1], rid[1]]); tri([mids[1], corners[2], rid[1]])
    tri([corners[3], mids[3], rid[0]]); tri([mids[3], corners[0], rid[0]])
    # низ крыши (виден снизу) — тёмный лак
    B.face([c + q for q in [corners[3], corners[2], corners[1], corners[0]]], mi("lacquer"), [(0, 0), (1, 0), (1, 1), (0, 1)])
    cuboid(B, c + Vector((0, 0, top + 0.12)), (2 * ridge + 0.6, 0.3, 0.25), 0.0, "gold", "gold")      # конёк
    for q in corners:                                              # золотые наконечники углов
        cuboid(B, c + q + Vector((0, 0, 0.12)), (0.25, 0.25, 0.35), math.pi / 4, "gold", "gold")


# ---------------------------------------------------------------- арена
A = Builder("arena_central")
N, S, E, W = math.pi / 2, -math.pi / 2, 0.0, math.pi
pit_gaps = [(N, GAP_PIT / 2), (S, GAP_PIT / 2)]
out_gaps = [(N, GAP_OUT / 2), (S, GAP_OUT / 2), (E, GAP_OUT / 2), (W, GAP_OUT / 2)]
# пол ямы: мозаика в центре, полосы и кольца мощения (как на площади Дасянчэн)
annulus(A, 0.0, 3.6, 0.02, "mosaic", seg=96)
annulus(A, 3.6, 4.1, 0.02, "band", seg=128)
annulus(A, 4.1, 8.8, 0.02, "paving")
annulus(A, 8.8, 9.3, 0.02, "band")
annulus(A, 9.3, PIT, 0.02, "slab")
# парапет ямы с проходами
annulus(A, PIT, PIT + PAR, PAR_H, "marble", gaps=pit_gaps)
ring_wall(A, PIT, 0.0, PAR_H, "wall", False, gaps=pit_gaps)
# трибуны: ярусы до высоты галереи (у последнего — уровень галереи)
for i in range(TIERS):
    r0 = PIT + PAR + i * TIER_D
    r1 = r0 + TIER_D
    zt = PAR_H + (H - PAR_H) * (i + 1) / TIERS if i < TIERS - 1 else H
    zprev = PAR_H if i == 0 else PAR_H + (H - PAR_H) * i / TIERS
    annulus(A, r0, r1, zt, "slab", gaps=pit_gaps)
    ring_wall(A, r0, zprev, zt, "wall", False, gaps=pit_gaps)
# галерея и наружная подпорная стена
annulus(A, GAL_IN, GAL_OUT, H, "slab", gaps=[])
ring_wall(A, GAL_OUT, 0.0, H, "wall", True, gaps=out_gaps)
for g in out_gaps:                                    # карниз
    pass
# проходы в яму: лестницы с галереи вниз, боковые стенки
for gang in (N, S):
    stairs(A, gang, GAL_IN, H, PIT, 0.0, GAP_PIT - 0.05, "slab", "wall", STAIR_N)
    gap_side(A, PIT, GAL_IN, 0.0, H + 0.0, gang, GAP_PIT / 2, "wall")
# наружные лестницы на четыре стороны с мраморными щеками
for gang in (N, S, E, W):
    stairs(A, gang, GAL_OUT, H, OUT_ST, 0.0, GAP_OUT, "slab", "wall", STAIR_N)
    ax = Vector((math.cos(gang), math.sin(gang), 0)); side = Vector((-ax.y, ax.x, 0))
    for s in (-1, 1):                                 # щёки лестницы — клин из коробок
        for i in range(STAIR_N):
            r = GAL_OUT + (i + 0.5) * STEP_D
            zt = H - i * STEP_H + 0.15
            cuboid(A, ax * r + side * s * (GAP_OUT / 2 + 0.3) + Vector((0, 0, zt / 2)), (STEP_D + 0.01, 0.6, zt), gang, "marble", "wall")
        path = [tuple((ax * GAL_OUT + side * s * (GAP_OUT / 2 + 0.3))[:2]), tuple((ax * OUT_ST + side * s * (GAP_OUT / 2 + 0.3))[:2])]
# балюстрада галереи — по внешнему краю, с разрывами у лестниц
for k, gang in enumerate((E, N, W, S)):
    span = (GAP_OUT / 2 + 0.6) / (GAL_OUT - 0.4)
    a0 = gang + span
    a1 = gang + math.pi / 2 - span
    balustrade(A, arc_path(GAL_OUT - 0.4, a0, a1), H)
# беседки на диагоналях галереи: каждая — своей сеткой у начала координат, потом развёрнута по радиусу
# (сторона подиума — поперёк галереи: не выступает ни к трибунам, ни за балюстраду) и присоединена к арене
PAV = []
for d in (45, 135, 225, 315):
    t = math.radians(d)
    pb = Builder("pav%d" % d)
    pavilion(pb, Vector((0, 0, 0)), size=2.2, hcol=2.8)
    po = pb.finish()
    po.location = pol((GAL_IN + GAL_OUT) / 2, t, H)
    po.rotation_euler = (0, 0, t)
    PAV.append(po)
# кольцо площади вокруг арены
annulus(A, OUT_ST, PLAZA, 0.02, "slab", gaps=[])
annulus(A, GAL_OUT, OUT_ST, 0.02, "band", gaps=out_gaps)
oa = A.finish()
bpy.ops.object.select_all(action="DESELECT")
for po in PAV:
    po.select_set(True)
oa.select_set(True)
bpy.context.view_layer.objects.active = oa
bpy.ops.object.join()

# ---------------------------------------------------------------- лестница Ставки
P = Builder("palace_stairs")
# в осях Blender: север = +Y; от y = PAL_Y0 (z 0) до PAL_Y1 (z PAL_H), два марша с площадкой посередине
steps1, steps2 = 10, 10
land_d = 1.2
run = (PAL_Y1 - PAL_Y0 - land_d) / 2
sh = PAL_H / (steps1 + steps2)
for i in range(steps1):
    y0 = PAL_Y0 + i * run / steps1; zt = (i + 1) * sh
    cuboid(P, Vector((0, y0 + run / steps1 / 2, zt / 2)), (PAL_W, run / steps1 + 0.01, zt), 0.0, "slab", "wall")
cuboid(P, Vector((0, PAL_Y0 + run + land_d / 2, steps1 * sh / 2)), (PAL_W, land_d + 0.01, steps1 * sh), 0.0, "slab", "wall")
for i in range(steps2):
    y0 = PAL_Y0 + run + land_d + i * run / steps2; zt = (steps1 + i + 1) * sh
    cuboid(P, Vector((0, y0 + run / steps2 / 2, zt / 2)), (PAL_W, run / steps2 + 0.01, zt), 0.0, "slab", "wall")
# щёки и балюстрада по сторонам
for s in (-1, 1):
    x = s * (PAL_W / 2 + 0.45)
    n = 24
    for i in range(n):
        y0 = PAL_Y0 + (PAL_Y1 - PAL_Y0) * i / n
        y1 = PAL_Y0 + (PAL_Y1 - PAL_Y0) * (i + 1) / n
        zt = PAL_H * (i + 1) / n + 0.2
        cuboid(P, Vector((x, (y0 + y1) / 2, zt / 2)), (0.9, y1 - y0 + 0.01, zt), 0.0, "marble", "wall")
    # поручень вдоль наклона: балюстрада ступенчато
    pts = [(x, PAL_Y0 + (PAL_Y1 - PAL_Y0) * i / 4) for i in range(5)]
    for i in range(4):
        zz = PAL_H * (i + 0.5) / 4 + 0.2
        balustrade(P, [pts[i], pts[i + 1]], zz)
# облицовка фасада террасы (перед коробкой террасы: 0.06 м — без наложения)
TW = 52.0
for s in (-1, 1):
    w = (TW - PAL_W - 1.8) / 2
    cx = s * (PAL_W / 2 + 0.9 + w / 2)
    cuboid(P, Vector((cx, PAL_Y1 + 0.06 - 0.2, PAL_H / 2)), (w, 0.4, PAL_H), 0.0, "marble", "wall")
    cuboid(P, Vector((cx, PAL_Y1 + 0.06 - 0.25, PAL_H + 0.1)), (w + 0.2, 0.55, 0.2), 0.0, "marble", "marble")   # карниз
    balustrade(P, [(s * (PAL_W / 2 + 0.9), PAL_Y1 + 0.3), (s * (TW / 2 - 0.3), PAL_Y1 + 0.3)], PAL_H)
op = P.finish()


def export(o, path):
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    # убрать неиспользуемые слоты материалов
    used = {p.material_index for p in o.data.polygons}
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_image_format="JPEG", export_jpeg_quality=92, export_materials="EXPORT")
    v = len(o.data.vertices); t = sum(len(p.vertices) - 2 for p in o.data.polygons)
    print(f"ARENA {o.name}: {v} verts, {t} tris → {path}", flush=True)


if OUT_S == "-":                                   # одной моделью: арена + лестница Ставки (общие материалы и текстуры)
    bpy.ops.object.select_all(action="DESELECT")
    op.select_set(True); oa.select_set(True)
    bpy.context.view_layer.objects.active = oa
    bpy.ops.object.join()
    oa.name = "central_plaza"
    export(oa, OUT_A)
else:
    export(oa, OUT_A)
    export(op, OUT_S)

if PREV:
    scn.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in [e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items] else "BLENDER_EEVEE"
    scn.render.resolution_x = 1600; scn.render.resolution_y = 1000
    op.location = (0, 0, 0)
    cam = bpy.data.objects.new("c", bpy.data.cameras.new("c")); scn.collection.objects.link(cam); scn.camera = cam
    cam.location = (30, -42, 26)
    cam.rotation_euler = (Vector((0, 4, 0)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.lens = 26
    sun = bpy.data.objects.new("s", bpy.data.lights.new("s", "SUN")); scn.collection.objects.link(sun)
    sun.rotation_euler = (0.9, 0.25, 0.7); sun.data.energy = 3.5
    w = bpy.data.worlds.new("w"); scn.world = w; w.color = (0.42, 0.38, 0.45)
    scn.render.filepath = PREV
    bpy.ops.render.render(write_still=True)
