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
const KINDS := ["clear", "cloudy", "fog", "rain"]

var mod: PaxMod
var kind := "clear"
var wet := 0.0
var rain := 0.0
var overcast := 0.0
var low_fog := 0.0
var _cam: Camera3D
var _rain: GPUParticles3D
var _rain_snd: AudioStreamPlayer
var _dust: CPUParticles3D
var _flies: CPUParticles3D
var _shadow: Decal
var _prints: Array = []
var _print_tex: Texture2D
var _drift := Vector2.ZERO


## Какая погода сейчас: по дню мира и часу (детерминированно — тот же час, та же погода).
static func pick(hour: float, day_index: int) -> String:
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
	match kind:
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
			env.volumetric_fog_density *= 1.0 + rain * 1.5 + low_fog * 2.0 + (1.0 - day) * 0.5
		if rain > 0.0:
			env.ambient_light_energy *= 0.85
			env.fog_light_color = env.fog_light_color.lerp(Color(0.55, 0.58, 0.68), 0.5)
	_make_cloud_shadows()
	if rain > 0.0:
		_make_rain()
	if day > 0.5 and rain <= 0.0:
		_make_dust()
	if day < 0.4 and rain <= 0.0:
		_make_flies()
	_make_moths(lamps, day)


# ---------- тени облаков ----------

func _make_cloud_shadows() -> void:
	if overcast <= 0.05 and kind == "clear":
		overcast = 0.25                                    # и в ясный день — редкие облака
	var img := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.seed = 77
	n.frequency = 0.012
	n.fractal_octaves = 4
	var cover := lerpf(0.25, 0.65, overcast)
	for y: int in 256:
		for x: int in 256:
			var v := n.get_noise_2d(x, y) * 0.5 + 0.5
			var a := smoothstep(1.0 - cover, 1.0 - cover + 0.25, v) * 0.55
			img.set_pixel(x, y, Color(0.0, 0.0, 0.02, a))
	img.generate_mipmaps()
	_shadow = Decal.new()
	_shadow.texture_albedo = ImageTexture.create_from_image(img)
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
	_rain = GPUParticles3D.new()
	_rain.amount = 5000
	_rain.lifetime = 0.9
	_rain.visibility_aabb = AABB(Vector3(-25, -20, -25), Vector3(50, 40, 50))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(22, 0.5, 22)
	pm.direction = Vector3(0.08, -1, 0.04)
	pm.spread = 3.0
	pm.initial_velocity_min = 18.0
	pm.initial_velocity_max = 22.0
	pm.gravity = Vector3(0, -9.8, 0)
	_rain.process_material = pm
	var q := QuadMesh.new()
	q.size = Vector2(0.012, 0.55)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.75, 0.8, 0.9, 0.35)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	mat.billboard_keep_scale = true
	q.material = mat
	_rain.draw_pass_1 = q
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_rain)
	var st: AudioStream = mod.sound("sounds/rain_loop.wav")
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


# ---------- следы ----------

func footprint(pos: Vector3, yaw: float, left: bool) -> void:
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
		var old: Decal = _prints.pop_front()
		if is_instance_valid(old):
			old.queue_free()
	var tw := d.create_tween()
	tw.tween_interval(14.0)
	tw.tween_property(d, "modulate:a", 0.0, 4.0)


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	if is_instance_valid(_cam):
		var cp := _cam.global_position
		if _rain != null:
			_rain.global_position = cp + Vector3(0, 14, 0)
		if _dust != null:
			_dust.global_position = cp + Vector3(0, -0.5, 0)
		if _flies != null:
			_flies.global_position = Vector3(cp.x, cp.y - 1.8, cp.z)
		if _shadow != null:                                 # облака плывут по ветру
			_drift += Vector2(delta, delta)                 # плавно туда-обратно (без скачка при повторе)
			_shadow.global_position = Vector3(sin(_drift.x * 0.006) * 70.0, 20.0, sin(_drift.y * 0.0041 + 1.3) * 70.0)
	Prof.add("погода", t0)
