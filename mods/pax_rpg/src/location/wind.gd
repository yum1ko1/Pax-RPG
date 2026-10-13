extends Node3D
## Ветер как в аниме: время от времени у героя проносится порыв — несколько тонких белых изогнутых штрихов
## (shaders/wind_streak.gdshader) летят по ветру, вспыхивают и тают. В порыв листья с деревьев сносит сильнее
## (city.gd → leaves, gravity по ветру). Направление ветра медленно гуляет.
const Prof := preload("res://mods/pax_rpg/src/location/prof.gd")

var mod: PaxMod
var target: Node3D                 # вокруг кого порывы (герой)
var leaves: Array = []             # CPUParticles3D листьев (city.gd)
var smoke: Array = []              # дым и пар (city.gd) — ветер клонит их в свою сторону
var dir := Vector3(1, 0, 0.3).normalized()
var _next := 2.5
var _gust := 0.0                   # 0..1 — сила текущего порыва
var _streaks: Array = []           # {mi, v, t, life}
var _mesh: QuadMesh
var _shader: Shader


func setup(m: PaxMod, who: Node3D) -> void:
	mod = m
	target = who
	name = "PaxRpgWind"
	_shader = mod.shader("shaders/wind_streak.gdshader")
	_mesh = QuadMesh.new()
	_mesh.size = Vector2(1.0, 1.0)
	_mesh.subdivide_width = 24


func _process(delta: float) -> void:
	var t0 := Time.get_ticks_usec()
	_proc(delta)
	Prof.add("ветер", t0)


func _proc(delta: float) -> void:
	if not is_instance_valid(target):
		return
	dir = dir.rotated(Vector3.UP, sin(Time.get_ticks_msec() * 0.00007) * delta * 0.05).normalized()
	_next -= delta
	if _next <= 0.0:
		_next = randf_range(4.0, 9.0)
		_spawn_gust()
	_gust = maxf(0.0, _gust - delta * 0.35)
	# трава, листва, степь — шейдеры читают ветер из глобального параметра (gfx.gd: pax_rpg_wind)
	RenderingServer.global_shader_parameter_set(&"pax_rpg_wind", Vector4(dir.x, dir.z, 0.55 + 0.25 * sin(Time.get_ticks_msec() * 0.0004), _gust))
	for l: Variant in leaves:
		if is_instance_valid(l):
			(l as CPUParticles3D).gravity = Vector3(0.0, -0.55, 0.0) + dir * (0.35 + 1.6 * _gust)
	for p: Variant in smoke:
		if is_instance_valid(p):
			(p as CPUParticles3D).gravity = Vector3(0.0, 0.12, 0.0) + dir * (0.25 + 0.9 * _gust)
	var keep: Array = []
	for s: Dictionary in _streaks:
		s.t = float(s.t) + delta
		var mi: MeshInstance3D = s.mi
		if float(s.t) >= float(s.life) or not is_instance_valid(mi):
			if is_instance_valid(mi):
				mi.queue_free()
			continue
		mi.global_position += (s.v as Vector3) * delta
		var k := float(s.t) / float(s.life)
		(mi.material_override as ShaderMaterial).set_shader_parameter("life", k)
		keep.append(s)
	_streaks = keep


## Пыль, поднятая порывом: низкие клубы у земли (флипбук дыма, цвет глины), сносит вдоль ветра.
var _dust_mat: StandardMaterial3D


func _dust(at: Vector3) -> void:
	if _dust_mat == null:
		_dust_mat = StandardMaterial3D.new()
		_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		_dust_mat.particles_anim_h_frames = 8
		_dust_mat.particles_anim_v_frames = 8
		_dust_mat.particles_anim_loop = false
		_dust_mat.vertex_color_use_as_albedo = true
		_dust_mat.albedo_texture = mod.texture("textures/vfx/smoke_8x8.png")
		_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_dust_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
		_dust_mat.proximity_fade_enabled = true
		_dust_mat.proximity_fade_distance = 0.6
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.material = _dust_mat
	p.mesh = q
	p.one_shot = true
	p.explosiveness = 0.6
	p.amount = 14
	p.lifetime = 2.4
	p.local_coords = false
	p.anim_speed_min = 1.0
	p.anim_speed_max = 1.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(5.0, 0.1, 5.0)
	p.direction = dir + Vector3(0, 0.15, 0)
	p.spread = 15.0
	p.initial_velocity_min = 3.0
	p.initial_velocity_max = 6.0
	p.damping_min = 1.0
	p.damping_max = 2.0
	p.gravity = Vector3(0, 0.2, 0)
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.4
	p.angle_min = 0.0
	p.angle_max = 360.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.72, 0.56, 0.42, 0.0))
	ramp.add_point(0.2, Color(0.72, 0.56, 0.42, 0.22))
	ramp.set_color(1, Color(0.8, 0.66, 0.55, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.global_position = Vector3(at.x, target.global_position.y + 0.3, at.z)
	p.emitting = true
	p.finished.connect(p.queue_free)


func _spawn_gust() -> void:
	if _shader == null:
		return
	_gust = 1.0
	var side := dir.cross(Vector3.UP).normalized()
	var cam0 := get_viewport().get_camera_3d()
	var base := target.global_position - dir * 6.0
	if cam0 != null:                                      # в поле зрения: в 7–12 м перед камерой
		var fw := -cam0.global_transform.basis.z
		fw.y = 0.0
		base = cam0.global_position + fw.normalized() * randf_range(7.0, 12.0) - dir * 6.0
		base.y = target.global_position.y
	_dust(base + dir * 6.0)
	for i: int in randi_range(3, 5):
		var mi := MeshInstance3D.new()
		mi.mesh = _mesh
		var m := ShaderMaterial.new()
		m.shader = _shader
		m.set_shader_parameter("phase", randf() * TAU)
		m.set_shader_parameter("curl", randf_range(0.15, 0.45))
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		var length := randf_range(3.0, 6.5)
		var at := base + side * randf_range(-5.0, 5.0) + Vector3(0, randf_range(0.6, 3.2), 0) - dir * randf_range(0.0, 4.0)
		# штрих лежит вдоль ветра, плоскостью — к камере (по вертикали), длина — по X квада
		var cam := get_viewport().get_camera_3d()
		var nrm := -side
		if cam != null:                                   # плоскостью к камере (поворот вокруг оси ветра)
			var to := cam.global_position - at
			nrm = (to - dir * to.dot(dir)).normalized()
		var b := Basis(dir, nrm.cross(dir).normalized(), nrm)
		mi.global_transform = Transform3D(b * Basis.from_scale(Vector3(length, randf_range(0.5, 0.9), 1.0)), at)
		_streaks.append({"mi": mi, "v": dir * randf_range(9.0, 14.0), "t": 0.0, "life": randf_range(0.9, 1.5)})
