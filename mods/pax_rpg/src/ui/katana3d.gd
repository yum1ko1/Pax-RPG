extends SubViewport
## Сцена для 3D-заставок с настоящими моделями оружия (models/weapons/*.glb): свой маленький мир с прозрачным
## фоном, ортокамера, три света (тёплый ключевой, холодный контровой, узкий «блик», который бежит по клинку).
## Картинка — get_texture(): её рисуют заставка входа в город и экраны загрузки. piece(path) — ещё одна модель
## (ножны, чужой клинок), повёрнутая острием вправо (+X); гарда — в нуле. Единицы — метры (катана ≈ 1 м).

const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")

var pivot: Node3D                   # вращаем его: roll — вокруг клинка, yaw/pitch — разворот
var glint: OmniLight3D              # бежит вдоль клинка: glint_at 0 — у гарды, 1 — у острия
var glint_at := -1.0:
	set(v):
		glint_at = v
		if glint != null:
			glint.visible = v >= 0.0 and v <= 1.0
			glint.position = Vector3(lerpf(-0.05, 0.78, clampf(v, 0.0, 1.0)), 0.06, 0.18)
var _model: Node3D
var cam: Camera3D
var _mod: PaxMod


func setup(mod: PaxMod, px: Vector2i, view_h := 0.55) -> void:
	_mod = mod
	size = px
	transparent_bg = true
	own_world_3d = true
	msaa_3d = Viewport.MSAA_4X
	render_target_update_mode = SubViewport.UPDATE_ALWAYS
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.7)
	env.ambient_light_energy = 0.6
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	var sky := Sky.new()                           # фон прозрачный, но сталь отражает небо Юрумы
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.3, 0.45, 0.85)
	sm.sky_horizon_color = Color(1.0, 0.65, 0.88)
	sm.ground_horizon_color = Color(0.85, 0.55, 0.8)
	sm.ground_bottom_color = Color(0.08, 0.08, 0.2)
	sky.sky_material = sm
	env.sky = sky
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = view_h                              # высота кадра, м
	cam.position = Vector3(0.0, 0.0, 3.0)
	add_child(cam)
	cam.current = true
	var key := DirectionalLight3D.new()            # тёплый ключевой сверху-спереди
	key.light_color = Color(1.0, 0.86, 0.75)
	key.light_energy = 1.6
	key.rotation_degrees = Vector3(-40, 20, 0)
	add_child(key)
	var rim := DirectionalLight3D.new()            # холодный контровой — серебрит кромку
	rim.light_color = Color(0.6, 0.8, 1.0)
	rim.light_energy = 2.2
	rim.rotation_degrees = Vector3(20, 160, 0)
	add_child(rim)
	pivot = piece("models/weapons/katana.glb")
	_model = pivot.get_child(0) as Node3D if pivot.get_child_count() > 0 else null
	glint = OmniLight3D.new()
	glint.light_color = Color(1.0, 0.95, 1.0)
	glint.light_energy = 9.0
	glint.omni_range = 0.22
	glint.visible = false
	add_child(glint)


## Модель на своём шарнире (Node3D): двигать и крутить шарнир. tint — окраска (чужой клинок — темнее).
func piece(path: String, tint := Color.WHITE) -> Node3D:
	var p := Node3D.new()
	add_child(p)
	var m := Assets.model(_mod, path)
	if m != null:
		m.rotation_degrees = Vector3(0, -90, 0)      # острие (−Z модели) → вправо (+X)
		p.add_child(m)
		for mi: Node in m.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if tint != Color.WHITE:
				for si: int in g.get_surface_override_material_count():
					var bm := g.mesh.surface_get_material(si) as BaseMaterial3D
					if bm != null:
						var c := bm.duplicate() as BaseMaterial3D
						c.albedo_color = bm.albedo_color * tint
						g.set_surface_override_material(si, c)
	return p


## Точка мира → пиксель картинки сцены.
func to_px(p: Vector3) -> Vector2:
	return cam.unproject_position(p)


func has_model() -> bool:
	return _model != null
