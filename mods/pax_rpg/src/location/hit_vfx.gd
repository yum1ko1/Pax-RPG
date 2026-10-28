extends RefCounted
## Удары «как в Genshin / DMC» (прототип: укол копьём Тянь Лун, Attack1). Не покадровая картинка: объёмные сетки вокруг
## оси удара (shaders/vfx_vol.gdshader — оболочка светится по краю силуэта, по объёму течёт шум, форма тает от хвоста
## к острию) и короткие вспышки-маски (GPT-референсы → pax_rpg/dev/vfx/make_hit_masks.py → shaders/vfx_hit.gdshader).
##   thrust — луч укола: плотное ядро-конус, газовая оболочка пошире, две ленты спирали вокруг оси (крутятся);
##            выстреливает за 3 кадра, держится, тает от хвоста к острию;
##   impact — вспышка-звезда (2–3 кадра, почти весь свет удара — в них), сфера-вспышка, ударный конус вперёд
##            по удару (раскрывается и тает), кольцо волны поперёк удара, искры по удару (не вверх);
##   landing — приземление спецприёма (прыжок орка, «Сокрушение» рыцаря): вспышка у земли, кольцо по земле, стена
##            ударной волны (светящийся цилиндр расходится и оседает в землю), корона-воронка пыли, купол воздуха;
##   parry  — парирование: белая звезда, блик-штрих, кольцо, широкий веер светлых искр;
##   block  — блок: тусклая вспышка, маленькое кольцо-толчок, горсть рыжих искр;
##   trail  — след клинка на взмахе (промах): серп прорисовывается по ходу удара и тает.
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


## Объёмная форма: p — параметры vfx_vol.gdshader (fres, fres_inv, flow, noise_scale, density, heat_k; core, edge —
## свои цвета, напр. у пыли: тогда она не светится, а кроет фон).
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


## Приземление спецприёма: at — точка на земле, col — энергия приёма, size — радиус волны, м (орк ~3, рыцарь ~5).
func landing(at: Vector3, col: Color, size := 3.0, dust := Color(0.62, 0.52, 0.42)) -> void:
	if not is_instance_valid(parent):
		return
	var up := Basis(Vector3.UP, Vector3.FORWARD, Vector3.RIGHT)   # ось X сеток — вверх
	var flash := _node(_quad(), _mat("impact", 0, col, 3.6))
	flash.global_position = at + Vector3(0.0, 0.5, 0.0)
	_live.append({"n": flash, "t": 0.0, "life": 0.12, "kind": "star", "s": size * 0.9})
	var orb := _node(_sphere(), _vol("orb", col, 1.6, {"fres": 1.6, "flow": 2.0, "noise_scale": 2.5, "density": 1.5,
		"heat_k": 0.7}))
	orb.global_position = at + Vector3(0.0, 0.2, 0.0)
	_live.append({"n": orb, "t": 0.0, "life": 0.22, "kind": "orb", "s": size * 0.7})
	var ring := _node(_quad(), _mat("ring", 2, col, 2.2))
	ring.global_transform = Transform3D(Basis(Vector3.RIGHT, Vector3.BACK, Vector3.UP), at + Vector3(0.0, 0.06, 0.0))
	_live.append({"n": ring, "t": 0.0, "life": 0.4, "kind": "ring", "s": size * 2.3, "b": ring.global_transform.basis})
	# стена волны: цилиндр смотрит осью вниз (UV.x = 0 — мягкий верх, 1 — у земли), тает сверху — оседает в землю
	var wall := _node(_cone("wall", 1.0, 1.0, 1.0), _vol("wall", col, 1.3, {"fres": 1.2, "flow": -4.0,
		"noise_scale": 4.0, "density": 1.6, "heat_k": 0.35}))
	wall.set_instance_shader_parameter(&"seed", randf())
	_live.append({"n": wall, "t": 0.0, "life": 0.45, "kind": "wall", "at": at, "s": size})
	# корона пыли: воронка раскрывается вверх-наружу; пыль не светится — кроет фон (свои тёмные цвета)
	var crown := _node(_cone("crown", 0.55, 1.0, 1.0), _vol("crown", dust, 1.0, {"fres": 0.9, "flow": 2.5,
		"noise_scale": 3.0, "density": 1.4, "heat_k": 0.0, "core": dust.lightened(0.3),
		"edge": dust.darkened(0.5)}))
	crown.set_instance_shader_parameter(&"seed", randf())
	_live.append({"n": crown, "t": 0.0, "life": 0.8, "kind": "crown", "at": at, "s": size, "b": up})
	_sparks(at + Vector3(0.0, 0.2, 0.0), Vector3.UP, col, int(10 * size))
	_shards(at, size, dust, col)
	for e: Dictionary in _live.slice(_live.size() - 5):
		_apply(e)


## Парирование — звонкий металл: белая вспышка-звезда (крупнее и короче, чем у попадания), горизонтальный блик-штрих,
## кольцо поперёк удара, широкий веер светлых искр навстречу удару. at — где встретились клинки, dir — куда шёл удар врага.
func parry(at: Vector3, dir: Vector3, col: Color) -> void:
	if not is_instance_valid(parent):
		return
	var d := -dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	var b := _basis(d)
	var hot := col.lerp(Color(1.0, 0.84, 0.55), 0.65)       # металл: цвет энергии почти выбелен
	var star := _node(_quad(), _mat("impact", 0, hot, 3.8))
	star.global_position = at
	star.set_instance_shader_parameter(&"roll", randf_range(-0.2, 0.2))
	_live.append({"n": star, "t": 0.0, "life": 0.09, "kind": "star", "s": 1.8})
	var glint := _node(_quad(), _mat("impact", 0, hot, 3.2))
	glint.global_position = at
	_live.append({"n": glint, "t": 0.0, "life": 0.16, "kind": "glint", "s": 3.4})
	var ring := _node(_quad(), _mat("ring", 2, hot, 2.4))
	ring.global_transform = Transform3D(Basis(b.z, b.y, b.x), at)
	_live.append({"n": ring, "t": 0.0, "life": 0.22, "kind": "ring", "s": 1.7, "b": ring.global_transform.basis})
	var s := b.z                                 # искры брызжут вдоль клинков — веером в стороны, а не в лицо врагу
	for k: float in [1.0, -1.0]:
		_sparks(at, (s * k + d * 0.35 + Vector3.UP * 0.25).normalized(), Color(1.0, 0.86, 0.62), 18, 32.0,
			Vector2(7.0, 16.0), 0.24, 6.0)
	for e: Dictionary in _live.slice(_live.size() - 3):
		_apply(e)


## Блок — удар принят на клинок: тусклая короткая вспышка, толчок (маленькое кольцо), горсть рыжих искр — падают.
func block(at: Vector3, dir: Vector3, col: Color) -> void:
	if not is_instance_valid(parent):
		return
	var d := -dir.normalized() if dir.length() > 0.01 else Vector3.BACK
	var b := _basis(d)
	var dull := col.lerp(Color(1.0, 0.55, 0.28), 0.55)
	var star := _node(_quad(), _mat("impact", 0, dull, 1.8))
	star.global_position = at
	star.set_instance_shader_parameter(&"roll", randf_range(-0.5, 0.5))
	_live.append({"n": star, "t": 0.0, "life": 0.07, "kind": "star", "s": 0.8})
	var ring := _node(_quad(), _mat("ring", 2, dull, 1.1))
	ring.global_transform = Transform3D(Basis(b.z, b.y, b.x), at)
	_live.append({"n": ring, "t": 0.0, "life": 0.16, "kind": "ring", "s": 0.9, "b": ring.global_transform.basis})
	var s := b.z * (1.0 if randf() < 0.5 else -1.0)  # горсть искр соскальзывает с клинка в одну сторону
	_sparks(at, (s + d * 0.3 + Vector3.UP * 0.5).normalized(), Color(1.0, 0.5, 0.2), 10, 35.0, Vector2(3.0, 7.0),
		0.3, 12.0)
	for e: Dictionary in _live.slice(_live.size() - 2):
		_apply(e)


## След клинка (взмах, промах): серп из маски slash прорисовывается по ходу взмаха и тает. at — грудь героя,
## fwd — куда он бьёт, side — +1 взмах слева направо, −1 справа налево; tilt — наклон серпа, рад; size — длина, м.
func trail(at: Vector3, fwd: Vector3, col: Color, side := 1.0, tilt := 0.35, reach := 1.2, size := 2.6) -> void:
	if not is_instance_valid(parent):
		return
	var f := Vector3(fwd.x, 0.0, fwd.z)
	f = f.normalized() if f.length() > 0.01 else Vector3.FORWARD
	var r := f.cross(Vector3.UP).normalized() * signf(side)
	var bx := r.rotated(f, tilt * signf(side))
	var by := Vector3.UP.rotated(f, tilt * signf(side))
	var arc := _node(_quad(), _mat("slash", 2, col, 2.6))
	arc.global_transform = Transform3D(Basis(bx * size, by * size * 0.32, f), at + f * reach)
	_live.append({"n": arc, "t": 0.0, "life": 0.3, "kind": "trail"})
	_apply(_live[-1])


## Осколки приземления: крупные камни (кувыркаются, падают), раскалённые сколы цвета приёма, мелкая крошка.
func _shards(at: Vector3, size: float, dust: Color, col: Color) -> void:
	var k := size / 3.0
	_chunks(at, int(26 * k), dust.darkened(0.45), Vector3(0.16, 0.11, 0.13), Vector2(5.0, 11.0) * sqrt(k), 45.0, 1.0, false)
	_chunks(at, int(40 * k), dust.darkened(0.25), Vector3(0.06, 0.05, 0.05), Vector2(6.0, 14.0) * sqrt(k), 60.0, 0.8, false)
	_chunks(at, int(18 * k), col, Vector3(0.05, 0.03, 0.04), Vector2(7.0, 15.0) * sqrt(k), 55.0, 0.6, true)


func _chunks(at: Vector3, amount: int, c: Color, box: Vector3, speed: Vector2, spread: float, life: float,
		hot: bool) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.92
	p.amount = maxi(4, amount)
	p.lifetime = life
	p.local_coords = false
	p.process_material = _chunk_pm(speed, spread)
	p.draw_pass_1 = _chunk_mesh(box, c, hot)
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(p)
	p.global_position = at + Vector3(0.0, 0.15, 0.0)
	p.emitting = true
	p.finished.connect(p.queue_free)


## Ресурсы частиц — один раз на набор параметров, а не на каждый эффект: новый материал процесса, CurveTexture и
## материал сетки на каждое приземление (4 комплекта) — это новые буферы и текстура на сервере рендера посреди боя.
static var _shrink_end: CurveTexture         # к концу — меньше: падают и пропадают, а не проваливаются в землю
static var _shrink_lin: CurveTexture
var _pms := {}
var _draw := {}


static func _curve_tex(pts: Array) -> CurveTexture:
	var cv := Curve.new()
	for pt: Vector2 in pts:
		cv.add_point(pt)
	var t := CurveTexture.new()
	t.curve = cv
	return t


func _chunk_pm(speed: Vector2, spread: float) -> ParticleProcessMaterial:
	var key := "c%s%s" % [speed, spread]
	if _pms.has(key):
		return _pms[key]
	if _shrink_end == null:
		_shrink_end = _curve_tex([Vector2(0.0, 1.0), Vector2(0.75, 1.0), Vector2(1.0, 0.0)])
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.5
	pm.direction = Vector3.UP
	pm.spread = spread
	pm.initial_velocity_min = speed.x
	pm.initial_velocity_max = speed.y
	pm.gravity = Vector3(0.0, -19.0, 0.0)
	pm.particle_flag_rotate_y = true
	pm.angle_min = -180.0
	pm.angle_max = 180.0
	pm.angular_velocity_min = -540.0
	pm.angular_velocity_max = 540.0
	pm.scale_min = 0.5
	pm.scale_max = 1.7
	pm.scale_curve = _shrink_end
	_pms[key] = pm
	return pm


func _chunk_mesh(box: Vector3, c: Color, hot: bool) -> BoxMesh:
	var key := "c%s%s%s" % [box, c, hot]
	if _draw.has(key):
		return _draw[key]
	var m := BoxMesh.new()
	m.size = box
	var mat := StandardMaterial3D.new()
	if hot:                                      # раскалённый скол — светится цветом приёма
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(c.r * 3.0, c.g * 3.0, c.b * 3.0)
	else:
		mat.albedo_color = c
		mat.roughness = 1.0
	m.material = mat
	_draw[key] = m
	return m


## Искры по направлению удара: узкий конус вперёд, быстрые, со шлейфом; к концу жизни тоньше — гаснут, а не висят.
## Направление у каждого удара своё — материал процесса свой, а кривая, лента и её материал общие (по цвету).
func _sparks(at: Vector3, dir: Vector3, col: Color, amount: int, spread := 28.0, speed := Vector2(7.0, 15.0),
		life := 0.2, fall := 2.0) -> void:
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 0.95
	p.amount = amount
	p.lifetime = life
	p.local_coords = false
	if _shrink_lin == null:
		_shrink_lin = _curve_tex([Vector2(0.0, 1.0), Vector2(1.0, 0.0)])
	var pm := ParticleProcessMaterial.new()
	pm.direction = dir
	pm.spread = spread
	pm.initial_velocity_min = speed.x
	pm.initial_velocity_max = speed.y
	pm.gravity = Vector3(0.0, -fall, 0.0)
	pm.damping_min = 2.0
	pm.damping_max = 5.0
	pm.scale_curve = _shrink_lin
	p.process_material = pm
	p.trail_enabled = true
	p.trail_lifetime = 0.06
	p.draw_pass_1 = _spark_trail(col)
	parent.add_child(p)
	p.global_position = at
	p.emitting = true
	p.finished.connect(p.queue_free)


func _spark_trail(col: Color) -> RibbonTrailMesh:
	var key := "s%s" % col
	if _draw.has(key):
		return _draw[key]
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
	_draw[key] = tm
	return tm


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
		"glint":                                # блик парирования: тонкий штрих поперёк кадра, вытягивается и гаснет
			var s := float(e.s) * lerpf(0.5, 1.2, _out(t))
			mi.scale = Vector3(s, s * 0.09, 1.0)
			mi.set_instance_shader_parameter(&"glow", 2.2 * (1.0 - t) * (1.0 - t))
			mi.set_instance_shader_parameter(&"progress", t * 0.4)
		"trail":                                # след клинка: прорисовывается по ходу взмаха, держится, тает
			mi.set_instance_shader_parameter(&"reveal", clampf(t / 0.3, 0.0, 1.0) * 1.1)
			mi.set_instance_shader_parameter(&"progress", _out(clampf((t - 0.3) / 0.7, 0.0, 1.0)))
			mi.set_instance_shader_parameter(&"glow", 1.6 if t < 0.3 else lerpf(1.6, 0.5, (t - 0.3) / 0.7))
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
		"wall":                                 # стена волны: быстро расходится, растёт и оседает
			var r := float(e.s) * lerpf(0.15, 1.0, _out(t))
			var h := float(e.s) * 0.32 * lerpf(0.4, 1.0, _out(minf(1.0, t * 2.5))) * (1.0 - 0.5 * t)
			var at: Vector3 = e.at
			mi.global_transform = Transform3D(Basis(Vector3.DOWN * h, Vector3.FORWARD * r, Vector3.RIGHT * r),
				at + Vector3(0.0, h, 0.0))
			mi.set_instance_shader_parameter(&"glow", 1.4 * (1.0 - t))
			mi.set_instance_shader_parameter(&"progress", clampf(t * 1.05, 0.0, 1.0))
		"crown":                                # пыль: воронка вверх-наружу, медленнее волны, тает
			var r := float(e.s) * lerpf(0.2, 0.75, _out(t))
			var h := float(e.s) * lerpf(0.15, 0.55, _out(t))
			var at: Vector3 = e.at
			mi.global_transform = Transform3D(Basis(Vector3.UP * h, Vector3.FORWARD * r, Vector3.RIGHT * r), at)
			mi.set_instance_shader_parameter(&"glow", 1.0 - t * 0.6)
			mi.set_instance_shader_parameter(&"progress", clampf(t * 1.1 - 0.1, 0.0, 1.0))
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
