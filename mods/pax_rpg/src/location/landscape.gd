extends RefCounted
const Trace := preload("res://mods/pax_rpg/src/trace.gd")
## Мир за частоколом: степь холмами до горизонта (shaders/steppe.gdshader — текстура земли, волны ветра, тени облаков),
## горные хребты кольцом (ridged-шум, shaders/mountain.gdshader — скалы слоями, снег по высоте и уклону; дымка
## тумана делает их синими и далёкими), кочевые юрты на холмах. Без коллизий — герой за стену не выходит. Высоты — шум
## (FastNoiseLite), город — в плоской «чаше» (land: [центр X, центр Z, полуширина, полуглубина]).
##
## Загрузка: сетки считаются в потоке (bg.gd, compute — чистая функция) и запоминаются (_cache) —
## request() зовут ещё на глобусе (location.prewarm), к входу в город всё готово; повторный вход — без расчёта.
## build() — сопрограмма: ждёт данные кадрами (экран загрузки не замирает), потом только собирает сетки.
## Степь — CHUNKS×CHUNKS кусков, горы — SECTORS секторов: вне кадра и за камерой не рисуются (frustum).
## Нормали — по соседним точкам общей сетки высот: на стыках кусков нет швов света.
const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")
const Bg := preload("res://mods/pax_rpg/src/location/bg.gd")

static var outer := 0.0                 # м ровной земли за стеной (внешние кварталы: layout "outer")
const STEPPE_SIZE := 1400.0
const STEPPE_N := 140
const CHUNKS := 7
const MOUNT_R0 := 545.0
const MOUNT_R1 := 1550.0
const SECTORS := 24
const MOUNT_NA := 720
const MOUNT_NR := 84

static var hole := Vector3.ZERO       # x, z, радиус ямы арены в городе (city.gd): степь под ямой уходит вниз (не видна в вырезе)
static var _cache := {}            # _key(area) → {"steppe": [arrays…], "mountains": [arrays…]}
static var _pending := {}

var mod: PaxMod
var root: Node3D
var _noise: FastNoiseLite
var _flat := Rect2()


## Площадка города по планировке (как в city.gd: ground = [ширина, глубина, центр X, центр Z]).
static func _key(area: Rect2) -> String:
	return str(area) + str(hole) + str(outer)


static func area_of(layout: Dictionary) -> Rect2:
	var g: Array = layout.get("ground", [190, 186, 0, 0])
	var gw := Vector2(float(g[0]), float(g[1]))
	return Rect2(Vector2(float(g[2]), float(g[3])) - gw * 0.5, gw)


## Начать расчёт в потоке (если ещё не считали и не считаем).
static func request(area: Rect2) -> void:
	var key := _key(area)
	if _cache.has(key) or _pending.has(key):
		return
	_pending[key] = true
	_run_request(area, key)


## Сопрограмма: поток считает, кадры идут; ответ — в _cache (ошибка в потоке — считаем здесь).
static func _run_request(area: Rect2, key: String) -> void:
	Trace.mark("landscape: request " + key)
	var res: Variant = await Bg.run(func() -> Variant:
		Trace.mark("landscape: compute " + key)
		var r: Variant = compute(area)
		Trace.mark("landscape: computed " + key)
		return r)
	Trace.mark("landscape: done " + key)
	_cache[key] = res if res is Dictionary else compute(area)
	_pending.erase(key)


static func ready_for(area: Rect2) -> bool:
	return _cache.has(_key(area))


static func _steppe_noise() -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = 1047
	n.frequency = 0.0065
	n.fractal_octaves = 4
	return n


## Высота степи: в городе — ниже земли города, за стеной поднимается холмами.
static func steppe_h(n: FastNoiseLite, flat: Rect2, x: float, z: float) -> float:
	if hole.z > 0.0 and Vector2(x - hole.x, z - hole.y).length() < hole.z + 1.0:
		return -12.0                                   # под ямой арены — глубоко, ниже её пола (−4 м)
	var dx := maxf(0.0, absf(x - flat.get_center().x) - flat.size.x * 0.5)
	var dz := maxf(0.0, absf(z - flat.get_center().y) - flat.size.y * 0.5)
	var d := sqrt(dx * dx + dz * dz)
	var inner := minf(flat.size.x * 0.5 - absf(x - flat.get_center().x), flat.size.y * 0.5 - absf(z - flat.get_center().y))
	if inner > 12.0:
		return -3.0                                    # под землёй города — глубже: на 0.4 м вдали мерцало (z-fighting)
	var t := smoothstep(4.0 + outer, 90.0 + outer, d)   # outer — ровный пояс внешнего города вокруг стены
	var hills := (n.get_noise_2d(x, z) * 0.5 + 0.5) * 55.0 + n.get_noise_2d(x * 3.1, z * 3.1) * 5.0
	return lerpf(-0.4, hills + d * 0.02, t)


static func mountain_h(ridge: FastNoiseLite, big: FastNoiseLite, x: float, z: float) -> float:
	var r := sqrt(x * x + z * z)
	var amp := lerpf(110.0, 450.0, smoothstep(600.0, 1300.0, r)) * smoothstep(MOUNT_R0, 720.0, r)
	var v := ridge.get_noise_2d(x, z) * 0.5 + 0.5
	var b := big.get_noise_2d(x, z) * 0.5 + 0.5
	return -18.0 + amp * pow(v, 1.6) * (0.55 + 0.75 * b)


## Чистый расчёт (поток): массивы поверхностей кусков степи и секторов гор (SurfaceTool.commit_to_arrays — без
## обращений к рендеру). Узлов и мода не трогает.
static func compute(area: Rect2) -> Dictionary:
	return {"steppe": _compute_steppe(area), "mountains": _compute_mountains()}


static func _compute_steppe(flat: Rect2) -> Array:
	var n := _steppe_noise()
	var step := STEPPE_SIZE / STEPPE_N
	var c := flat.get_center()
	var x0 := c.x - STEPPE_SIZE * 0.5
	var z0 := c.y - STEPPE_SIZE * 0.5
	var w := STEPPE_N + 3                                 # сетка высот с запасом в клетку по краям — для нормалей
	var hs := PackedFloat32Array()
	hs.resize(w * w)
	for j: int in w:
		for i: int in w:
			hs[j * w + i] = steppe_h(n, flat, x0 + (i - 1) * step, z0 + (j - 1) * step)
	var grass := Color(0.52, 0.55, 0.3)
	var ochre := Color(0.78, 0.6, 0.4)
	var dry := Color(0.66, 0.56, 0.42)
	var per := STEPPE_N / CHUNKS
	var out: Array = []
	for cj: int in CHUNKS:
		for ci: int in CHUNKS:
			var st := SurfaceTool.new()
			st.begin(Mesh.PRIMITIVE_TRIANGLES)
			for j: int in per + 1:
				for i: int in per + 1:
					var gi := ci * per + i + 1
					var gj := cj * per + j + 1
					var x := x0 + (gi - 1) * step
					var z := z0 + (gj - 1) * step
					var h := hs[gj * w + gi]
					var k := n.get_noise_2d(x * 2.0 + 300.0, z * 2.0) * 0.5 + 0.5
					st.set_normal(Vector3(hs[gj * w + gi - 1] - hs[gj * w + gi + 1], 2.0 * step,
						hs[(gj - 1) * w + gi] - hs[(gj + 1) * w + gi]).normalized())
					st.set_color(ochre.lerp(grass, smoothstep(0.35, 0.75, k)).lerp(dry, smoothstep(18.0, 34.0, h) * 0.6))
					st.set_uv(Vector2(x, z) / 8.0)
					st.add_vertex(Vector3(x, h, z))
			_grid_indices(st, per + 1, per, per)
			st.generate_tangents()                        # для карты нормалей земли
			out.append(st.commit_to_arrays())
	return out


static func _compute_mountains() -> Array:
	var ridge := FastNoiseLite.new()
	ridge.seed = 77
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 6
	ridge.frequency = 0.0021
	var big := FastNoiseLite.new()
	big.seed = 78
	big.frequency = 0.0007
	var e := 3.0                                          # шаг для наклона: точки сетки гор слишком редки вдали
	var per := MOUNT_NA / SECTORS
	var out: Array = []
	for sec: int in SECTORS:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for j: int in MOUNT_NR + 1:
			var r := lerpf(MOUNT_R0, MOUNT_R1, pow(float(j) / MOUNT_NR, 1.25))     # ближе — гуще
			for i: int in per + 1:
				var a := TAU * float(sec * per + i) / MOUNT_NA
				var x := cos(a) * r
				var z := sin(a) * r
				var h := mountain_h(ridge, big, x, z)
				st.set_normal(Vector3(mountain_h(ridge, big, x - e, z) - mountain_h(ridge, big, x + e, z), 2.0 * e,
					mountain_h(ridge, big, x, z - e) - mountain_h(ridge, big, x, z + e)).normalized())
				st.add_vertex(Vector3(x, h, z))
		for j: int in MOUNT_NR:                           # вдоль радиуса — j, по кругу — i
			for i: int in per:
				var a0 := j * (per + 1) + i
				var b0 := a0 + per + 1
				for k: int in [a0, b0, a0 + 1, a0 + 1, b0, b0 + 1]:
					st.add_index(k)
		out.append(st.commit_to_arrays())
	return out


## Сетка треугольников: stride вершин в ряду, cols × rows квадратов (порядок обхода — лицом вверх).
static func _grid_indices(st: SurfaceTool, stride: int, cols: int, rows: int) -> void:
	for j: int in rows:
		for i: int in cols:
			var a := j * stride + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + stride)
			st.add_index(a + 1)
			st.add_index(a + stride + 1)
			st.add_index(a + stride)


## Сопрограмма: ждёт расчёт (кадрами — экран загрузки живой), собирает сетки, ставит юрты.
func build(m: PaxMod, parent: Node3D, area: Rect2) -> void:
	mod = m
	_flat = area
	_noise = _steppe_noise()
	root = Node3D.new()
	root.name = "Landscape"
	parent.add_child(root)
	request(area)
	var t0 := Time.get_ticks_msec()
	while not ready_for(area):
		if not is_instance_valid(root) or not root.is_inside_tree():
			return
		if Time.get_ticks_msec() - t0 > 30000:              # поток так и не ответил — считаем здесь, но не виснем
			_cache[_key(area)] = compute(area)
			break
		await root.get_tree().process_frame
	if not is_instance_valid(root):
		return
	var data: Dictionary = _cache[_key(area)]
	var steppe := _steppe_mat()
	for arr: Variant in data.get("steppe", []):
		_add_mesh(arr as Array, steppe, "Steppe")
	var mount := _mountain_mat()
	for arr: Variant in data.get("mountains", []):
		_add_mesh(arr as Array, mount, "Mountains")
	_camps()
	_backdrop()


func _add_mesh(arrays: Array, mat: Material, nm: String) -> void:
	var am := ArrayMesh.new()
	am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var mi := MeshInstance3D.new()
	mi.name = nm
	mi.mesh = am
	if mat != null:
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED        # даль — не в отражённый свет (SDFGI), дорого и не видно
	root.add_child(mi)


## Высота степи в точке (юрты ставятся по ней).
func height(x: float, z: float) -> float:
	return steppe_h(_noise, _flat, x, z)


func _steppe_mat() -> Material:
	var sh: Shader = mod.shader("shaders/steppe.gdshader")
	if sh != null:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("g_col", _tex("models/gharn/tex/ground.jpg", false))
		m.set_shader_parameter("g_nrm", _tex("models/gharn/tex/ground_n.jpg", true))
		return m
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _tex("models/gharn/tex/ground.jpg", false)
	mat.roughness = 0.95
	return mat


func _mountain_mat() -> Material:
	var sh: Shader = mod.shader("shaders/mountain.gdshader")
	if sh == null:
		return null
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("detail_n", _tex("models/gharn/tex/ground_n.jpg", true))
	return m


## Картинка мода с мипмапами (без них даль рябит).
func _tex(path: String, normal: bool) -> Texture2D:
	var tex := Assets.tex(mod, path)                 # .dds рядом (BC7/BC5 с mip) — сразу он
	if tex == null:
		return null
	var img := tex.get_image()
	if img != null and not img.is_compressed() and not img.has_mipmaps():
		if normal:
			img.generate_mipmaps(true)
		else:
			img.generate_mipmaps()
		return ImageTexture.create_from_image(img)
	return tex


## Кочевья на холмах: юрты по 2–4, где склон пологий.
func _camps() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var c := _flat.get_center()
	for camp: int in 9:
		var ang := TAU * camp / 9.0 + rng.randf_range(-0.2, 0.2)
		var r := rng.randf_range(150.0, 280.0)
		var cx := c.x + cos(ang) * r
		var cz := c.y + sin(ang) * r
		for k: int in rng.randi_range(2, 4):
			var x := cx + rng.randf_range(-14.0, 14.0)
			var z := cz + rng.randf_range(-14.0, 14.0)
			var y := yurt_y(x, z)
			var m := Assets.model(mod, "models/gharn/props/" + ("yurt_large.glb" if rng.randf() < 0.3 else "yurt_small.glb"))
			if m == null:
				return
			m.position = Vector3(x, y, z)
			m.rotation.y = rng.randf() * TAU
			root.add_child(m)
			for g: Node in m.find_children("*", "GeometryInstance3D", true, false):   # даль: без теней, за 320 м не рисуем
				(g as GeometryInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				(g as GeometryInstance3D).visibility_range_end = 320.0


## Высота сетки степи (как её рисует меш: клетки по STEPPE_SIZE / STEPPE_N м, билинейно) — на гребнях холмов
## меш ниже шума, и поставленное по шуму дерево издалека висело в воздухе.
func mesh_h(x: float, z: float) -> float:
	var step := STEPPE_SIZE / STEPPE_N
	var c := _flat.get_center()
	var fx := (x - (c.x - STEPPE_SIZE * 0.5)) / step
	var fz := (z - (c.y - STEPPE_SIZE * 0.5)) / step
	var ix := floorf(fx)
	var iz := floorf(fz)
	var gx := c.x - STEPPE_SIZE * 0.5 + ix * step
	var gz := c.y - STEPPE_SIZE * 0.5 + iz * step
	var a := height(gx, gz)
	var b := height(gx + step, gz)
	var d := height(gx, gz + step)
	var e := height(gx + step, gz + step)
	return lerpf(lerpf(a, b, fx - ix), lerpf(d, e, fx - ix), fz - iz)


## Дерево: по самой низкой из сетки и шума вокруг ствола — корни в земле, а не над склоном.
func tree_y(x: float, z: float) -> float:
	return minf(yurt_y(x, z), minf(mesh_h(x, z), minf(mesh_h(x - 1.5, z), mesh_h(x + 1.5, z)))) - 0.5


func yurt_y(x: float, z: float) -> float:
	return minf(minf(height(x - 2.0, z), height(x + 2.0, z)), minf(height(x, z - 2.0), height(x, z + 2.0)))


## Фон за стеной (без деталей, только силуэты в дымке): три тракта от ворот и концов Аллеи уходят в степь,
## вдоль них деревни (срубы и юрты — лёгкие LOD-копии), по холмам — рощи дубов и сакуры. MultiMesh на модель
## в каждом секторе по 45° вокруг города (сектор вне кадра не рисуется), без теней и коллизий.
## Прежняя дальность 520 м не срабатывала (центр рамки общего MultiMesh — в ≤ 400 м от любой точки Гхарна) — не ставим.
const BACK_SECTORS := 8
const YURT := "models/gharn/props/yurt_large.glb"


func _backdrop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var c := _flat.get_center()
	var half := _flat.size * 0.5
	var places := {}                                     # путь модели → [Transform3D]
	var put := func(path: String, x: float, z: float, s: float, yaw: float) -> void:
		if not places.has(path):
			places[path] = []
		var y := tree_y(x, z) if path.contains("/nature/") else yurt_y(x, z) - 0.15
		(places[path] as Array).append(Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), Vector3(x, y, z)))
	# тракты: от ворот на юг, от концов Аллеи на запад и восток — лёгкий изгиб, дальше 600 м
	var roads: Array = []
	for start: Array in [[Vector2(c.x, c.y + half.y + 8.0), Vector2(0, 1)], [Vector2(c.x - half.x - 8.0, c.y), Vector2(-1, 0)],
			[Vector2(c.x + half.x + 8.0, c.y), Vector2(1, 0)]]:
		var p: Vector2 = start[0]
		var d: Vector2 = start[1]
		var pts: Array = [p]
		for i: int in 30:
			d = d.rotated(rng.randf_range(-0.12, 0.12)).normalized()
			p += d * 20.0
			pts.append(p)
		roads.append(pts)
		_road_strip(pts, 5.0)
	# деревни у трактов: дома фасадом к дороге по обе стороны
	# дальние копии (_lod2): прежних *_lo.glb нет — две трети мест в деревнях оставались пустыми
	var houses := ["models/gharn/house_timber_a_lod2.glb", "models/gharn/house_timber_b_lod2.glb", "models/gharn/house_two_b_lod2.glb"]
	for pts: Array in roads:
		for vi: int in [8, 17, 26]:
			var a: Vector2 = pts[vi]
			var b: Vector2 = pts[vi + 1]
			var dir := (b - a).normalized()
			var nrm := Vector2(-dir.y, dir.x)
			for k: int in rng.randi_range(5, 8):
				var t := rng.randf_range(-30.0, 30.0)
				var side := 1.0 if k % 2 == 0 else -1.0
				var q := a + dir * t + nrm * side * rng.randf_range(11.0, 16.0)
				var yaw := atan2(-nrm.x * side, -nrm.y * side)
				if rng.randf() < 0.65:
					put.call(houses[rng.randi() % houses.size()], q.x, q.y, 1.0, yaw)
				else:
					put.call(YURT, q.x, q.y, 1.0, rng.randf() * TAU)
	# рощи по холмам: кучки деревьев, гуще к центру рощи; не на трактах и не у стены
	var trees := ["models/nature/oak_big_1.glb", "models/nature/oak_big_2.glb", "models/nature/oak_medium_1.glb",
		"models/nature/oak_medium_2.glb", "models/nature/oak_medium_3.glb", "models/nature/oak_small_1.glb",
		"models/nature/oak_small_2.glb"]                 # лес, а не сакура из горшка
	for grove: int in 20:                                # рощи — 3.4M треугольников в кадре было при 22×(18–45)
		var ang := rng.randf() * TAU
		var r := rng.randf_range(170.0, 560.0)
		var gc := c + Vector2(cos(ang), sin(ang)) * r
		var n := rng.randi_range(18, 34)
		for k: int in n:
			var q := gc + Vector2(rng.randfn(0.0, 18.0), rng.randfn(0.0, 18.0))   # гуще — лес, а не одиночки
			var near_road := false
			for pts: Array in roads:
				for v: Variant in pts:
					if (v as Vector2).distance_squared_to(q) < 100.0:
						near_road = true
			if near_road or (absf(q.x - c.x) < half.x + 60.0 and absf(q.y - c.y) < half.y + 60.0):
				continue
			put.call(trees[rng.randi() % trees.size()], q.x, q.y, rng.randf_range(0.9, 1.5), rng.randf() * TAU)
	for path: String in places:
		var src := Assets.model(mod, path)
		if src == null:
			continue
		# секторами вокруг города: один MultiMesh на весь круг (рамка ~1.2 км) камера не отсекала — рощи и деревни
		# за спиной рисовались каждый кадр (~1 млн треугольников)
		var sectors := {}
		for t: Variant in places[path]:
			var o := (t as Transform3D).origin
			var s := posmod(floori((atan2(o.z - c.y, o.x - c.x) + PI) / TAU * BACK_SECTORS), BACK_SECTORS)
			if not sectors.has(s):
				sectors[s] = []
			(sectors[s] as Array).append(t)
		for mi: Node in src.find_children("*", "MeshInstance3D", true, false):
			var g := mi as MeshInstance3D
			if g.mesh == null:
				continue
			var rel := src.global_transform.affine_inverse() * g.global_transform if src.is_inside_tree() else _rel(src, g)
			for s: Variant in sectors:
				var list: Array = sectors[s]
				var mm := MultiMesh.new()
				mm.transform_format = MultiMesh.TRANSFORM_3D
				mm.mesh = g.mesh
				mm.instance_count = list.size()
				for i: int in list.size():
					mm.set_instance_transform(i, (list[i] as Transform3D) * rel)
				var mmi := MultiMeshInstance3D.new()
				mmi.multimesh = mm
				mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mmi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
				root.add_child(mmi)
		src.free()


func _rel(top: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != top:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t


## Тракт в степи: лента 5 м по рельефу (чуть выше земли), утоптанная глина.
func _road_strip(pts: Array, w: float) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in pts.size() - 1:
		var a: Vector2 = pts[i]
		var b: Vector2 = pts[i + 1]
		var nrm := (b - a).normalized().orthogonal() * w * 0.5
		var seg := 4
		for k: int in seg:
			var p0 := a.lerp(b, float(k) / seg)
			var p1 := a.lerp(b, float(k + 1) / seg)
			var v := [p0 - nrm, p0 + nrm, p1 + nrm, p1 - nrm]
			var v3: Array = []
			for q: Vector2 in v:
				v3.append(Vector3(q.x, height(q.x, q.y) + 0.9, q.y))   # сетка степи 10 м — выше, чтобы не тонула
			for idx: int in [0, 1, 2, 0, 2, 3]:
				st.set_normal(Vector3.UP)
				st.add_vertex(v3[idx])
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.42, 0.31, 0.22)
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var mi := MeshInstance3D.new()
	mi.name = "BackRoad"
	mi.mesh = st.commit()
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi)
