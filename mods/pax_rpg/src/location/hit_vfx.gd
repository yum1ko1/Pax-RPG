extends RefCounted
## Удары «как в Genshin / DMC» (прототип: укол копьём Тянь Лун, Attack1). Эффект — не покадровая картинка, а статичные
## маски (GPT-референсы → pax_rpg/dev/vfx/make_hit_masks.py), которые оживляет shaders/vfx_hit.gdshader: эрозия по
## порогу, прорисовка вдоль мазка, цвет от белого ядра к мане. Слои одного удара:
##   thrust — луч укола из острия (выстреливает за 3 кадра, держится, тает от хвоста к острию);
##   impact — вспышка-звезда в точке попадания (2–3 кадра, почти весь свет удара — в них), кольцо волны поперёк удара,
##            искры по направлению удара (не вверх).
## Материалы общие (на маску и цвет), живые эффекты тикает один tick() из location.gd — без _process на каждом узле.

const SH := "shaders/vfx_hit.gdshader"
const TEX := "textures/vfx/hit/%s.png"

var mod: PaxMod
var parent: Node
var _mats := {}
var _quad: QuadMesh
var _live: Array = []                # {n, t, life, ...}: узел и кривые его жизни


func _init(m: PaxMod, p: Node) -> void:
	mod = m
	parent = p


func _mat(mask: String, mode: int, col: Color, energy: float) -> ShaderMaterial:
	var key := mask + str(mode) + str(col) + str(energy)
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = mod.shader(SH)
	m.set_shader_parameter("mask_tex", mod.texture(TEX % mask))
	m.set_shader_parameter("mode", mode)
	m.set_shader_parameter("mid", Color(col.r, col.g, col.b))
	m.set_shader_parameter("edge", Color(col.r * 0.32, col.g * 0.1, col.b * 0.2))
	m.set_shader_parameter("energy", energy)
	_mats[key] = m
	return m


func _node(mat: ShaderMaterial) -> MeshInstance3D:
	if _quad == null:
		_quad = QuadMesh.new()
	var mi := MeshInstance3D.new()
	mi.mesh = _quad
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0                   # шейдер сам ставит квад к камере — рамка узла меньше видимого
	parent.add_child(mi)
	return mi


static func _basis(dir: Vector3) -> Basis:
	var x := dir.normalized()
	var up := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var z := x.cross(up).normalized()
	return Basis(x, z.cross(x), z)


## Луч укола: остриё мазка — чуть впереди tip, длина len м вдоль dir. hit — укол попал (ярче и дольше).
func thrust(tip: Vector3, dir: Vector3, col: Color, hit := false, heft := 1.0) -> void:
	if not is_instance_valid(parent) or dir.length() < 0.01:
		return
	var d := dir.normalized()
	var length := 2.3 * clampf(heft, 0.8, 1.5)          # хвост — у груди героя, остриё — на полметра дальше копья
	var width := 0.5 * clampf(heft, 0.8, 1.4)
	var mi := _node(_mat("thrust", 1, col, 2.2 if hit else 1.7))
	var b := _basis(d)
	mi.global_transform = Transform3D(Basis(b.x * length, b.y * width, b.z), tip + d * 0.5 - d * length * 0.5)
	_live.append({"n": mi, "t": 0.0, "life": 0.3 if hit else 0.24, "kind": "thrust"})
	_apply(_live[-1])


## Попадание: звезда, кольцо поперёк удара, искры по удару. at — точка на враге, dir — куда шёл удар.
func impact(at: Vector3, dir: Vector3, col: Color, heft := 1.0) -> void:
	if not is_instance_valid(parent):
		return
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var k := clampf(heft, 0.7, 1.6)
	var star := _node(_mat("impact", 0, col, 4.0))
	star.global_position = at
	star.set_instance_shader_parameter(&"roll", randf_range(-0.35, 0.35))
	_live.append({"n": star, "t": 0.0, "life": 0.11, "kind": "star", "s": 1.7 * k})
	var ring := _node(_mat("ring", 2, col, 2.2))
	var rb := _basis(d)
	ring.global_transform = Transform3D(Basis(rb.z, rb.y, rb.x), at + d * 0.15)   # плоскость кольца — поперёк удара
	_live.append({"n": ring, "t": 0.0, "life": 0.32, "kind": "ring", "s": 2.8 * k, "b": ring.global_transform.basis})
	_sparks(at, d, col, int(16 * k))
	for e: Dictionary in _live.slice(_live.size() - 2):
		_apply(e)                               # с первого кадра — в своём начальном виде, а не квадом 1×1


## Искры по направлению удара: узкий конус вперёд, быстрые, со шлейфом; гравитация слабая — летят, а не сыплются.
func _sparks(at: Vector3, dir: Vector3, col: Color, amount: int) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = 0.2
	p.local_coords = false
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = 28.0
	pm.initial_velocity_min = 7.0
	pm.initial_velocity_max = 15.0
	pm.gravity = Vector3(0.0, -2.0, 0.0)
	pm.damping_min = 2.0
	pm.damping_max = 5.0
	var shrink := Curve.new()                         # к концу жизни искра тоньше — гаснет, а не висит штрихом
	shrink.add_point(Vector2(0.0, 1.0))
	shrink.add_point(Vector2(1.0, 0.0))
	var sc := CurveTexture.new()
	sc.curve = shrink
	pm.scale_curve = sc
	p.process_material = pm
	p.trail_enabled = true
	p.trail_lifetime = 0.06
	var tm := RibbonTrailMesh.new()
	tm.shape = RibbonTrailMesh.SHAPE_CROSS
	tm.size = 0.018
	tm.sections = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.use_particle_trails = true
	m.albedo_color = Color(lerpf(col.r, 1.0, 0.3) * 4.0, lerpf(col.g, 1.0, 0.12) * 4.0, lerpf(col.b, 1.0, 0.12) * 4.0)
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	tm.material = m
	p.draw_pass_1 = tm
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


static func _out(x: float) -> float:
	return 1.0 - (1.0 - x) * (1.0 - x)


func _apply(e: Dictionary) -> void:
	var mi: MeshInstance3D = e.n
	var t := float(e.t) / float(e.life)
	match String(e.kind):
		"thrust":                               # 0..0.18 — выстрел вдоль, держится ярким, затем тает хвост → остриё
			mi.set_instance_shader_parameter(&"reveal", clampf(t / 0.18, 0.0, 1.0) * 1.08)
			mi.set_instance_shader_parameter(&"progress", _out(clampf((t - 0.22) / 0.78, 0.0, 1.0)))
			mi.set_instance_shader_parameter(&"glow", 1.6 if t < 0.25 else lerpf(1.6, 0.8, (t - 0.25) / 0.75))
		"star":                                 # раздувается и гаснет за 2–3 кадра
			var s := float(e.s) * lerpf(0.65, 1.25, _out(t))
			mi.scale = Vector3(s, s, 1.0)
			mi.set_instance_shader_parameter(&"glow", 2.6 * (1.0 - t) * (1.0 - t))
			mi.set_instance_shader_parameter(&"progress", t * 0.55)
		"ring":                                 # быстро расходится, рвётся и тает
			var s := float(e.s) * lerpf(0.12, 1.0, _out(t))
			var b: Basis = e.b
			mi.global_transform.basis = Basis(b.x.normalized() * s, b.y.normalized() * s, b.z.normalized())
			mi.set_instance_shader_parameter(&"glow", 1.0 - t * 0.5)
			mi.set_instance_shader_parameter(&"progress", clampf(0.1 + t * 0.95, 0.0, 1.0))


## Каждый кадр из location.gd: кривые жизни живых эффектов, отжившие — убрать.
func tick(delta: float) -> void:
	var i := 0
	while i < _live.size():
		var e: Dictionary = _live[i]
		if not is_instance_valid(e.n):
			_live.remove_at(i)
			continue
		e.t = float(e.t) + delta
		if float(e.t) >= float(e.life):
			(e.n as Node).queue_free()
			_live.remove_at(i)
			continue
		_apply(e)
		i += 1


func clear() -> void:
	for e: Dictionary in _live:
		if is_instance_valid(e.n):
			(e.n as Node).queue_free()
	_live.clear()
