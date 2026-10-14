extends RefCounted
## «Разлом» — ультимейт большого меча Разрубателя (location.gd → _quake_wave): земля как после землетрясения.
##  • crack — декаль расколотой земли: радиальные трещины с ветками, вокруг — потемневшая разбитая корка; из трещин
##    светится мана (текстура свечения декали); держится, потом тает. Рисунок — свой, без файла (один раз за сессию);
##  • spikes — каменные шипы вырываются из-под земли по кольцу волны (гранёные, с наклоном наружу, пыль), миг стоят и
##    уходят обратно в землю.

static var _crack_alb: ImageTexture
static var _crack_emi: ImageTexture
static var _rock: StandardMaterial3D


## Нарисовать трещины заранее (прогрев под экраном загрузки) — на первом «Разломе» не будет рывка.
static func prepare() -> void:
	if _crack_alb == null:
		_make_crack_textures()


static func crack(mod: PaxMod, parent: Node, at: Vector3, radius: float, stay: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _crack_alb == null:
		_make_crack_textures()
	var d := Decal.new()
	d.texture_albedo = _crack_alb
	d.texture_emission = _crack_emi
	d.emission_energy = 2.2
	d.size = Vector3(radius * 2.0, 2.0, radius * 2.0)
	d.albedo_mix = 1.0
	d.upper_fade = 0.2
	d.lower_fade = 0.3
	d.modulate = Color(1, 1, 1, 0)
	parent.add_child(d)
	d.global_position = at + Vector3(0.0, 0.4, 0.0)
	d.rotation.y = randf() * TAU
	d.scale = Vector3(0.3, 1.0, 0.3)
	var tw := d.create_tween()
	tw.tween_property(d, "modulate:a", 1.0, 0.12)
	tw.parallel().tween_property(d, "scale", Vector3.ONE, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	tw.tween_property(d, "emission_energy", 0.6, 1.5)        # мана в трещинах остывает, трещины остаются
	tw.tween_interval(maxf(0.0, stay - 1.5))
	tw.tween_property(d, "modulate:a", 0.0, 2.0)
	tw.tween_callback(d.queue_free)


## Трещины: из центра 11 кривых лучей, у каждого ветки; маска толщины → альбедо (тёмные щели, корка вокруг) и
## свечение (только сердцевина щели).
static func _make_crack_textures() -> void:
	var n := 256
	var mask := PackedFloat32Array()
	mask.resize(n * n)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7071
	var c := Vector2(n, n) * 0.5
	for k: int in 11:
		var ang := TAU * k / 11.0 + rng.randf_range(-0.2, 0.2)
		_crack_line(mask, n, c + Vector2(cos(ang), sin(ang)) * 5.0, ang, n * 0.46, 3.0, rng, 2)
	var alb := Image.create(n, n, true, Image.FORMAT_RGBA8)
	var emi := Image.create(n, n, true, Image.FORMAT_RGBA8)
	var noise := FastNoiseLite.new()
	noise.seed = 3
	noise.frequency = 0.04
	for y: int in n:
		for x: int in n:
			var m := mask[y * n + x]
			var r := Vector2(x, y).distance_to(c) / (n * 0.5)
			var crust := (1.0 - smoothstep(0.35, 1.0, r)) * (0.35 + 0.25 * noise.get_noise_2d(x, y))   # разбитая корка
			var a := clampf(maxf(m, crust), 0.0, 1.0)
			var dark := lerpf(0.42, 0.04, clampf(m * 1.4, 0.0, 1.0))
			alb.set_pixel(x, y, Color(dark * 1.05, dark * 0.9, dark * 0.85, a))
			var core := smoothstep(0.55, 1.0, m)
			emi.set_pixel(x, y, Color(1.0 * core, 0.45 * core, 0.95 * core, 1.0))
	alb.generate_mipmaps()
	emi.generate_mipmaps()
	_crack_alb = ImageTexture.create_from_image(alb)
	_crack_emi = ImageTexture.create_from_image(emi)


## Кривая трещина: шаги со случайным изломом, толщина убывает к концу; с depth > 0 — ветки в стороны.
static func _crack_line(mask: PackedFloat32Array, n: int, from: Vector2, ang: float, length: float, width: float,
		rng: RandomNumberGenerator, depth: int) -> void:
	var p := from
	var a := ang
	var step := 3.5
	var steps := int(length / step)
	for s: int in steps:
		a += rng.randf_range(-0.35, 0.35)
		var nxt := p + Vector2(cos(a), sin(a)) * step
		var w := width * (1.0 - float(s) / steps) + 0.8
		_stamp(mask, n, nxt, w)
		if depth > 0 and rng.randf() < 0.09:
			_crack_line(mask, n, nxt, a + rng.randf_range(0.5, 1.1) * (1.0 if rng.randf() < 0.5 else -1.0),
				length * rng.randf_range(0.2, 0.4), w * 0.7, rng, depth - 1)
		p = nxt


static func _stamp(mask: PackedFloat32Array, n: int, at: Vector2, w: float) -> void:
	var r := int(ceil(w)) + 1
	for y: int in range(maxi(0, int(at.y) - r), mini(n, int(at.y) + r + 1)):
		for x: int in range(maxi(0, int(at.x) - r), mini(n, int(at.x) + r + 1)):
			var v := 1.0 - smoothstep(w * 0.4, w, Vector2(x, y).distance_to(at))
			if v > mask[y * n + x]:
				mask[y * n + x] = v


## Шипы по кольцу r_in..r_out вокруг at: вырываются из-под земли, стоят hold секунд и уходят обратно.
static func spikes(mod: PaxMod, parent: Node, at: Vector3, r_in: float, r_out: float, count: int, hold: float) -> void:
	if parent == null or not parent.is_inside_tree():
		return
	if _rock == null:
		_rock = StandardMaterial3D.new()
		_rock.albedo_color = Color(0.36, 0.31, 0.32)
		_rock.roughness = 0.92
		var tex := mod.texture("models/gharn/tex/cobble.jpg")
		if tex != null:
			_rock.albedo_texture = tex
			_rock.uv1_triplanar = true
			_rock.uv1_world_triplanar = true
			_rock.uv1_scale = Vector3.ONE * 0.6
		_rock.emission_enabled = true                      # по граням — отсвет маны из глубины
		_rock.emission = Color(0.55, 0.2, 0.6)
		_rock.emission_energy_multiplier = 0.25
	for i: int in count:
		var ang := randf() * TAU
		var r := randf_range(r_in, r_out)
		var h := randf_range(0.9, 2.4) * (0.7 + 0.3 * r / maxf(r_out, 0.1))
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = randf_range(0.18, 0.42)
		cm.height = h
		cm.radial_segments = 5                             # гранёный камень, а не гладкий конус
		cm.rings = 1
		cm.material = _rock
		mi.mesh = cm
		parent.add_child(mi)
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var base := at + out * r
		var tilt := Basis(out.cross(Vector3.UP).normalized(), -deg_to_rad(randf_range(8.0, 28.0)))   # наклон наружу
		var b := tilt * Basis(Vector3.UP, randf() * TAU)
		var up_pos := base + b.y * (h * 0.5 - 0.15)
		var down_pos := base - b.y * (h * 0.55)
		mi.global_transform = Transform3D(b, down_pos)
		var tw := mi.create_tween()
		tw.tween_interval(randf_range(0.0, 0.12))
		tw.tween_property(mi, "global_position", up_pos, 0.11).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
		tw.tween_interval(hold + randf_range(0.0, 0.4))
		tw.tween_property(mi, "global_position", down_pos, 0.5).set_ease(Tween.EASE_IN)
		tw.tween_callback(mi.queue_free)
