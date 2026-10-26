"""Огонь жаровни — настоящая симуляция газа (Blender Mantaflow), из неё флипбук для игры (make_fire_atlas.py).
Запуск (на ПК, фоном — без окна и без мышки):
  blender -b -P fire_sim.py -- <папка> [bake|render|all] [res] [gpu|cpu]
bake   — газ (пламя + дым) в <папка>/cache;
render — кадры F_A..F_B в <папка>/frames, два прохода Cycles на кадр (ортокамера сбоку, без перспективы):
  e_####.png — свечение пламени, 16 бит линейно (одна величина: цвет по жару даёт шейдер игры);
  s_####.png — дым, RGBA 16 бит: освещён сверху-спереди мягким солнцем, альфа — плотность.
E_K — масштаб свечения: подобран так, чтобы ядро пламени не упиралось в 1.0."""
import bpy, sys, os, math

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
out = argv[0] if argv else os.path.join(os.getcwd(), "fire_sim")
mode = argv[1] if len(argv) > 1 else "all"
res = int(argv[2]) if len(argv) > 2 else 110
dev = argv[3] if len(argv) > 3 else "gpu"
F0, F1 = 1, 170
F_A, F_B = 81, 160                 # 80 кадров установившегося горения: 64 в петлю + 16 на перехлёст
W, H = 1.3, 2.6                    # домен, м: огонь в чаше ~0.6 м, языки до ~1.5 м
RX, RY = 256, 512                  # кадр
E_K = 0.6                          # масштаб свечения в PNG (линейно, 1.0 = белое)

os.makedirs(out, exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
sc = bpy.context.scene
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
ds.vorticity = 0.15
ds.alpha = 0.3                     # подъём от плотности дыма
ds.beta = 1.8                      # подъём от жара — языки тянутся вверх и рвутся
ds.burning_rate = 0.9
ds.flame_smoke = 0.5
ds.flame_vorticity = 1.0
ds.flame_ignition = 1.25
ds.flame_max_temp = 3.0
ds.use_dissolve_smoke = True
ds.use_dissolve_smoke_log = True
ds.dissolve_speed = 45
ds.time_scale = 0.85
ds.use_noise = True                # мелкие вихри поверх основного газа (upres ×2) — рваный край пламени
ds.noise_scale = 2
ds.noise_strength = 1.2
ds.noise_pos_scale = 2.0
ds.use_collision_border_bottom = True

# «угли» в чаше: диск, подача рвётся текстурой облаков, текстура плывёт — пламя не стоит столбом
bpy.ops.mesh.primitive_cylinder_add(radius=0.3, depth=0.1, location=(0, 0, 0.14), vertices=32)
src = bpy.context.object
src.name = "coals"
mf = src.modifiers.new("fluid", "FLUID")
mf.fluid_type = "FLOW"
fs = mf.flow_settings
fs.flow_type = "BOTH"
fs.flow_behavior = "INFLOW"
fs.flow_source = "MESH"
fs.surface_distance = 0.5
fs.fuel_amount = 1.4
fs.temperature = 1.3
fs.density = 0.35
fs.smoke_color = (0.1, 0.09, 0.085)
tex = bpy.data.textures.new("flick", "CLOUDS")
tex.noise_scale = 0.09
tex.noise_depth = 2
fs.use_texture = True
fs.noise_texture = tex
fs.texture_map_type = "AUTO"
fs.texture_size = 1.0
fs.texture_offset = 0.0
fs.keyframe_insert("texture_offset", frame=F0)
fs.texture_offset = 9.0
fs.keyframe_insert("texture_offset", frame=F1)
for fc in (src.animation_data.action.fcurves if src.animation_data and src.animation_data.action else []):
    for k in fc.keyframe_points:
        k.interpolation = "LINEAR"
src.hide_render = True

bpy.context.view_layer.objects.active = dom
if mode in ("bake", "all"):
    with bpy.context.temp_override(object=dom, active_object=dom, selected_objects=[dom], scene=sc):
        bpy.ops.fluid.bake_all()
    print("baked")


def attr(nt, name):
    n = nt.nodes.new("ShaderNodeAttribute")
    n.attribute_name = name
    return n


def mat_emit():
    m = bpy.data.materials.new("emit")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = (1, 1, 1, 1)
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = 1.0
    nt.links.new(attr(nt, "flame").outputs["Fac"], mul.inputs[0])
    nt.links.new(mul.outputs[0], e.inputs["Strength"])
    nt.links.new(e.outputs[0], o.inputs["Volume"])
    return m


def mat_smoke():
    m = bpy.data.materials.new("smoke")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    v = nt.nodes.new("ShaderNodeVolumePrincipled")
    v.inputs["Color"].default_value = (0.5, 0.5, 0.5, 1)
    v.inputs["Anisotropy"].default_value = 0.25
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = 6.0
    nt.links.new(attr(nt, "density").outputs["Fac"], mul.inputs[0])
    nt.links.new(mul.outputs[0], v.inputs["Density"])
    nt.links.new(v.outputs[0], o.inputs["Volume"])
    return m


if mode in ("render", "all"):
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
    cy.samples = 64
    cy.use_denoising = False
    cy.volume_step_rate = 0.5
    cy.volume_max_steps = 2048
    cy.max_bounces = 4
    cy.volume_bounces = 1
    r.resolution_x, r.resolution_y = RX, RY
    r.resolution_percentage = 100
    r.image_settings.file_format = "PNG"
    r.image_settings.color_depth = "16"
    try:
        sc.view_settings.view_transform = "Raw"
    except Exception:
        sc.view_settings.view_transform = "Standard"
    sc.view_settings.look = "None"
    sc.view_settings.exposure = 0.0
    sc.view_settings.gamma = 1.0

    cam_d = bpy.data.cameras.new("cam")
    cam_d.type = "ORTHO"
    cam_d.ortho_scale = H
    cam = bpy.data.objects.new("cam", cam_d)
    sc.collection.objects.link(cam)
    cam.location = (0, -6, H / 2)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.camera = cam

    sun_d = bpy.data.lights.new("sun", "SUN")
    sun_d.energy = 3.0
    sun_d.angle = math.radians(12)
    sun = bpy.data.objects.new("sun", sun_d)
    sc.collection.objects.link(sun)
    sun.rotation_euler = (math.radians(35), math.radians(-25), 0)   # сверху, чуть спереди-сбоку
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    sc.world = world

    me, ms = mat_emit(), mat_smoke()
    dom.data.materials.clear()
    dom.data.materials.append(me)
    fr = os.path.join(out, "frames")
    os.makedirs(fr, exist_ok=True)
    for f in range(F_A, F_B + 1):
        sc.frame_set(f)
        # проход 1: только свечение пламени на чёрном
        dom.data.materials[0] = me
        me.node_tree.nodes["Math"].inputs[1].default_value = E_K
        r.film_transparent = False
        bg.inputs["Strength"].default_value = 0.0
        sun.hide_render = True
        cy.samples = 32
        r.filepath = os.path.join(fr, "e_%04d.png" % f)
        bpy.ops.render.render(write_still=True)
        # проход 2: дым, освещённый солнцем и слабым небом, фон прозрачный
        dom.data.materials[0] = ms
        r.film_transparent = True
        bg.inputs["Color"].default_value = (0.35, 0.38, 0.45, 1)
        bg.inputs["Strength"].default_value = 0.6
        sun.hide_render = False
        cy.samples = 64
        r.filepath = os.path.join(fr, "s_%04d.png" % f)
        bpy.ops.render.render(write_still=True)
        print("frame", f, flush=True)
    print("rendered")
