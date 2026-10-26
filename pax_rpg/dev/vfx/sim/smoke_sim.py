"""Клуб дыма — настоящая симуляция газа (Blender Mantaflow), из неё флипбук для частиц дыма (make_smoke_atlas.py).
Запуск (на ПК, фоном — без окна и без мышки):
  blender -b -P smoke_sim.py -- <папка> [bake|render|peek|all] [res] [gpu|cpu]
Клуб — как из трубы: короткий выдох вверх, дальше тёплый дым сам всплывает, заворачивается вихревым кольцом,
клубится «цветной капустой», растёт и тает. Всплытие из кадра убирает make_smoke_atlas.py (кадр — по центру клуба),
подъём и ветер в игре даёт частица.
peek — быстрый просмотр формы: каждый 8-й кадр, свет сверху и справа, мало сэмплов.
render — кадры F_A..F_B в <папка>/frames, по одному на каждый из 6 источников света (свет «с 6 сторон», 6-way
lighting — как дым освещают в больших играх: в игре свет солнца, луны и огней смешивает эти 6 картинок):
  s_<d>_####.png, d: r — свет справа, l — слева, t — сверху, b — снизу, f — спереди (со стороны камеры), k — сзади;
  RGBA 16 бит, альфа — плотность (у всех шести одна)."""
import bpy, sys, os, math
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = argv[0] if argv else os.path.join(os.getcwd(), "smoke_sim")
mode = argv[1] if len(argv) > 1 else "all"
res = int(argv[2]) if len(argv) > 2 else 96
dev = argv[3] if len(argv) > 3 else "gpu"
F0, F1 = 1, 80
F_A, F_B = 6, 69                    # 64 кадра жизни клуба
W, H = 2.4, 4.0                     # домен, м: клуб всплывает
RX, RY = 240, 400                   # кадр, px (0.01 м/px; make_smoke_atlas.py вырезает квадрат W×W вокруг клуба)
DENS_K = 30.0                       # плотность в рендере: густой клуб сам себя затеняет — видно, откуда свет

os.makedirs(out, exist_ok=True)
BLEND = os.path.join(out, "smoke.blend")
reuse = mode in ("render", "peek") and os.path.exists(BLEND)
if reuse:                                          # газ уже посчитан: сцена с ним (флаг «запечено» живёт в .blend)
    bpy.ops.wm.open_mainfile(filepath=BLEND)
    sc = bpy.context.scene
    dom = bpy.data.objects["domain"]
else:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene


def setup():
    global dom
    sc.frame_start, sc.frame_end = F0, F1
    sc.render.fps = 30
    bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0, H / 2))
    dom = bpy.context.object
    dom.name = "domain"
    dom.scale = (W, W, H)
    bpy.ops.object.transform_apply(scale=True)
    md = dom.modifiers.new("fluid", "FLUID")
    md.fluid_type = "DOMAIN"
    ds = md.domain_settings
    ds.domain_type = "GAS"
    ds.resolution_max = res
    ds.cache_directory = os.path.join(out, "cache")
    ds.cache_type = "ALL"
    ds.cache_frame_start, ds.cache_frame_end = F0, F1
    ds.use_adaptive_domain = False
    ds.alpha = 0.6                  # тёплый дым всплывает и сам заворачивается
    ds.beta = 1.2
    ds.vorticity = 0.35             # клубится
    ds.use_dissolve_smoke = True
    ds.use_dissolve_smoke_log = True
    ds.dissolve_speed = 70          # к концу жизни клуб почти растаял
    ds.time_scale = 0.75
    for b in ("front", "back", "left", "right", "top", "bottom"):   # края открыты: дым уходит, а не копится
        setattr(ds, "use_collision_border_" + b, False)
    ds.use_noise = True             # мелкие завитки по краю клуба (upres ×2)
    ds.noise_scale = 2
    ds.noise_strength = 1.6
    ds.noise_pos_scale = 2.5

    # выдох трубы: диск, в первые кадры дует дымом вверх (вихревое кольцо), потом уходит из домена
    bpy.context.preferences.edit.keyframe_new_interpolation_type = "CONSTANT"
    bpy.ops.mesh.primitive_cylinder_add(radius=0.3, depth=0.3, location=(0, 0, 0.45), vertices=48)
    src = bpy.context.object
    src.name = "puff"
    mf = src.modifiers.new("fluid", "FLUID")
    mf.fluid_type = "FLOW"
    fs = mf.flow_settings
    fs.flow_type = "SMOKE"
    fs.flow_behavior = "INFLOW"
    fs.flow_source = "MESH"
    fs.surface_distance = 0.4
    fs.density = 1.0
    fs.smoke_color = (1, 1, 1)
    fs.use_initial_velocity = True
    fs.temperature = 1.5
    fs.velocity_normal = 0.4
    fs.velocity_coord = (0.0, 0.0, 2.6)
    tex = bpy.data.textures.new("lumps", "CLOUDS")
    tex.noise_scale = 0.12             # подача пятнами — клуб неровный с самого начала
    tex.contrast = 2.2
    fs.use_texture = True
    fs.noise_texture = tex
    fs.texture_map_type = "AUTO"
    src.keyframe_insert("location", frame=F0)
    src.keyframe_insert("location", frame=F0 + 6)
    src.location = (0, 0, -10.0)                    # прыжком за домен: дует только первые кадры
    src.keyframe_insert("location", frame=F0 + 7)
    act = src.animation_data.action
    curves = list(getattr(act, "fcurves", []) or [])
    for layer in getattr(act, "layers", []):        # Blender 5: кривые — в слоях действия
        for strip in layer.strips:
            for cb in strip.channelbags:
                curves += list(cb.fcurves)
    for fc in curves:
        for kp in fc.keyframe_points:
            kp.interpolation = "CONSTANT"
    src.hide_render = True
    return dom


if not reuse:
    setup()
bpy.context.view_layer.objects.active = dom
if mode in ("bake", "all"):
    with bpy.context.temp_override(object=dom, active_object=dom, selected_objects=[dom], scene=sc):
        bpy.ops.fluid.bake_all()
    bpy.ops.wm.save_as_mainfile(filepath=BLEND)
    print("baked", flush=True)

DIRS = {"r": (1, 0, 0), "l": (-1, 0, 0), "t": (0, 0, 1), "b": (0, 0, -1), "f": (0, -1, 0), "k": (0, 1, 0)}

if mode in ("render", "peek", "all"):
    r = sc.render
    r.engine = "CYCLES"
    cy = sc.cycles
    if dev == "gpu":
        pr = bpy.context.preferences.addons["cycles"].preferences
        for t in ("OPTIX", "CUDA"):
            try:
                pr.compute_device_type = t
                pr.get_devices()
                if any(d.type == t for d in pr.devices):
                    break
            except Exception:
                pass
        for d in pr.devices:
            d.use = d.type != "CPU"
        cy.device = "GPU"
    cy.samples = 96 if mode != "peek" else 24
    cy.use_denoising = True
    cy.denoiser = "OPENIMAGEDENOISE"
    cy.volume_step_rate = 0.4
    cy.volume_max_steps = 2048
    cy.max_bounces = 6
    cy.volume_bounces = 1            # дым светится изнутри рассеянным светом — мягкий, а не «картонный»
    r.resolution_x, r.resolution_y = RX, RY
    r.resolution_percentage = 100
    r.film_transparent = True
    r.image_settings.file_format = "PNG"
    r.image_settings.color_mode = "RGBA"
    r.image_settings.color_depth = "16"
    try:
        sc.view_settings.view_transform = "Raw"
    except Exception:
        sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"

    m = bpy.data.materials.new("smoke")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    v = nt.nodes.new("ShaderNodeVolumePrincipled")
    v.inputs["Color"].default_value = (0.85, 0.85, 0.85, 1)
    v.inputs["Anisotropy"].default_value = 0.2
    a = nt.nodes.new("ShaderNodeAttribute")
    a.attribute_name = "density"
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = DENS_K
    nt.links.new(a.outputs["Fac"], mul.inputs[0])
    nt.links.new(mul.outputs[0], v.inputs["Density"])
    nt.links.new(v.outputs[0], o.inputs["Volume"])
    dom.data.materials.clear()
    dom.data.materials.append(m)

    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = H
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    cam.location = (0, -8, H / 2)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.camera = cam

    sun_d = bpy.data.lights.new("sun", "SUN")
    sun_d.energy = 4.0
    sun_d.angle = math.radians(5)
    sun = bpy.data.objects.new("sun", sun_d)
    sc.collection.objects.link(sun)
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    sc.world = world

    fr = os.path.join(out, "frames")
    os.makedirs(fr, exist_ok=True)
    peek = mode == "peek"
    for f in (range(F_A, F_B + 1, 8) if peek else range(F_A, F_B + 1)):
        sc.frame_set(f)
        for k, d in DIRS.items():
            if peek and k not in "tr":
                continue
            # свет «с той стороны»: лучи солнца идут от d к центру
            sun.rotation_euler = (-Vector(d)).to_track_quat("-Z", "Y").to_euler()
            r.filepath = os.path.join(fr, "s_%s_%04d.png" % (k, f))
            bpy.ops.render.render(write_still=True)
        print("frame", f, flush=True)
    print("rendered", flush=True)
