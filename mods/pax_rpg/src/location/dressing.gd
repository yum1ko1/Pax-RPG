## Убранство улиц из планировки («proxy» в config/<город>.json, левел-дизайн входа в Гхарн): окна, дым, факелы,
## решётка ворот, занавеси над дверями, вывески на кронштейнах, полотнища на гирляндах, лужи, колеи, лепестки,
## мусор, зарево. Простые формы и материалы города — потом часть заменим моделями, расстановка останется.
## Люди (guard/crier/person) — не здесь: жители-гоблины (location.gd → _spawn_dressing_npcs).
extends RefCounted

const PALETTE := [Color(0.62, 0.06, 0.05), Color(0.06, 0.05, 0.05), Color(0.72, 0.5, 0.12), Color(0.48, 0.03, 0.03),
	Color(0.1, 0.28, 0.27)]                            # киноварь, чёрный, золото, тёмная киноварь, бирюза (редко)
var city                                            # city.gd: root, lights, glass, mod, vfx
var _mats := {}
var _font: SystemFont


func _init(c) -> void:
	city = c


func _m(key: String, col: Color, rough := 0.85, metal := 0.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	_mats[key] = m
	return m


## Коробка убранства — в пакет города (city.gd → batch_box): сотни мелочей одним вызовом отрисовки на ячейку.
func _box(size: Vector3, pos: Vector3, basis: Basis, mat: Material) -> void:
	var tiny := size.length() < 0.6                   # щепки, солома, черепки: без тени, дальше 50 м не рисуются (< 1 px)
	city.batch_box(size, basis, pos, mat,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if tiny else GeometryInstance3D.SHADOW_CASTING_SETTING_ON,
		50.0 if tiny else 0.0)


## Ткань на ветру: шейдер флагов (как бельё и знамёна), цвет — палитра района.
func _cloth(size: Vector2, col: Color, xf: Transform3D, amp := 0.06) -> void:
	var q := QuadMesh.new()
	q.size = size
	q.subdivide_width = 3
	q.subdivide_depth = 5
	var mi := MeshInstance3D.new()
	mi.mesh = q
	var sh: Shader = city.mod.shader("shaders/flag.gdshader")
	if sh != null:
		var g := Gradient.new()
		g.set_color(0, col.lightened(0.05))
		g.set_color(1, col.darkened(0.25))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.width = 8
		gt.height = 8
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("tex", gt)
		m.set_shader_parameter("amp", amp)
		mi.material_override = m
	else:
		var sm := StandardMaterial3D.new()
		sm.albedo_color = col
		sm.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = sm
	mi.transform = xf
	city.root.add_child(mi)


func add(d: Dictionary, pos: Vector3) -> void:
	var k := str(d.proxy)
	var ry := deg_to_rad(float(d.get("r", 0.0)))
	var b := Basis(Vector3.UP, ry)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(pos.x * 131.0 + pos.z * 17.0)
	match k:
		"window":                                       # тёплое окно: стекло города (ночью светится, daynight.gd)
			var q := QuadMesh.new()
			q.size = Vector2(0.62, 0.5)
			var gm := StandardMaterial3D.new()
			city._glass(gm)
			q.material = gm
			var mi := MeshInstance3D.new()
			mi.mesh = q
			mi.transform = Transform3D(b, pos)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			city.root.add_child(mi)
			_box(Vector3(0.74, 0.07, 0.08), pos + b * Vector3(0, -0.29, 0.03), b, _m("wood_d", Color(0.13, 0.08, 0.05)))
		"smoke":
			city.vfx.smoke(city.root, pos, 0.7, Color(0.32, 0.3, 0.33, 0.32), 10, 0.45)
		"torch":
			_box(Vector3(0.08, 0.6, 0.08), pos, Basis(), _m("wood_d", Color(0.13, 0.08, 0.05)))
			_box(Vector3(0.16, 0.12, 0.16), pos + Vector3(0, 0.32, 0), Basis(), _m("iron", Color(0.05, 0.05, 0.055), 0.45, 0.8))
			city.lights.append([city.vfx.fire(city.root, pos + Vector3(0, 0.36, 0), 0.32, false), 1.6])
		"portcullis":                                   # решётка-герса, поднятая над проходом
			var w := float(d.get("w", 4.6))
			var h := float(d.get("h", 1.6))
			var iron := _m("iron", Color(0.05, 0.05, 0.055), 0.45, 0.8)
			var n := int(w / 0.42)
			for i: int in n + 1:
				_box(Vector3(0.08, h, 0.08), pos + b * Vector3(-w * 0.5 + i * w / n, h * 0.5, 0), b, iron)
			for j: int in 4:
				_box(Vector3(w, 0.07, 0.07), pos + b * Vector3(0, h * j / 3.0, 0), b, iron)
			for i: int in n + 1:                            # зубья внизу
				_box(Vector3(0.05, 0.22, 0.05), pos + b * Vector3(-w * 0.5 + i * w / n, -0.11, 0), b, iron)
		"noren":                                        # занавес над дверью лавки: три полотнища с покачиванием
			var col: Color = PALETTE[int(d.get("c2", 0)) % PALETTE.size()]
			_box(Vector3(1.9, 0.06, 0.06), pos + Vector3(0, 3.05, 0) + b * Vector3(0, 0, 0.1), b, _m("wood_d", Color(0.13, 0.08, 0.05)))
			for i: int in [-1, 0, 1]:
				_cloth(Vector2(0.56, 0.95), col, Transform3D(b, pos + b * Vector3(i * 0.6, 2.55, 0.12)), 0.04)
		"hang_sign":                                    # вывеска на кронштейне — над тротуаром, иероглиф с двух сторон
			var wood := _m("wood_d", Color(0.13, 0.08, 0.05))
			var out := b * Vector3(0, 0, 0.55)
			_box(Vector3(0.06, 0.06, 1.1), pos + Vector3(0, 3.5, 0) + out, b, wood)
			_box(Vector3(0.05, 0.42, 0.05), pos + Vector3(0, 3.28, 0) + b * Vector3(0, 0, 0.1), b, wood)
			var board := pos + Vector3(0, 2.92, 0) + b * Vector3(0, 0, 0.85)
			var sb := b * Basis(Vector3.UP, PI * 0.5)       # доска — поперёк фасада, видна вдоль улицы
			_box(Vector3(0.62, 0.9, 0.06), board, sb, _m("lac", Color(0.12, 0.04, 0.04), 0.4))
			_box(Vector3(0.68, 0.96, 0.03), board, sb, _m("gold", Color(0.8, 0.6, 0.26), 0.35, 1.0))
			var g := str(d.get("glyph", ""))
			if g != "":
				if _font == null:
					_font = SystemFont.new()
					_font.font_names = PackedStringArray(["Yu Mincho", "MS Mincho", "Noto Serif CJK JP", "SimSun"])
					_font.font_weight = 700
				for side: float in [1.0, -1.0]:
					var lb := Label3D.new()
					lb.text = g
					lb.font = _font
					lb.font_size = 96
					lb.pixel_size = 0.004
					lb.modulate = Color(0.95, 0.78, 0.4)
					lb.outline_size = 0
					lb.transform = Transform3D(sb * Basis(Vector3.UP, 0.0 if side > 0 else PI), board + sb * Vector3(0, 0, 0.05 * side))
					city.root.add_child(lb)
		"banner_x":                                     # полотнище с верёвки гирлянды
			var ln := float(d.get("ln", 1.8))
			var col2: Color = PALETTE[int(d.get("c2", 0)) % PALETTE.size()]
			_cloth(Vector2(0.7, ln), col2, Transform3D(Basis(Vector3.UP, PI * 0.5), pos - Vector3(0, ln * 0.5, 0)), 0.08)
		"puddle":                                       # лужа: тёмная гладкая вода — отражает фонари
			var mi2 := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.5
			cm.bottom_radius = 0.5
			cm.height = 0.01
			cm.radial_segments = 20
			cm.material = _m("water", Color(0.03, 0.035, 0.045), 0.03, 0.2)
			mi2.mesh = cm
			mi2.transform = Transform3D(b.scaled(Vector3(float(d.get("w", 2.0)), 1.0, float(d.get("d", 1.2)))), pos + Vector3(0, 0.035, 0))
			mi2.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			city.root.add_child(mi2)
		"ruts":                                         # колеи повозок
			var ln2 := float(d.get("len", 20.0))
			for s: float in [-0.8, 0.8]:
				_box(Vector3(0.32, 0.012, ln2), pos + b * Vector3(s, 0.03, 0), b, _m("rut", Color(0.06, 0.045, 0.035), 0.95))
		"petals":                                       # лепестки сакуры пятном
			var r := float(d.get("w", 3.0))
			var pm := _m("petal", Color(0.86, 0.42, 0.55), 0.8)
			for i: int in 40:
				var a := rng.randf() * TAU
				var dd := sqrt(rng.randf()) * r
				_box(Vector3(0.07, 0.005, 0.05), pos + Vector3(cos(a) * dd, 0.03, sin(a) * dd * 0.8),
					Basis(Vector3.UP, rng.randf() * TAU), pm)
		"debris":                                       # мусор: щепки, черепки, бумага / солома
			var straw := str(d.get("mat_", "")) == "straw"
			var cols := [Color(0.25, 0.15, 0.08), Color(0.45, 0.2, 0.12), Color(0.75, 0.7, 0.6), Color(0.12, 0.1, 0.09)]
			for i: int in int(d.get("n", 6)):
				var q2 := pos + Vector3(rng.randf_range(-0.7, 0.7), 0.025, rng.randf_range(-0.7, 0.7))
				var bb := Basis(Vector3.UP, rng.randf() * TAU)
				if straw:
					_box(Vector3(rng.randf_range(0.2, 0.5), 0.012, 0.02), q2, bb, _m("straw", Color(0.55, 0.42, 0.18)))
				else:
					var c: Color = cols[rng.randi() % cols.size()]
					_box(Vector3(rng.randf_range(0.06, 0.28), 0.015, rng.randf_range(0.04, 0.12)), q2, bb,
						_m("deb%d" % int(c.r * 100), c))
		"glow":                                         # контровое зарево: цель пути светлее
			var ol := OmniLight3D.new()
			ol.light_color = Color(1.0, 0.5, 0.2)
			ol.omni_range = 16.0
			ol.light_energy = 1.2
			ol.shadow_enabled = false
			ol.position = pos + Vector3(0, float(d.get("h", 4.0)), 0)
			city.root.add_child(ol)
			city.lights.append([ol, 1.6])
