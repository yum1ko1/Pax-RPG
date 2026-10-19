extends RefCounted
## Эффекты «как в больших играх»: флипбуки (атласы 8×8, pax_rpg/dev/vfx/make_flipbooks.py) вместо одной картинки,
## огонь из слоёв (ядро-ореол, языки пламени, искры, дым над ним, мерцающий свет), дым с запечённым объёмом,
## ореолы у фонарей. Материалы общие — сотни эффектов делят несколько штук.

const SMOKE := "textures/vfx/smoke_8x8.png"
const FIRE := "textures/vfx/fire_8x8.png"
const GLOW := "textures/vfx/glow.png"

var mod: PaxMod
var _mats := {}
var _quad: QuadMesh


func _init(m: PaxMod) -> void:
	mod = m


## Флипбук-материал: billboard частиц, кадры атласа идут за жизнь частицы (anim_speed 1 у частиц).
func _flip_mat(tex: String, additive: bool, energy: float) -> StandardMaterial3D:
	var key := tex + str(additive) + str(energy)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.billboard_keep_scale = true
	m.particles_anim_h_frames = 8
	m.particles_anim_v_frames = 8
	m.particles_anim_loop = false
	m.vertex_color_use_as_albedo = true
	m.albedo_texture = mod.texture(tex)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.proximity_fade_enabled = true                      # мягкие частицы: без резкого среза о стены и землю
	m.proximity_fade_distance = 0.5
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		m.albedo_color = Color(energy, energy, energy)       # HDR > 1 — ловит bloom
	else:                                                # дым и пыль освещены: ночью не светятся сами, у костра — рыжие
		m.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
		m.disable_receive_shadows = true
	_mats[key] = m
	return m


func _glow_mat(color: Color, energy: float) -> StandardMaterial3D:
	var key := "glow" + str(color) + str(energy)
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_texture = mod.texture(GLOW)
	m.albedo_color = Color(color.r * energy, color.g * energy, color.b * energy)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	m.no_depth_test = false
	m.proximity_fade_enabled = true
	m.proximity_fade_distance = 0.3
	_mats[key] = m
	return m


func _q() -> QuadMesh:
	if _quad == null:
		_quad = QuadMesh.new()
	return _quad


func _parts(parent: Node, pos: Vector3, mat: Material, amount: int, life: float) -> CPUParticles3D:
	var p := CPUParticles3D.new()
	var q := QuadMesh.new()
	q.material = mat
	p.mesh = q
	p.amount = amount
	p.lifetime = life
	p.preprocess = life
	p.local_coords = false
	p.anim_speed_min = 1.0                               # весь атлас за жизнь частицы
	p.anim_speed_max = 1.0
	p.angle_min = 0.0
	p.angle_max = 360.0
	p.visibility_range_end = 90.0
	p.position = pos
	parent.add_child(p)
	return p


## Дым: клубы с объёмом, тёмные у источника, светлеют и тают вверху; ветер сносит.
func smoke(parent: Node, pos: Vector3, size: float, col: Color, amount: int, rise := 0.55) -> CPUParticles3D:
	var p := _parts(parent, pos, _flip_mat(SMOKE, false, 1.0), amount, 5.5)
	p.direction = Vector3.UP
	p.spread = 10.0
	p.initial_velocity_min = rise * 0.6
	p.initial_velocity_max = rise
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	p.emission_sphere_radius = 0.12 * size / 0.6
	p.gravity = Vector3(0.28, 0.1, 0.08)
	p.damping_min = 0.05
	p.damping_max = 0.15
	p.angular_velocity_min = -18.0
	p.angular_velocity_max = 18.0
	p.scale_amount_min = size
	p.scale_amount_max = size * 1.7
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.45))
	grow.add_point(Vector2(1, 1.6))
	p.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(col.darkened(0.35), col.a))
	ramp.set_color(1, Color(col.lightened(0.3), col.a))
	p.color_ramp = ramp
	return p


## Огонь из слоёв. size ≈ высота языков, м. Возвращает свет (им управляет daynight как фонарём).
func fire(parent: Node, pos: Vector3, size: float, with_smoke := true) -> OmniLight3D:
	var core := MeshInstance3D.new()                     # ядро-ореол: жар у основания
	var cq := QuadMesh.new()
	cq.size = Vector2.ONE * size * 1.3
	cq.material = _glow_mat(Color(1.0, 0.55, 0.2), 2.2)
	core.mesh = cq
	core.position = pos + Vector3(0, size * 0.25, 0)
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(core)
	var fl := _parts(parent, pos, _flip_mat(FIRE, true, 2.6), 10, 0.75)   # языки пламени
	fl.direction = Vector3.UP
	fl.spread = 6.0
	fl.initial_velocity_min = size * 0.4
	fl.initial_velocity_max = size * 0.8
	fl.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fl.emission_sphere_radius = size * 0.15
	fl.gravity = Vector3(0, 0.6, 0)
	fl.angle_min = -8.0
	fl.angle_max = 8.0
	fl.scale_amount_min = size * 0.7
	fl.scale_amount_max = size * 1.1
	var shrink := Curve.new()
	shrink.add_point(Vector2(0, 0.7))
	shrink.add_point(Vector2(0.3, 1.0))
	shrink.add_point(Vector2(1, 0.3))
	fl.scale_amount_curve = shrink
	var fr := Gradient.new()
	fr.set_color(0, Color(1, 1, 1, 0.0))
	fr.add_point(0.15, Color(1, 1, 1, 1))
	fr.set_color(1, Color(1, 0.6, 0.4, 0.0))
	fl.color_ramp = fr
	var sp := CPUParticles3D.new()                       # искры: уходят вверх, гаснут
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.024
	sm.radial_segments = 4
	sm.rings = 2
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(3.0, 1.4, 0.4)
	smat.vertex_color_use_as_albedo = true
	sm.material = smat
	sp.mesh = sm
	sp.amount = 10
	sp.lifetime = 1.6
	sp.preprocess = 1.6
	sp.local_coords = false
	sp.direction = Vector3.UP
	sp.spread = 25.0
	sp.initial_velocity_min = 0.8
	sp.initial_velocity_max = 2.2
	sp.gravity = Vector3(0.3, 0.6, 0.1)
	sp.damping_min = 0.4
	sp.damping_max = 1.0
	sp.tangential_accel_min = -1.5                        # искры кружат
	sp.tangential_accel_max = 1.5
	var sr := Gradient.new()
	sr.set_color(0, Color(1, 1, 1, 1))
	sr.set_color(1, Color(1, 0.3, 0.1, 0))
	sp.color_ramp = sr
	sp.visibility_range_end = 60.0
	sp.position = pos + Vector3(0, size * 0.3, 0)
	parent.add_child(sp)
	if with_smoke:
		smoke(parent, pos + Vector3(0, size * 1.1, 0), size * 0.8, Color(0.22, 0.2, 0.22, 0.3), 8, 0.7)
	var l := Flicker.new()
	l.light_color = Color(1.0, 0.52, 0.22)
	l.light_energy = 1.1
	l.omni_range = 7.0 + size * 3.0
	l.position = pos + Vector3(0, size * 0.6, 0)
	parent.add_child(l)
	return l


## Ореол у фонаря / кристалла: мягкое свечение вокруг источника, чуть дышит.
func halo(parent: Node, pos: Vector3, color: Color, size: float, energy := 1.2) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2.ONE * size
	q.material = _halo_mat(color, energy)
	mi.mesh = q
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visibility_range_end = 80.0
	mi.visibility_range_begin = 5.0                     # вблизи ореол — не «солнце» во весь кадр: тает у камеры
	mi.visibility_range_begin_margin = 4.0
	mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
	mi.position = pos
	parent.add_child(mi)
	return mi


## Свет огня: мерцает шумом (не ровный), энергию задаёт daynight через base.
## Один «ведущий» огонь считает мерцание всех (а не сотня колбэков _process в кадр — как менеджеры эффектов
## в больших движках); дальше FAR м от камеры мерцание не считается — его там не разглядеть.
class Flicker extends OmniLight3D:
	const FAR := 60.0
	static var all: Array = []
	static var _driver: Flicker
	var base := -1.0
	var _t := randf() * 100.0

	func _enter_tree() -> void:
		all.append(self)
		var lead := _driver == null or not is_instance_valid(_driver)
		if lead:
			_driver = self
		set_process(lead)

	func _exit_tree() -> void:
		all.erase(self)
		if _driver != self:
			return
		_driver = null
		for f: Variant in all:
			if is_instance_valid(f) and (f as Flicker).is_inside_tree():
				_driver = f
				(f as Flicker).set_process(true)
				break

	func _process(delta: float) -> void:
		if _driver != self:
			set_process(false)
			return
		var cam := get_viewport().get_camera_3d()
		var cp := cam.global_position if cam != null else Vector3.ZERO
		for v: Variant in all:
			var f := v as Flicker
			if f == null:
				continue
			if f.base < 0.0:
				f.base = f.light_energy
			f._t += delta
			if cam != null and f.global_position.distance_squared_to(cp) > FAR * FAR:
				continue
			var t := f._t
			var n := sin(t * 13.0) * 0.5 + sin(t * 7.3 + 1.7) * 0.3 + sin(t * 23.0 + 0.4) * 0.2
			f.light_energy = f.base * (0.85 + 0.15 * n)


## Ореол — billboard как у StandardMaterial (без масштаба узла: прежнее «дыхание» через scale billboard и так
## не показывал), но без узла-скрипта: раньше каждый ореол звал _process каждый кадр впустую.
const HALO_SH := """shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform vec4 col : source_color = vec4(1.0);
uniform float prox = 0.3;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;
void vertex() {
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}
void fragment() {
	vec4 t = texture(tex, UV);
	float d = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec4 wp = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, d, 1.0);
	wp.xyz /= wp.w;
	ALBEDO = col.rgb * t.rgb;
	ALPHA = t.a * clamp(1.0 - smoothstep(wp.z + prox, wp.z, VERTEX.z), 0.0, 1.0);
}
"""
static var _halo_sh: Shader


func _halo_mat(color: Color, energy: float) -> ShaderMaterial:
	var key := "halo" + str(color) + str(energy)
	if _mats.has(key):
		return _mats[key]
	if _halo_sh == null:
		_halo_sh = Shader.new()
		_halo_sh.code = HALO_SH
	var m := ShaderMaterial.new()
	m.shader = _halo_sh
	m.set_shader_parameter("tex", mod.texture(GLOW))
	m.set_shader_parameter("col", Color(color.r * energy, color.g * energy, color.b * energy))
	_mats[key] = m
	return m


## Постоянные частицы (огни, дым, листья, брызги) — на видеокарту: CPUParticles3D считает каждую частицу
## процессором каждый кадр, GPUParticles3D — шейдером (так делают все большие движки). Вид тот же:
## convert_from_particles переносит все параметры. Разовые всплески (искры удара, пыль) остаются как есть.
## Возвращает {старый узел: новый} — чтобы обновить списки (ветер).
static func to_gpu(root: Node) -> Dictionary:
	return to_gpu_list(root.find_children("*", "CPUParticles3D", true, false))


static func to_gpu_list(nodes: Array) -> Dictionary:
	var map := {}
	for n: Variant in nodes:
		var c := n as CPUParticles3D
		if c == null or c.one_shot or c.get_parent() == null:
			continue
		var g := GPUParticles3D.new()
		g.convert_from_particles(c)
		g.transform = c.transform
		g.preprocess = c.preprocess
		g.visibility_range_begin = c.visibility_range_begin
		g.visibility_range_end = c.visibility_range_end
		g.cast_shadow = c.cast_shadow
		g.layers = c.layers
		g.visible = c.visible
		g.visibility_aabb = AABB(Vector3(-8.0, -3.0, -8.0), Vector3(16.0, 18.0, 16.0))   # дым уходит высоко
		g.emitting = c.emitting
		var par := c.get_parent()
		par.add_child(g)
		par.move_child(g, c.get_index())
		par.remove_child(c)
		c.queue_free()
		map[c] = g
	return map
