extends Node3D
## Погода и живой воздух локации. Погода — по часам мира (daynight.gd → world_hour) и дню: ясно, облачно, утренний
## туман, дождь; пока герой в локации, она не меняется (как и время). Что делает:
##  • глобальный pax_rpg_weather (x — мокрость 0..1, y — дождь 0..1, z — пасмурность, w — туман низин): его читают
##    ground / grass / foliage.gdshader (мокрая брусчатка и лужи, потемневшая трава), city.gd (мокрые материалы);
##  • тени облаков — большая декаль над локацией, медленно дрейфует по ветру; на стенах гаснет (normal_fade);
##  • небо (sky.gdshader: cloud_cover), туман окружения (высотный в низинах по утрам, объёмный гуще в дождь и на заре);
##  • дождь — штрихи вокруг камеры и шум дождя (sounds/rain_loop.wav);
##  • живой воздух: пылинки на свету днём, светлячки ночью у травы, мотыльки у фонарей (lights);
##  • следы ног героя (footprint) — декали, гаснут; на песке арены и в лесу заметнее.

const Prof := preload("res://mods/pax_rpg/src/location/prof.gd")
const KINDS := ["clear", "cloudy", "fog", "rain", "storm"]

static var forced := ""                 # консоль rpg_weather: погода для следующих локаций ("" — по дню мира)

const Vfx := preload("res://mods/pax_rpg/src/location/vfx.gd")
var mod: PaxMod
var kind := "clear"
var wet := 0.0
var rain := 0.0
var overcast := 0.0
var low_fog := 0.0
var _cam: Camera3D
var _rain: GPUParticles3D
var _rain_snd: AudioStreamPlayer
var _dust: Node3D                  # пыль и светлячки — частицы на видеокарте (vfx.gd → to_gpu)
var _flies: Node3D
var _shadow: Decal
var _prints: Array = []
var _print_tex: Texture2D
var _drift := Vector2.ZERO
var puddles := false                    # location.gd: земля — ground.gdshader (город), лужи на ней есть
var _player_pos := Vector3.INF          # location.gd → footprint: где земля у героя (брызги — вокруг него)
var _env: Environment
var _flash: DirectionalLight3D          # гроза: вспышка молнии
var _bolt_in := 4.0                     # до следующей молнии, с
var _flash_t := 0.0
var _thunder_in := -1.0                 # гром — позже вспышки (свет быстрее звука)
var _thunder: AudioStreamPlayer


## Какая погода сейчас: по дню мира и часу (детерминированно — тот же час, та же погода).
static func pick(hour: float, day_index: int) -> String:
	if forced != "":
		return forced
	var h := fmod(abs(sin(float(day_index) * 12.9898 + 4.1) * 43758.5453), 1.0)
	if hour >= 4.5 and hour < 8.5 and h < 0.45:
		return "fog"
	if h < 0.22:
		return "rain"
	if h < 0.55:
		return "cloudy"
	return "clear"


func setup(m: PaxMod, k: String, env: Environment, sky_mat: ShaderMaterial, cam: Camera3D, day: float,
		lamps: Array) -> void:
	mod = m
	kind = k
	name = "PaxRpgWeather"
	_cam = cam
	_env = env
	match kind:
		"storm":
			wet = 1.0
			rain = 1.0
			overcast = 1.0
		"rain":
			wet = 1.0
			rain = 1.0
			overcast = 0.85
		"cloudy":
			overcast = 0.55
			wet = 0.15
		"fog":
			low_fog = 1.0
			wet = 0.35
			overcast = 0.3
	RenderingServer.global_shader_parameter_set(&"pax_rpg_weather", Vector4(wet, rain, overcast, low_fog))
	if sky_mat != null:
		sky_mat.set_shader_parameter("cloud_cover", lerpf(0.5, 0.18, overcast))   # меньше порог — больше облаков
	if env != null:
		if low_fog > 0.0:                                  # туман в низинах (утро)
			env.fog_height = 1.5
			env.fog_height_density = 0.12
			env.fog_density = maxf(env.fog_density, 0.9)
		if env.volumetric_fog_enabled:                     # гуще в дождь и на заре — видны лучи
			env.volumetric_fog_density *= 1.0 + rain * 0.35 + low_fog * 1.2 + (1.0 - day) * 0.15   # дымка у глаза — едва
		if rain > 0.0:
			env.ambient_light_energy *= 0.85
			env.fog_light_color = env.fog_light_color.lerp(Color(0.55, 0.58, 0.68), 0.5)
	_make_cloud_shadows()
	if rain > 0.0:
		_make_rain()
	if kind == "storm":
		_make_storm()
	if day > 0.5 and rain <= 0.0:
		_make_dust()
	if day < 0.4 and rain <= 0.0:
		_make_flies()
	_make_moths(lamps, day)
	_to_gpu()


## Пыль, светлячки, мотыльки у фонарей — на видеокарту: CPUParticles3D считались процессором каждый кадр.
func _to_gpu() -> void:
	var list: Array = [_dust, _flies].filter(func(n: Variant) -> bool: return n is CPUParticles3D and is_instance_valid(n))
	for ol: Variant in _moth_lamps:
		if is_instance_valid(ol):
			list.append_array((ol as Node).find_children("*", "CPUParticles3D", false, false))
	var map := Vfx.to_gpu_list(list)
	_dust = map.get(_dust, _dust)
	_flies = map.get(_flies, _flies)
	_cam_last = Vector3.INF
	_moth_lamps.clear()


# ---------- тени облаков ----------

## Карта теней облаков: шум считает движок одним вызовом (get_image), порог — таблицей на 256 значений; раньше
## 65 536 вызовов get_noise_2d и set_pixel из GDScript — до 0.1 с на главном потоке при каждой загрузке города.
## Одинаковая погода — одна и та же карта (кэш по покрытию).
static var _cloud_cache := {}


static func _cloud_tex(cover: float) -> ImageTexture:
	var key := snappedf(cover, 0.01)
	if _cloud_cache.has(key):
		return _cloud_cache[key]
	var n := FastNoiseLite.new()
	n.seed = 77
	n.frequency = 0.012
	n.fractal_octaves = 4
	var src := n.get_image(256, 256, false, false, false)   # без нормировки: шум [-1, 1] → [0, 255], как noise*0.5+0.5
	if src.get_format() != Image.FORMAT_L8:
		src.convert(Image.FORMAT_L8)
	var lut := PackedByteArray()
	lut.resize(256)
	for i: int in 256:
		lut[i] = int(round(smoothstep(1.0 - key, 1.0 - key + 0.25, i / 255.0) * 0.55 * 255.0))
	var d := src.get_data()
	var px := PackedByteArray()
	px.resize(d.size() * 4)
	for i: int in d.size():
		px[i * 4 + 2] = 5                                     # чуть синевы в тени, как было (0.02)
		px[i * 4 + 3] = lut[d[i]]
	var img := Image.create_from_data(256, 256, false, Image.FORMAT_RGBA8, px)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_cloud_cache[key] = t
	return t


func _make_cloud_shadows() -> void:
	if overcast <= 0.05 and kind == "clear":
		overcast = 0.25                                    # и в ясный день — редкие облака
	_shadow = Decal.new()
	_shadow.texture_albedo = _cloud_tex(lerpf(0.25, 0.65, overcast))
	_shadow.size = Vector3(420.0, 120.0, 420.0)
	_shadow.albedo_mix = 1.0
	_shadow.normal_fade = 0.6                              # на стенах гаснет — только земля и крыши
	_shadow.upper_fade = 0.05
	_shadow.lower_fade = 0.05
	_shadow.modulate = Color(1, 1, 1, 0.9)
	_shadow.cull_mask = 0xFFFFF & ~(1 << 19)               # не на героя (слой героя — gfx.gd RIM_LAYER)
	add_child(_shadow)
	_shadow.position = Vector3(0, 20.0, 0)


# ---------- дождь ----------

func _make_rain() -> void:
	_cam_last = Vector3.INF                                 # новая система — встать к камере в ближайший кадр
	_rain = GPUParticles3D.new()
	_rain.amount = 7000
	_rain.lifetime = 1.0                                   # долетают до земли и в низинах, и на ровном
	_rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 50, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(14, 0.5, 14)        # ближе к камере — капли видны, а не тонут в дали
	pm.direction = Vector3(0.08, -1, 0.04)
	pm.spread = 3.0
	pm.initial_velocity_min = 18.0
	pm.initial_velocity_max = 22.0
	pm.gravity = Vector3(0, -9.8, 0)
	_rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.011, 0.5)                          # тонкие штрихи, а не палки
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.78, 0.83, 0.92, 0.38)
	mat.emission_enabled = true                          # ночью и в тени капли ловят свет — не исчезают
	mat.emission = Color(0.12, 0.13, 0.16)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	q.material = mat
	_rain.draw_pass_1 = q
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)
	_make_splashes()
	var st: AudioStream = mod.sound("sounds/storm_loop.mp3" if kind == "storm" else "sounds/rain_loop.mp3")   # гроза — с громом
	if st is AudioStreamMP3:
		(st as AudioStreamMP3).loop = true
	if st == null:
		st = mod.sound("sounds/rain_loop.wav")
	if st != null:
		if st is AudioStreamWAV:
			var wav := st as AudioStreamWAV
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_end = wav.data.size() / 2
		_rain_snd = AudioStreamPlayer.new()
		_rain_snd.stream = st
		_rain_snd.bus = "PaxRpgSfx"
		_rain_snd.volume_db = -10.0
		add_child(_rain_snd)
		_rain_snd.play()


## Брызги: короткие светлые всплески у земли вокруг героя — дождь видно и под ногами.
var _splash: GPUParticles3D


func _make_splashes() -> void:
	_splash_last = Vector3.INF
	_splash = GPUParticles3D.new()
	_splash.amount = 700
	_splash.lifetime = 0.25
	_splash.visibility_aabb = AABB(Vector3(-12, -3, -12), Vector3(24, 6, 24))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(10, 0.05, 10)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 35.0
	pm.initial_velocity_min = 0.6
	pm.initial_velocity_max = 1.4
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.6
	pm.scale_max = 1.2
	_splash.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.022, 0.022)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.9, 1.0, 0.5)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	q.material = mat
	_splash.draw_pass_1 = q
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_splash)


# ---------- живой воздух ----------

func _soft_dot(col: Color, size: float, emissive: float) -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = col * (1.0 + emissive)
	m.albedo_texture = _radial()
	m.vertex_color_use_as_albedo = true
	q.material = m
	return q


static var _rad: ImageTexture


static func _radial() -> ImageTexture:
	if _rad != null:
		return _rad
	var img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	for y: int in 32:
		for x: int in 32:
			var d := Vector2(x - 15.5, y - 15.5).length() / 15.5
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_rad = ImageTexture.create_from_image(img)
	return _rad


func _make_dust() -> void:
	_cam_last = Vector3.INF                                 # новая система — встать к камере в ближайший кадр
	_dust = CPUParticles3D.new()
	_dust.mesh = _soft_dot(Color(1.0, 0.95, 0.85, 0.5), 0.04, 0.2)
	_dust.amount = 220
	_dust.lifetime = 9.0
	_dust.preprocess = 9.0
	_dust.local_coords = false
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(9, 3, 9)
	_dust.gravity = Vector3(0.05, 0.02, 0.0)
	_dust.initial_velocity_min = 0.02
	_dust.initial_velocity_max = 0.12
	_dust.spread = 180.0
	_dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.3, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	_dust.color_ramp = g
	add_child(_dust)


func _make_flies() -> void:
	_cam_last = Vector3.INF                                 # новая система — встать к камере в ближайший кадр
	_flies = CPUParticles3D.new()
	_flies.mesh = _soft_dot(Color(0.75, 1.0, 0.45, 1.0), 0.07, 2.0)
	_flies.amount = 90
	_flies.lifetime = 6.0
	_flies.preprocess = 6.0
	_flies.local_coords = false
	_flies.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_flies.emission_box_extents = Vector3(18, 0.8, 18)
	_flies.gravity = Vector3.ZERO
	_flies.initial_velocity_min = 0.1
	_flies.initial_velocity_max = 0.4
	_flies.spread = 180.0
	_flies.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var g := Gradient.new()                                 # мерцают: вспыхивают и гаснут
	g.set_color(0, Color(1, 1, 1, 0))
	g.add_point(0.2, Color(1, 1, 1, 1))
	g.add_point(0.35, Color(1, 1, 1, 0.1))
	g.add_point(0.6, Color(1, 1, 1, 1))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	_flies.color_ramp = g
	add_child(_flies)


func _make_moths(lamps: Array, day: float) -> void:
	if day > 0.6:
		return
	var mesh := _soft_dot(Color(1.0, 0.9, 0.7, 0.8), 0.035, 0.5)
	var used := 0
	for l: Variant in lamps:
		var ol: Node3D = (l as Array)[0] if l is Array else null
		if ol == null or not is_instance_valid(ol) or used >= 24:
			continue
		used += 1
		var p := CPUParticles3D.new()
		p.mesh = mesh
		p.amount = 8
		p.lifetime = 2.5
		p.preprocess = 2.5
		p.local_coords = true
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
		p.emission_sphere_radius = 0.6
		p.gravity = Vector3.ZERO
		p.orbit_velocity_min = 0.3
		p.orbit_velocity_max = 0.8
		p.initial_velocity_min = 0.3
		p.initial_velocity_max = 0.9
		p.spread = 180.0
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_range_end = 35.0
		ol.add_child(p)
		_moth_lamps.append(ol)


var _moth_lamps: Array = []


# ---------- следы ----------

## В луже ли точка (тот же шум, что у луж в ground.gdshader; край — середина перехода).
static func _h2(x: float, y: float) -> float:
	var a := fposmod(x * 0.1031, 1.0)
	var b := fposmod(y * 0.1031, 1.0)
	var c := a
	var d := a * (b + 33.33) + b * (c + 33.33) + c * (a + 33.33)
	a += d
	b += d
	c += d
	return fposmod((a + b) * c, 1.0)


static func _pn(x: float, y: float) -> float:
	var ix := floorf(x)
	var iy := floorf(y)
	var fx := x - ix
	var fy := y - iy
	var ux := fx * fx * (3.0 - 2.0 * fx)
	var uy := fy * fy * (3.0 - 2.0 * fy)
	return lerpf(lerpf(_h2(ix, iy), _h2(ix + 1.0, iy), ux), lerpf(_h2(ix, iy + 1.0), _h2(ix + 1.0, iy + 1.0), ux), uy)


func puddle_at(pos: Vector3) -> bool:
	if not puddles or wet < 0.3:
		return false
	var pn := _pn(pos.x * 0.11 + 7.3, pos.z * 0.11 + 7.3) * 0.8 + _pn(pos.x * 0.45, pos.z * 0.45) * 0.2
	return pn > 0.612


var _drop_mesh: QuadMesh
var _ring_mesh: TorusMesh


## Шаг в луже: брызги-капли вверх и в стороны, кольцо по воде.
func splash(pos: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.one_shot = true
	p.emitting = false
	p.amount = 18
	p.lifetime = 0.45
	p.explosiveness = 0.95
	p.direction = Vector3(0, 1, 0)
	p.spread = 55.0
	p.initial_velocity_min = 1.2
	p.initial_velocity_max = 2.6
	p.gravity = Vector3(0, -9.8, 0)
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	if _drop_mesh == null:                                  # капля — одна сетка и материал на все шаги (были новые на каждый)
		_drop_mesh = QuadMesh.new()
		_drop_mesh.size = Vector2(0.035, 0.035)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.82, 0.88, 0.95, 0.65)
		mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		_drop_mesh.material = mat
	p.mesh = _drop_mesh
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	p.global_position = pos + Vector3(0, 0.04, 0)
	p.emitting = true
	# кольцо по воде: плоское, растёт и тает
	var ring := MeshInstance3D.new()
	if _ring_mesh == null:                                  # сетка кольца — общая; материал свой (тает альфой)
		_ring_mesh = TorusMesh.new()
		_ring_mesh.inner_radius = 0.16
		_ring_mesh.outer_radius = 0.2
		_ring_mesh.rings = 24
		_ring_mesh.ring_segments = 4
	ring.mesh = _ring_mesh
	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.albedo_color = Color(0.85, 0.9, 1.0, 0.45)
	ring.material_override = rmat
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.scale = Vector3(1.0, 0.05, 1.0)
	add_child(ring)
	ring.global_position = pos + Vector3(0, 0.02, 0)
	var tw := ring.create_tween().set_parallel(true)
	tw.tween_property(ring, "scale", Vector3(3.2, 0.05, 3.2), 0.6).set_ease(Tween.EASE_OUT)
	tw.tween_property(rmat, "albedo_color:a", 0.0, 0.6)
	tw.chain().tween_callback(ring.queue_free)
	get_tree().create_timer(1.0).timeout.connect(p.queue_free)


func footprint(pos: Vector3, yaw: float, left: bool) -> void:
	if puddle_at(pos):
		splash(pos)
		_player_pos = pos
		return                                              # в воде след не остаётся
	if _print_tex == null:
		var img := Image.create(32, 64, false, Image.FORMAT_RGBA8)
		for y: int in 64:
			for x: int in 32:
				var u := (x - 15.5) / 11.0
				var v := (y - 31.5) / 28.0
				var heel := Vector2(u, (v - 0.55) * 1.6).length()
				var sole := Vector2(u * 0.9, (v + 0.2) * 1.0).length()
				var a := clampf(1.0 - minf(heel, sole), 0.0, 1.0)
				img.set_pixel(x, y, Color(0.12, 0.09, 0.07, smoothstep(0.0, 0.35, a) * 0.6))
		img.generate_mipmaps()
		_print_tex = ImageTexture.create_from_image(img)
	var d := Decal.new()
	d.texture_albedo = _print_tex
	d.size = Vector3(0.16, 0.12, 0.3)                       # тонкая проекция: только земля под ногой, не предметы рядом
	d.albedo_mix = 1.0
	d.normal_fade = 0.5
	d.cull_mask = 0xFFFFF & ~(1 << 19)
	add_child(d)
	_player_pos = pos
	var side := Vector3(cos(yaw), 0.0, -sin(yaw)) * (0.11 if left else -0.11)
	var at := pos + side
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	if space != null:                                       # земля под ногой — лучом вниз (след ложится точно на неё)
		var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 1.0, 0), at - Vector3(0, 3.0, 0))
		q.collision_mask = 1
		var r := space.intersect_ray(q)
		if r.has("position"):
			at.y = (r.position as Vector3).y
	d.global_position = at + Vector3(0, 0.02, 0)
	d.rotation.y = yaw
	d.modulate = Color(1, 1, 1, 0.9 if wet > 0.3 else 0.6)
	_prints.append(d)
	if _prints.size() > 60:
		var old: Variant = _prints.pop_front()             # мог уже истаять и уйти (ниже) — без типа
		if is_instance_valid(old):
			(old as Decal).queue_free()
	var tw := d.create_tween()
	tw.tween_interval(14.0)
	tw.tween_property(d, "modulate:a", 0.0, 4.0)
	tw.tween_callback(d.queue_free)                         # истаявший след — вон: невидимая декаль всё равно
	                                                        # считалась в кластерах и на каждом пикселе земли рядом


var _cam_last := Vector3.INF
var _splash_last := Vector3.INF
var _shadow_at := Vector3.INF


func _process(delta: float) -> void:
	preload("res://mods/pax_rpg/src/trace.gd").tick("weather._process")
	var t0 := Time.get_ticks_usec()
	if is_instance_valid(_cam):
		var cp := _cam.global_position
		# дождь, пыль и светлячки едут за камерой — только когда она сдвинулась (каждое присваивание — пересчёт
		# трансформа и вызов в сервер рендера на каждую систему частиц)
		if cp != _cam_last:
			_cam_last = cp
			if _rain != null:
				_rain.global_position = cp + Vector3(0, 14, 0)
			if _dust != null:
				_dust.global_position = cp + Vector3(0, -0.5, 0)
			if _flies != null:
				_flies.global_position = Vector3(cp.x, cp.y - 1.8, cp.z)
		if _splash != null and _player_pos != Vector3.INF and _player_pos != _splash_last:
			_splash_last = _player_pos
			_splash.global_position = _player_pos + Vector3(0, 0.05, 0)
		if _shadow != null:                                 # облака плывут по ветру
			_drift += Vector2(delta, delta)                 # плавно туда-обратно (без скачка при повторе)
			var sp := Vector3(sin(_drift.x * 0.006) * 70.0, 20.0, sin(_drift.y * 0.0041 + 1.3) * 70.0)
			# плывут ≤ 0.42 м/с, клетка тени — 1.6 м и мягкая: ставим раз в 2 см (раз в ~5 кадров), а не каждый кадр
			if sp.distance_squared_to(_shadow_at) > 0.0004:
				_shadow_at = sp
				_shadow.global_position = sp
	if _flash != null:
		_storm_tick(delta)
	Prof.add("погода", t0)


# ---------- гроза ----------

func _make_storm() -> void:
	if _rain != null:                                       # ливень гуще и косой
		_rain.amount = 9000
		var pm := _rain.process_material as ParticleProcessMaterial
		pm.direction = Vector3(0.3, -1, 0.12)
	if _env != null:
		_env.ambient_light_energy *= 0.8
	_flash = DirectionalLight3D.new()
	_flash.light_color = Color(0.8, 0.85, 1.0)
	_flash.light_energy = 0.0
	_flash.shadow_enabled = false
	_flash.rotation_degrees = Vector3(-65, 30, 0)
	add_child(_flash)
	if not (_rain_snd != null and _rain_snd.stream is AudioStreamMP3):   # в записи грозы гром уже есть — свой не нужен
		_thunder = AudioStreamPlayer.new()
		_thunder.stream = _thunder_wav()
		_thunder.bus = "PaxRpgSfx"
		add_child(_thunder)
	_bolt_in = randf_range(2.0, 5.0)


func _storm_tick(delta: float) -> void:
	_bolt_in -= delta
	if _bolt_in <= 0.0:
		_bolt_in = randf_range(6.0, 16.0)
		_flash_t = 0.45
		_thunder_in = randf_range(0.4, 2.5)
	if _flash_t > 0.0:                                      # две-три вспышки подряд
		_flash_t -= delta
		var k := _flash_t / 0.45
		_flash.light_energy = (6.0 if fmod(_flash_t, 0.15) > 0.07 else 1.5) * k
	elif _flash.light_energy != 0.0:                       # погасла — один раз, а не запись нуля каждый кадр
		_flash.light_energy = 0.0
	if _thunder_in > 0.0:
		_thunder_in -= delta
		if _thunder_in <= 0.0 and _thunder != null:
			_thunder.volume_db = randf_range(-6.0, 0.0)
			_thunder.pitch_scale = randf_range(0.8, 1.15)
			_thunder.play()


## Гром без файла: бурый шум с резким началом и долгим раскатистым затуханием.
func _thunder_wav() -> AudioStreamWAV:
	var rate := 22050
	var n := rate * 4
	var data := PackedByteArray()
	data.resize(n * 2)
	var b := 0.0
	var roll := 0.0
	for i in n:
		var t := float(i) / rate
		b = clampf(b + randf_range(-1.0, 1.0) * 0.06, -1.0, 1.0) * 0.995
		roll = 0.6 + 0.4 * sin(t * 5.0 + sin(t * 1.7) * 3.0)
		var env := minf(1.0, t * 30.0) * exp(-t * 1.1) * roll
		data.encode_s16(i * 2, int(clampf(b * env * 2.5, -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w
