extends RefCounted
## Сплошная трава города: пучки травинок (своя сетка, 7 травинок) MultiMesh-ячейками по CELL м — рисуются только
## ближние ячейки (дальше fade_end шейдер уже опустил траву в землю). Не растёт на дорогах (маска дорог города, R),
## реже на тропах (G), не растёт под постройками (прямоугольники city.rects) и на песке арены.
## Ветер, волны по полю и топтание героем — shaders/grass.gdshader. Конфиг — config/location.json → gfx.
##
## Загрузка: где расти — чистый расчёт в потоке (bg.gd → compute), результат — готовые буферы
## MultiMesh (16 чисел на пучок: матрица и цвет) — ставятся одним присваиванием, без цикла по копиям.
## Буферы запоминаются (_cache): повторный вход в город — без расчёта.

const Bg := preload("res://mods/pax_rpg/src/location/bg.gd")
const CELL := 16.0
const OCC := 0.5                   # м на клетку карты занятости

static var _cache := {}            # ключ → {Vector2i ячейка: PackedFloat32Array}

var count := 0
var done := false                  # трава поставлена (или её нет)


## Запустить (сопрограмма, можно не ждать): расчёт в потоке, потом трава встаёт под parent и зовётся on_done().
## Если уже считали — сразу.
func start(mod: PaxMod, parent: Node, layout: Dictionary, rects: Array, cfg: Dictionary, on_done: Callable) -> void:
	var density := float(cfg.get("grass_density", 6.0))
	var sh: Shader = mod.shader("shaders/grass.gdshader")
	var g: Array = layout.get("ground", [])
	if density <= 0.0 or sh == null or g.size() < 4:
		_finish(on_done)
		return
	var fade_end := float(cfg.get("grass_distance", 40.0))
	var gm: Dictionary = layout.get("ground_mask", {})
	var mask: Image = null
	var mt: Texture2D = mod.texture(str(gm.get("tex", "")))
	if mt != null:
		mask = mt.get_image()
		if mask != null and mask.is_compressed():
			mask.decompress()
	var input := {"density": density, "ground": g, "mask": mask, "mask_rect": gm.get("rect", [0, 0, 1, 1]),
		"rects": rects, "arena": layout.get("arena", [])}
	var key := str(hash(var_to_str([density, g, gm.get("tex", ""), rects.size(), layout.get("arena", [])])))
	if _cache.has(key):
		_spawn(parent, _cache[key], sh, fade_end)
		_finish(on_done)
		return
	var tg := Time.get_ticks_msec()
	var res: Variant = await Bg.run(func() -> Variant: return compute(input))
	print("[pax_rpg] load: grass computed %d ms (%s)" % [Time.get_ticks_msec() - tg, "ok" if res is Dictionary else "failed"])
	if res is Dictionary:
		_cache[key] = res
		if is_instance_valid(parent) and parent.is_inside_tree():
			_spawn(parent, res as Dictionary, sh, fade_end)
	_finish(on_done)                                     # ошибка в потоке — без травы, но загрузка не виснет


func _finish(on_done: Callable) -> void:
	done = true
	if on_done.is_valid():
		on_done.call()


## Ячейки → MultiMeshInstance3D (главный поток): сетка пучка, материал, буфер.
func _spawn(parent: Node, cells: Dictionary, sh: Shader, fade_end: float) -> void:
	var mat := ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("fade_end", fade_end)
	mat.set_shader_parameter("fade_start", fade_end * 0.7)
	var mesh := _clump()
	mesh.surface_set_material(0, mat)
	for key: Vector2i in cells:
		var buf: PackedFloat32Array = cells[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = mesh
		mm.instance_count = buf.size() / 16
		mm.buffer = buf
		var mi := MultiMeshInstance3D.new()
		mi.name = "Grass"
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED        # в отражённый свет (SDFGI) трава не входит
		mi.extra_cull_margin = 1.0                              # ветер наклоняет за рамку сетки
		mi.visibility_range_end = fade_end + CELL * 0.75
		parent.add_child(mi)
		count += mm.instance_count


## Чистый расчёт (поток): где растёт трава. Узлов и мода не трогает.
static func compute(input: Dictionary) -> Dictionary:
	var density := float(input.density)
	var g: Array = input.ground
	var gsize := Vector2(float(g[0]), float(g[1]))
	var gpos := Vector2(float(g[2]), float(g[3])) - gsize * 0.5
	var mask: Image = input.mask
	var r: Array = input.mask_rect
	var mr := Rect2(float(r[0]), float(r[1]), float(r[2]), float(r[3]))
	var occ := _occupancy(input.rects, gpos, gsize)
	var ow := int(ceil(gsize.x / OCC))
	var arena: Array = input.arena
	var rng := RandomNumberGenerator.new()
	rng.seed = 1047
	var step := 1.0 / sqrt(density)
	var cells := {}
	var y := gpos.y + 1.5
	while y < gpos.y + gsize.y - 1.5:
		var x := gpos.x + 1.5
		while x < gpos.x + gsize.x - 1.5:
			var px := x + rng.randf_range(-0.5, 0.5) * step
			var pz := y + rng.randf_range(-0.5, 0.5) * step
			x += step
			if occ[int((pz - gpos.y) / OCC) * ow + int((px - gpos.x) / OCC)] != 0:
				continue
			if arena.size() >= 3 and Vector2(px - float(arena[0]), pz - float(arena[1])).length() < float(arena[2]) + 3.0:
				continue
			if mask != null:
				var mu := clampi(int((px - mr.position.x) / mr.size.x * mask.get_width()), 0, mask.get_width() - 1)
				var mv := clampi(int((pz - mr.position.y) / mr.size.y * mask.get_height()), 0, mask.get_height() - 1)
				var mc := mask.get_pixel(mu, mv)
				if mc.r > 0.22 or rng.randf() < mc.g * 1.4:   # дорога — нет; тропа — редко, по краям
					continue
			var key := Vector2i(floori(px / CELL), floori(pz / CELL))
			if not cells.has(key):
				cells[key] = PackedFloat32Array()
			var s := rng.randf_range(0.75, 1.3)
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.8, 1.25), s))
			var buf: PackedFloat32Array = cells[key]
			cells[key] = PackedFloat32Array()             # одна ссылка на буфер — дописываем без копирования
			buf.append_array(PackedFloat32Array([b.x.x, b.y.x, b.z.x, px, b.x.y, b.y.y, b.z.y, 0.0, b.x.z, b.y.z, b.z.z, pz,
				rng.randf_range(0.85, 1.1), rng.randf_range(0.88, 1.08), rng.randf_range(0.85, 1.0), 1.0]))
			cells[key] = buf
		y += step
	return cells


## Где стоят постройки: 1 — занято (прямоугольники city.rects с запасом), 0 — свободно. Огромные (сама земля) — мимо.
static func _occupancy(rects: Array, gpos: Vector2, gsize: Vector2) -> PackedByteArray:
	var w := int(ceil(gsize.x / OCC))
	var h := int(ceil(gsize.y / OCC))
	var occ := PackedByteArray()
	occ.resize(w * h)
	for r: Variant in rects:
		var e: Array = r
		var c: Vector2 = e[0]
		var sz: Vector2 = e[1]
		if sz.x > 60.0 or sz.y > 60.0:
			continue
		var a := c - sz * 0.5 - Vector2(0.3, 0.3) - gpos
		var b := c + sz * 0.5 + Vector2(0.3, 0.3) - gpos
		for oz: int in range(maxi(0, int(a.y / OCC)), mini(h, int(b.y / OCC) + 1)):
			for ox: int in range(maxi(0, int(a.x / OCC)), mini(w, int(b.x / OCC) + 1)):
				occ[oz * w + ox] = 1
	return occ


## Пучок: 7 травинок веером, каждая — 3 звена, сужается к кончику и клонится наружу. UV.y — высота (0..1).
func _clump() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for b: int in 7:
		var ang := TAU * b / 7.0 + rng.randf_range(-0.3, 0.3)
		var out := Vector3(cos(ang), 0.0, sin(ang))
		var side := out.cross(Vector3.UP).normalized()
		var hb := rng.randf_range(0.3, 0.58)
		var lean := rng.randf_range(0.08, 0.2)
		var base := out * rng.randf_range(0.0, 0.07)
		var w := rng.randf_range(0.022, 0.034)
		var rows: Array = []
		for k: int in 4:
			var t := k / 3.0
			var p := base + out * lean * t * t + Vector3(0.0, hb * t, 0.0)
			var ww := w * pow(1.0 - t, 0.7) + 0.002
			rows.append([p - side * ww, p + side * ww, t])
		var nrm := out.normalized()
		for k: int in 3:
			var r0: Array = rows[k]
			var r1: Array = rows[k + 1]
			for v: Array in [[r0[0], 0.0, r0[2]], [r1[0], 0.0, r1[2]], [r1[1], 1.0, r1[2]],
					[r0[0], 0.0, r0[2]], [r1[1], 1.0, r1[2]], [r0[1], 1.0, r0[2]]]:
				st.set_normal(nrm)
				st.set_color(Color.WHITE)
				st.set_uv(Vector2(float(v[1]), float(v[2])))
				st.add_vertex(v[0])
	return st.commit()
