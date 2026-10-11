extends Node3D
## Ветер как в аниме: время от времени у героя проносится порыв — несколько тонких белых изогнутых штрихов
## (shaders/wind_streak.gdshader) летят по ветру, вспыхивают и тают. В порыв листья с деревьев сносит сильнее
## (city.gd → leaves, gravity по ветру). Направление ветра медленно гуляет.

var mod: PaxMod
var target: Node3D                 # вокруг кого порывы (герой)
var leaves: Array = []             # CPUParticles3D листьев (city.gd)
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
	if not is_instance_valid(target):
		return
	dir = dir.rotated(Vector3.UP, sin(Time.get_ticks_msec() * 0.00007) * delta * 0.05).normalized()
	_next -= delta
	if _next <= 0.0:
		_next = randf_range(4.0, 9.0)
		_spawn_gust()
	_gust = maxf(0.0, _gust - delta * 0.35)
	for l: Variant in leaves:
		if is_instance_valid(l):
			(l as CPUParticles3D).gravity = Vector3(0.0, -0.55, 0.0) + dir * (0.35 + 1.6 * _gust)
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
	for i: int in randi_range(4, 7):
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
