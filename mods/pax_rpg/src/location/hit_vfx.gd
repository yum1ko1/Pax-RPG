extends RefCounted
## Удары «как в Genshin / DMC» (прототип: укол копьём Тянь Лун, Attack1). Не покадровая картинка: объёмные сетки вокруг
## оси удара (shaders/vfx_vol.gdshader — оболочка светится по краю силуэта, по объёму течёт шум, форма тает от хвоста
## к острию) и короткие вспышки-маски (GPT-референсы → pax_rpg/dev/vfx/make_hit_masks.py → shaders/vfx_hit.gdshader).
##   thrust — луч укола: плотное ядро-конус, газовая оболочка пошире, две ленты спирали вокруг оси (крутятся);
##            выстреливает за 3 кадра, держится, тает от хвоста к острию;
##   impact — вспышка-звезда (2–3 кадра, почти весь свет удара — в них), сфера-вспышка, ударный конус вперёд
##            по удару (раскрывается и тает), кольцо волны поперёк удара, искры по удару (не вверх).
## Сетки строятся один раз (единичные, по оси X), материалы общие; живые эффекты тикает один tick() из location.gd.

const SH := "shaders/vfx_hit.gdshader"
const SH_VOL := "shaders/vfx_vol.gdshader"
const TEX := "textures/vfx/hit/%s.png"

var mod: PaxMod
var parent: Node
var _mats := {}
var _meshes := {}
var _live: Array = []                # {n, t, life, kind, ...}: узел и кривые его жизни


func _init(m: PaxMod, p: Node) -> void:
	mod = m
	parent = p


func _colors(m: ShaderMaterial, col: Color, energy: float) -> void:
	m.set_shader_parameter("mid", Color(col.r, col.g, col.b))
	m.set_shader_parameter("edge", Color(col.r * 0.32, col.g * 0.1, col.b * 0.2))
	m.set_shader_parameter("energy", energy)


## Плоская маска (звезда, кольцо): mode 0 — billboard, 2 — как стоит узел.
func _mat(mask: String, mode: int, col: Color, energy: float) -> ShaderMaterial:
	var key := mask + str(mode) + str(col) + str(energy)
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = mod.shader(SH)
	m.set_shader_parameter("mask_tex", mod.texture(TEX % mask))
	m.set_shader_parameter("mode", mode)
	_colors(m, col, energy)
	_mats[key] = m
	return m


## Объёмная форма: p — параметры vfx_vol.gdshader (fres, fres_inv, flow, noise_scale, density, heat_k).
func _vol(name: String, col: Color, energy: float, p: Dictionary) -> ShaderMaterial:
	var key := name + str(col) + str(energy)
	if _mats.has(key):
		return _mats[key]
	var m := ShaderMaterial.new()
	m.shader = mod.shader(SH_VOL)
	_colors(m, col, energy)
	for k: String in p:
		m.set_shader_parameter(k, p[k])
	_mats[key] = m
	return m


func _node(mesh: Mesh, mat: ShaderMaterial) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.extra_cull_margin = 4.0                   # billboard ставит квад к камере сам — рамка узла меньше видимого
	parent.add_child(mi)
	return mi


static func _basis(dir: Vector3) -> Basis:
	var x := dir.normalized()
	var up := Vector3.UP if absf(x.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD
	var z := x.cross(up).normalized()
	return Basis(x, z.cross(x), z)


# ---------- сетки (единичные, ось X — вдоль удара, UV.x — от хвоста к острию, UV.y — вокруг оси) ----------

func _quad() -> Mesh:
	if not _meshes.has("quad"):
		_meshes["quad"] = QuadMesh.new()
	return _meshes["quad"]


## Конус-трубка длиной 1: радиус r0 у хвоста → r1 у острия, кривая pow(x, bend) (bend < 1 — быстро сужается к острию).
func _cone(name: String, r0: float, r1: float, bend: float) -> Mesh:
	if _meshes.has(name):
		return _meshes[name]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := 24
	var seg := 18
	for i: int in rings + 1:
		var x := float(i) / rings
		var r := lerpf(r0, r1, pow(x, bend))
		for j: int in seg + 1:
			var a := TAU * float(j) / seg
			var radial := Vector3(0.0, cos(a), sin(a))
			st.set_normal(radial)
			st.set_uv(Vector2(x, float(j) / seg))
			st.add_vertex(Vector3(x, 0.0, 0.0) + radial * r)
	for i: int in rings:
		for j: int in seg:
			var a := i * (seg + 1) + j
			var b := a + seg + 1
			st.add_index(a)
			st.add_index(b)
			st.add_index(a + 1)
			st.add_index(a + 1)
			st.add_index(b)
			st.add_index(b + 1)
	_meshes[name] = st.commit()
	return _meshes[name]


## Лента спирали вокруг оси: turns витков, радиус r0 → r1, ширина w (к концам тоньше). UV.y — поперёк ленты.
func _helix(name: String, turns: float, r0: float, r1: float, w: float, phase: float) -> Mesh:
	if _meshes.has(name):
		return _meshes[name]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 64
	for i: int in n + 1:
		var x := float(i) / n
		var r := lerpf(r0, r1, x)
		var a := phase + TAU * turns * x
		var radial := Vector3(0.0, cos(a), sin(a))
		var c := Vector3(x, 0.0, 0.0) + radial * r
		var tang := (Vector3(1.0 / n, 0.0, 0.0) + Vector3(0.0, -sin(a), cos(a)) * r * TAU * turns / n).normalized()
		var bi := tang.cross(radial).normalized()
		var ww := w * sin(PI * clampf(x * 1.15, 0.0, 1.0))
		for s: int in 2:
			st.set_normal(radial)
			st.set_uv(Vector2(x, float(s)))
			st.add_vertex(c + bi * ww * (float(s) - 0.5) * 2.0)
	for i: int in n:
		var a := i * 2
		st.add_index(a)
		st.add_index(a + 2)
		st.add_index(a + 1)
		st.add_index(a + 1)
		st.add_index(a + 2)
		st.add_index(a + 3)
	_meshes[name] = st.commit()
	return _meshes[name]


func _sphere() -> Mesh:
	if not _meshes.has("sphere"):
		var s := SphereMesh.new()
		s.radial_segments = 20
		s.rings = 10
		_meshes["sphere"] = s
	return _meshes["sphere"]


# ---------- слои удара ----------

## Луч укола: остриё — на полметра дальше tip (конец копья), хвост — у кисти; hit — укол попал (ярче и дольше).
func thrust(tip: Vector3, dir: Vector3, col: Color, hit := false, heft := 1.0) -> void:
	if not is_instance_valid(parent) or dir.length() < 0.01:
		return
	var d := dir.normalized()
	var k := clampf(heft, 0.8, 1.5)
	var length := 2.4 * k
	var b := _basis(d)
	var tail := tip + d * 0.5 - d * length
	var life := 0.3 if hit else 0.26
	var core := _node(_cone("core", 0.07, 0.006, 0.55), _vol("core", col, 2.6,
		{"fres_inv": 1.0, "flow": 4.0, "noise_scale": 2.0, "density": 1.5, "heat_k": 1.6}))
	var shell := _node(_cone("shell", 0.22, 0.02, 0.7), _vol("shell", col, 1.05,
		{"fres": 1.8, "flow": 3.0, "noise_scale": 3.2, "density": 1.5, "heat_k": 0.15}))
	for e: Array in [[core, 1.0], [shell, 1.0]]:
		var mi: MeshInstance3D = e[0]
		mi.global_transform = Transform3D(Basis(b.x * length, b.y * k, b.z * k), tail)
		mi.set_instance_shader_parameter(&"seed", randf())
		_live.append({"n": mi, "t": 0.0, "life": life, "kind": "beam"})
	for ph: float in [0.0, PI]:                  # две ленты спирали навстречу друг другу, крутятся вокруг оси
		var hx := _node(_helix("helix%d" % int(ph * 10.0), 1.6, 0.34, 0.05, 0.11, ph), _vol("helix", col, 1.5,
			{"fres": 0.4, "flow": 5.0, "noise_scale": 2.5, "density": 2.0, "heat_k": 0.6}))
		hx.global_transform = Transform3D(Basis(b.x * length * 0.92, b.y * k, b.z * k), tail + d * length * 0.06)
		hx.set_instance_shader_parameter(&"seed", randf())
		_live.append({"n": hx, "t": 0.0, "life": life, "kind": "helix", "b": hx.global_transform.basis,
			"spin": 9.0 if ph == 0.0 else -9.0})
	for e: Dictionary in _live.slice(_live.size() - 4):
		_apply(e)


## Попадание: звезда, сфера-вспышка, ударный конус и кольцо по удару, искры. at — точка на враге, dir — куда шёл удар.
func impact(at: Vector3, dir: Vector3, col: Color, heft := 1.0) -> void:
	if not is_instance_valid(parent):
		return
	var d := dir.normalized() if dir.length() > 0.01 else Vector3.FORWARD
	var k := clampf(heft, 0.7, 1.6)
	var b := _basis(d)
	var star := _node(_quad(), _mat("impact", 0, col, 3.4))
	star.global_position = at
	star.set_instance_shader_parameter(&"roll", randf_range(-0.35, 0.35))
	_live.append({"n": star, "t": 0.0, "life": 0.1, "kind": "star", "s": 1.4 * k})
	var orb := _node(_sphere(), _vol("orb", col, 1.6, {"fres": 1.6, "flow": 2.0, "noise_scale": 2.5, "density": 1.5,
		"heat_k": 0.7}))
	orb.global_position = at
	_live.append({"n": orb, "t": 0.0, "life": 0.16, "kind": "orb", "s": 0.75 * k})
	var cone := _node(_cone("burst", 0.25, 1.0, 1.0), _vol("burst", col, 1.15, {"fres": 1.4, "flow": 6.0,
		"noise_scale": 3.5, "density": 1.5, "heat_k": 0.2}))
	cone.global_position = at - d * 0.1
	cone.set_instance_shader_parameter(&"seed", randf())
	_live.append({"n": cone, "t": 0.0, "life": 0.26, "kind": "burst", "b": b, "s": k})
	var ring := _node(_quad(), _mat("ring", 2, col, 2.0))
	ring.global_transform = Transform3D(Basis(b.z, b.y, b.x), at + d * 0.15)   # плоскость кольца — поперёк удара
	_live.append({"n": ring, "t": 0.0, "life": 0.3, "kind": "ring", "s": 2.4 * k, "b": ring.global_transform.basis})
	_sparks(at, d, col, int(16 * k))
	for e: Dictionary in _live.slice(_live.size() - 4):
		_apply(e)                               # с первого кадра — в своём начальном виде, а не единичной сеткой


## Искры по направлению удара: узкий конус вперёд, быстрые, со шлейфом; к концу жизни тоньше — гаснут, а не висят.
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
	var shrink := Curve.new()
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
		"beam", "helix":                        # 0..0.18 — выстрел вдоль, держится ярким, затем тает хвост → остриё
			mi.set_instance_shader_parameter(&"reveal", clampf(t / 0.18, 0.0, 1.0) * 1.1)
			mi.set_instance_shader_parameter(&"progress", _out(clampf((t - 0.25) / 0.75, 0.0, 1.0)))
			mi.set_instance_shader_parameter(&"glow", 1.5 if t < 0.25 else lerpf(1.5, 0.7, (t - 0.25) / 0.75))
			if String(e.kind) == "helix":           # спираль крутится вокруг оси удара
				var b: Basis = e.b
				var ax := b.x.normalized()
				mi.global_transform.basis = Basis(ax, float(e.spin) * float(e.t)) * b
		"star":                                 # раздувается и гаснет за 2–3 кадра
			var s := float(e.s) * lerpf(0.65, 1.25, _out(t))
			mi.scale = Vector3(s, s, 1.0)
			mi.set_instance_shader_parameter(&"glow", 2.4 * (1.0 - t) * (1.0 - t))
			mi.set_instance_shader_parameter(&"progress", t * 0.55)
		"orb":                                  # шар света раздувается и рвётся шумом
			var s := float(e.s) * lerpf(0.3, 1.0, _out(t))
			mi.scale = Vector3(s, s, s)
			mi.set_instance_shader_parameter(&"glow", 1.8 * (1.0 - t))
			mi.set_instance_shader_parameter(&"progress", t * 0.9)
		"burst":                                # ударный конус: вылетает вперёд по удару, раскрывается и тает
			var b: Basis = e.b
			var k := float(e.s)
			var l := lerpf(0.3, 1.7, _out(t)) * k
			var r := lerpf(0.25, 1.1, _out(t)) * k
			mi.global_transform.basis = Basis(b.x * l, b.y * r, b.z * r)
			mi.set_instance_shader_parameter(&"glow", 1.3 * (1.0 - t))
			mi.set_instance_shader_parameter(&"progress", clampf(t * 1.1, 0.0, 1.0))
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
