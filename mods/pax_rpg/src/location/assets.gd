extends RefCounted
## Модели мода, как в больших играх:
##  • кэш — glb разбирается один раз, копии делят сетки, материалы и текстуры (раньше 32 жителя = 32 комплекта 4K);
##  • сжатые текстуры — DDS (BC1/BC3, с mip-уровнями) из <name>.tex/ вместо картинок glb: в видеопамяти в 4–8 раз
##    меньше (готовит pax_rpg/dev/assets/bake_textures.gd, картинки из glb убирает strip_glb.py);
##  • LOD — у неподвижных моделей движок строит упрощённые сетки и вдали рисует их (ImporterMesh.generate_lods);
##  • стриминг — у больших моделей сначала лёгкие 512 px (t<N>_lo.dds), полные 2048 подгружаются, когда модель
##    ближе NEAR м к камере, и выгружаются дальше FAR (stream_tick — раз в полсекунды, не больше SWAPS за раз).

const Bg := preload("res://mods/pax_rpg/src/location/bg.gd")
const SLOTS := [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ORM,
	BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_EMISSION,
	BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]
const LOD_MIN_TRIS := 3000           # сетки проще — без LOD
const NEAR := 70.0                   # дальше — реже переключение лёгких/полных текстур на глазах (видеопамяти хватает)
const FAR := 95.0
const SWAPS := 8                      # было 2: при сотне моделей полные текстуры вблизи подгружались по десятку секунд — стены «мылились»

static var _cache := {}              # путь → образец (вне дерева)
static var _streams: Array = []      # {tex: ImageTexture, hi, lo, pts: Array[Vector3], nodes: Array, hi_on: bool}
static var _by_path := {}            # путь → индексы в _streams
static var _lod_ok := 0              # 0 — не проверяли, 1 — работает, -1 — в этой сборке нет упрощения сеток


## Копия модели; null — нет файла.
static func model(mod: PaxMod, path: String) -> Node3D:
	if not _cache.has(path):
		var t0 := Time.get_ticks_msec()
		var m := mod.model(path)
		if m == null:
			return null
		var t1 := Time.get_ticks_msec()
		var base := lod_base(path)
		var bm: Node3D = model(mod, base) if base != "" else null   # LOD-копия: материалы (текстуры, стриминг) — у основной
		if bm != null:
			bm.free()
			_share_materials(_cache[base] as Node3D, m)
		else:
			_textures(mod, path, m)
		var t2 := Time.get_ticks_msec()
		_lods(m)
		if SHADOW_PROXY.has(path):
			_shadow_proxy(m)
		var t3 := Time.get_ticks_msec()
		if t3 - t0 > 150:                               # журнал загрузки: что из моделей долгое
			print("[pax_rpg] load: model %s — glb %d, textures %d, lod %d ms" % [path.get_file(), t1 - t0, t2 - t1, t3 - t2])
		_cache[path] = m
	return (_cache[path] as Node3D).duplicate() as Node3D


## LOD-копии: <name>_lod1.glb (средняя даль), <name>_lod2.glb (дальняя), <name>_lo.glb (прежние) → путь основной.
static func lod_base(path: String) -> String:
	for suf: String in ["_lod1.glb", "_lod2.glb", "_lo.glb"]:
		if path.ends_with(suf):
			return path.trim_suffix(suf) + ".glb"
	return ""


## Материалы основной модели — на поверхности копии по порядку обхода (у упрощённой те же поверхности).
static func _share_materials(src: Node3D, dst: Node3D) -> void:
	var mats: Array = []
	for mi: Node in src.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null:
			continue
		for si: int in inst.mesh.get_surface_count():
			var mat := inst.get_surface_override_material(si)
			mats.append(mat if mat != null else inst.mesh.surface_get_material(si))
	if mats.is_empty():
		return
	var k := 0
	for mi: Node in dst.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null:
			continue
		for si: int in inst.mesh.get_surface_count():
			inst.mesh.surface_set_material(si, mats[mini(k, mats.size() - 1)])
			k += 1


## Где стоят копии модели (для стриминга): узлы (герой, жители) или точки (MultiMesh города).
static func track(path: String, node: Node3D = null, points: Array = []) -> void:
	for i: int in _by_path.get(path, []):
		var s: Dictionary = _streams[i]
		if node != null:
			(s.nodes as Array).append(node)
		(s.pts as Array).append_array(points)


## Локация ушла — забыть, где что стояло, и вернуть лёгкие текстуры (кэш моделей остаётся).
static func clear_tracking(mod: PaxMod) -> void:
	for s: Dictionary in _streams:
		(s.pts as Array).clear()
		(s.nodes as Array).clear()
		if bool(s.hi_on):
			_swap(mod, s, false)


static func stream_tick(mod: PaxMod, cam: Vector3) -> void:
	for s: Dictionary in _streams:
		if bool(s.get("queued", false)):
			continue
		var d := INF
		for p: Vector3 in s.pts:
			d = minf(d, p.distance_squared_to(cam))
		var alive: Array = []
		for n: Variant in s.nodes:
			if is_instance_valid(n):
				alive.append(n)
				d = minf(d, (n as Node3D).global_position.distance_squared_to(cam))
		s.nodes = alive
		var want := d < NEAR * NEAR if not bool(s.hi_on) else d < FAR * FAR
		if want != bool(s.hi_on):
			s.queued = true
			_queue.append([s, want])


## Смена текстуры — по одной за кадр и без остановки кадра: файл читается здесь, разбор DDS — в потоке (Bg),
## загрузка в видеокарту — снова здесь. Раньше до SWAPS полных текстур (по ~5.6 МБ) читались и разбирались
## в одном кадре — на ходу кадр дёргался.
static var _queue: Array = []
static var _busy := false


static func stream_pump(mod: PaxMod) -> void:
	if _busy or _queue.is_empty():
		return
	var job: Array = _queue.pop_front()
	_swap_async(mod, job[0], job[1])


static func _swap_async(mod: PaxMod, s: Dictionary, hi: bool) -> void:
	_busy = true
	var b := mod.read_bytes(str(s.hi if hi else s.lo))
	var img: Variant = null
	if not b.is_empty():
		img = await Bg.run(func() -> Variant:
			var im := Image.new()
			return im if im.load_dds_from_buffer(b) == OK else null)
	if img is Image and s.tex is ImageTexture:
		(s.tex as ImageTexture).set_image(img)
		s.hi_on = hi
	s.queued = false
	_busy = false


static func _swap(mod: PaxMod, s: Dictionary, hi: bool) -> void:
	var img := _dds(mod, str(s.hi if hi else s.lo))
	if img == null:
		return
	(s.tex as ImageTexture).set_image(img)
	s.hi_on = hi


## Отдельная картинка мода: если рядом лежит <name>.dds (BC7/BC5 — pax_rpg/dev/assets/tex_bc7.gd), берём его — в
## видеопамяти вчетверо меньше несжатой, mip — те же, что строила игра (или их нет — как у картинки); иначе — как раньше,
## mod.texture. Одна текстура на путь, пока её кто-то держит (слабая ссылка: кэш не держит видеопамять сам).
static var _dds_tex := {}            # путь → WeakRef на ImageTexture из .dds
static var _no_dds := {}             # пути, у которых .dds нет (файл не читаем повторно)


static func tex(mod: PaxMod, path: String) -> Texture2D:
	if path == "" or _no_dds.has(path):
		return mod.texture(path)
	var w: WeakRef = _dds_tex.get(path)
	if w != null:
		var t := w.get_ref() as Texture2D
		if t != null:
			return t
	var img := _dds(mod, path.get_basename() + ".dds")
	if img == null:
		_no_dds[path] = true
		return mod.texture(path)
	var it := ImageTexture.create_from_image(img)
	_dds_tex[path] = weakref(it)
	return it


## Текстура из DDS, общая для всех моделей с тем же содержимым файла (ключ — MD5 байтов). Слабая ссылка: держат её
## материалы моделей (кэш образцов), не этот словарь.
static var _shared_tex := {}


static func _shared(mod: PaxMod, rel: String) -> ImageTexture:
	var b := mod.read_bytes(rel)
	if b.is_empty():
		return null
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_MD5)
	hc.update(b)
	var key := hc.finish().hex_encode()
	var w: WeakRef = _shared_tex.get(key)
	if w != null:
		var t := w.get_ref() as ImageTexture
		if t != null:
			return t
	var img := Image.new()
	if img.load_dds_from_buffer(b) != OK:
		return null
	var it := ImageTexture.create_from_image(img)
	_shared_tex[key] = weakref(it)
	return it


static func _dds(mod: PaxMod, rel: String) -> Image:
	var b := mod.read_bytes(rel)
	if b.is_empty():
		return null
	var img := Image.new()
	return img if img.load_dds_from_buffer(b) == OK else null


## Картинки glb (их уже нет — 1×1) → DDS из <name>.tex/: тот же обход, что у bake_textures.gd.
static func _textures(mod: PaxMod, path: String, m: Node3D) -> void:
	var dir := path.get_basename() + ".tex/"
	var seen: Array = []
	var repl := {}                                       # картинка glb → общая текстура из DDS
	for mi: Node in m.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null:
			continue
		for si: int in inst.mesh.get_surface_count():
			var mat := inst.get_surface_override_material(si)
			if mat == null:
				mat = inst.mesh.surface_get_material(si)
			if not (mat is BaseMaterial3D):
				continue
			_pbr(mat as BaseMaterial3D)
			if DETAIL.any(func(k: String) -> bool: return path.contains(k)):
				_detail(mod, mat as BaseMaterial3D)
			if path.contains("goblin") or path.contains("orc"):    # кожа — свет просвечивает (уши, пальцы)
				var bm3 := mat as BaseMaterial3D
				bm3.subsurf_scatter_enabled = true
				bm3.subsurf_scatter_strength = 0.25
				bm3.subsurf_scatter_skin_mode = true
			for slot: int in SLOTS:
				var t: Texture2D = (mat as BaseMaterial3D).get_texture(slot)
				if t != null and repl.has(t):
					(mat as BaseMaterial3D).set_texture(slot, repl[t])   # та же картинка у другой поверхности модели
					continue
				if t == null or seen.has(t):
					continue
				seen.append(t)
				var n := seen.size() - 1
				var hi := dir + "t%d.dds" % n
				var lo := dir + "t%d_lo.dds" % n
				var has_lo := not mod.read_bytes(lo).is_empty()
				if not has_lo:
					# без стриминга (лёгкой копии нет): одинаковый DDS у разных моделей — одна текстура в видеопамяти
					# (у семи дубов одни и те же кора, листва и нормали 4096²: было по копии на каждый)
					var sh := _shared(mod, hi)
					if sh != null:
						repl[t] = sh
						(mat as BaseMaterial3D).set_texture(slot, sh)
					continue                                   # нет файла — остаётся как в glb
				var img := _dds(mod, lo if has_lo else hi)
				if img == null:
					continue                                   # не упакована — остаётся как в glb
				if t is ImageTexture:
					(t as ImageTexture).set_image(img)
				else:
					var it := ImageTexture.create_from_image(img)
					for sl: int in SLOTS:
						if (mat as BaseMaterial3D).get_texture(sl) == t:
							(mat as BaseMaterial3D).set_texture(sl, it)
					t = it
				if has_lo:
					var idx: Array = _by_path.get(path, [])
					idx.append(_streams.size())
					_by_path[path] = idx
					_streams.append({"tex": t, "hi": hi, "lo": lo, "pts": [], "nodes": [], "hi_on": false})


## Большие постройки Meshy: вся модель — на одном атласе 2048, и вблизи стена из 2–3 пикселей на сантиметр
## мылится. Поверх — мелкое зерно дерева и камня (textures/detail, трипланарно в мировых метрах, тайл 2 м):
## яркость ±6 % и рельеф нормалей, цвет и рисунок атласа не меняются.
const DETAIL := [   # постройки — в house_detail.gd (city.gd → BUILDINGS)
	"yurt_noble", "market_stall_hide", "tusk_arch", "guardian_statue"]
static var _det_a: Texture2D
static var _det_n: Texture2D


static func _detail(mod: PaxMod, m: BaseMaterial3D) -> void:
	if _det_a == null:
		_det_a = mod.texture("textures/detail/grain_albedo.png")
		_det_n = mod.texture("textures/detail/grain_normal.png")
	if _det_a == null:
		return
	m.detail_enabled = true
	m.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MUL
	m.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	m.detail_albedo = _det_a
	m.detail_normal = _det_n
	m.uv2_triplanar = true
	m.uv2_world_triplanar = true
	m.uv2_scale = Vector3(0.5, 0.5, 0.5)
	m.uv2_triplanar_sharpness = 4.0


## PBR моделей Meshy: рассеяние Burley (мягче Lambert на камне, ткани, коже), отражения GGX, нормальная доля зеркальности
## у неметаллов, анизотропная фильтрация. Металличность — из текстуры модели; без текстуры у неметалла — 0.
static func _pbr(m: BaseMaterial3D) -> void:
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.metallic_specular = 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if m.metallic_texture == null and m.metallic > 0.0 and not m.resource_name.to_lower().contains("metal"):
		m.metallic = 0.0                                   # Meshy ставит металличность 1 и без карты — всё «пластиковое»
	# дерево, камень, ткань — матовые: при шероховатости от 0.25 Meshy-вещи блестели лаком, и отражения (SSR) на их
	# плоскостях мерцали при каждом движении камеры — у всех ящиков, лавок, столов разом. Металл и стекло — как были
	var nm := m.resource_name.to_lower()
	if nm.contains("metal") or nm.contains("glass") or m.metallic > 0.0:
		m.roughness = clampf(m.roughness, 0.25, 1.0)
	else:
		m.roughness_texture = null                         # карта шероховатости умножается — тёмная давала лак и при 0.7
		m.roughness = clampf(maxf(m.roughness, 0.85), 0.85, 1.0)
		m.metallic_specular = 0.3


## LOD для сеток: у неподвижных и у скинованных (жители-гоблины по 37k треугольников ×40 — 1.5M в кадре без LOD;
## у скинованных LOD — только другой список индексов, кости и веса те же). С морфами — без LOD.
const SKIN_LOD := true
const STATIC_LOD := false             # постройки 10–40k треугольников — дёшево и без LOD (было: грани и пятна вблизи)
static func _lods(m: Node3D) -> void:
	if _lod_ok == 0:
		_lod_ok = 1 if _lod_works() else -1
	if _lod_ok < 0:
		return
	for mi: Node in m.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null or not (inst.mesh is ArrayMesh):
			continue
		if inst.skin != null and not SKIN_LOD:
			continue
		if inst.skin == null and not STATIC_LOD:
			continue                                         # дома Meshy: упрощение рвёт швы UV — стены в рваных треугольниках
		var am := inst.mesh as ArrayMesh
		var tris := 0
		for si: int in am.get_surface_count():
			tris += am.surface_get_array_index_len(si) / 3
		if tris < LOD_MIN_TRIS or am.get_blend_shape_count() > 0:
			continue
		var im := ImporterMesh.new()
		for si: int in am.get_surface_count():
			im.add_surface(am.surface_get_primitive_type(si), am.surface_get_arrays(si), [], {},
				am.surface_get_material(si), am.surface_get_name(si),
				am.surface_get_format(si) & Mesh.ARRAY_FLAG_USE_8_BONE_WEIGHTS)
		im.generate_lods(25.0, 60.0, [])
		var any := false
		for si: int in im.get_surface_count():
			any = any or im.get_surface_lod_count(si) > 0
		# сетку, которая не упростилась (швы UV Meshy на каждой вершине), оставляем как есть. Раньше такая сетка
		# первой поверхностью выключала LOD у всех моделей до конца игры (_lod_ok = -1)
		if any:
			inst.mesh = im.get_mesh()


## Есть ли в этой сборке упрощение сеток (meshoptimizer): шар 64×32 упрощается всегда.
static func _lod_works() -> bool:
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, SphereMesh.new().get_mesh_arrays())
	im.generate_lods(25.0, 60.0, [])
	return im.get_surface_count() > 0 and im.get_surface_lod_count(0) > 0


## Тень лёгкой на вид, но тяжёлой модели (катана с ножнами на поясе героя — 87k треугольников, 18 сеток): она в
## каждом каскаде солнца и в 6 гранях тени каждого огня рядом с героем (тень огня у героя перерисовывается каждый кадр).
## Тень даёт одна копия: все сетки модели одной, вершины сварены по месту (швы UV и нормалей тени не нужны), у неё LOD
## движка — его погрешность меньше пикселя с камеры (выбирает по расстоянию до камеры и в проходах теней). Сами
## сетки тень не отбрасывают, видны как были. Копия — дочерний узел модели: прячется и двигается вместе с ней.
const SHADOW_PROXY := ["models/weapons/katana.glb", "models/weapons/katana_saya.glb", "models/weapons/katana_sheathed.glb"]
static var _proxy_mat: StandardMaterial3D


static func _shadow_proxy(m: Node3D) -> void:
	if _lod_ok < 0:
		return
	var verts := PackedVector3Array()
	var idx := PackedInt32Array()
	var at := {}                                         # место вершины → номер (сварка)
	var parts: Array = []                                # в осях корня модели: копия — его дочерний узел
	if m is MeshInstance3D and (m as MeshInstance3D).mesh != null:
		parts.append([m, Transform3D.IDENTITY])
	for c: Node in m.get_children():
		_mesh_nodes(c, Transform3D.IDENTITY, parts)
	if parts.is_empty():
		return
	for pr: Array in parts:
		var inst: MeshInstance3D = pr[0]
		var xf: Transform3D = pr[1]
		for si: int in inst.mesh.get_surface_count():
			if inst.mesh.surface_get_primitive_type(si) != Mesh.PRIMITIVE_TRIANGLES:
				return                                   # не треугольники — без копии, как было
			var arr := inst.mesh.surface_get_arrays(si)
			var vs: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var ix: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
			var remap := PackedInt32Array()
			remap.resize(vs.size())
			for i: int in vs.size():
				var p := xf * vs[i]
				var k: int = at.get(p, -1)
				if k < 0:
					k = verts.size()
					at[p] = k
					verts.append(p)
				remap[i] = k
			if ix.is_empty():
				for i: int in vs.size():
					idx.append(remap[i])
			else:
				for i: int in ix:
					idx.append(remap[i])
	var nrm := PackedVector3Array()                      # гладкие нормали — LOD бережёт форму по ним
	nrm.resize(verts.size())
	for t: int in range(0, idx.size() - 2, 3):
		var fn := (verts[idx[t + 1]] - verts[idx[t]]).cross(verts[idx[t + 2]] - verts[idx[t]])
		nrm[idx[t]] += fn
		nrm[idx[t + 1]] += fn
		nrm[idx[t + 2]] += fn
	for i: int in nrm.size():
		nrm[i] = nrm[i].normalized() if nrm[i].length_squared() > 0.0 else Vector3.UP
	if _proxy_mat == null:
		_proxy_mat = StandardMaterial3D.new()
		_proxy_mat.cull_mode = BaseMaterial3D.CULL_DISABLED   # как у сеток модели (Meshy/Blender — двусторонние)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = nrm
	arrays[Mesh.ARRAY_INDEX] = idx
	var im := ImporterMesh.new()
	im.add_surface(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, _proxy_mat, "shadow")
	im.generate_lods(60.0, 60.0, [])
	if im.get_surface_count() == 0 or im.get_surface_lod_count(0) == 0:
		return                                           # не упростилась — пусть тень дают сами сетки
	var px := MeshInstance3D.new()
	px.name = "ShadowLod"
	px.mesh = im.get_mesh()
	px.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	px.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	m.add_child(px)
	for pr: Array in parts:
		(pr[0] as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Сетки модели (не скинованные) и их место в осях модели — модель ещё вне дерева, по локальным преобразованиям.
static func _mesh_nodes(n: Node, xf: Transform3D, out: Array) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null and (n as MeshInstance3D).skin == null:
		out.append([n, here])
	for c: Node in n.get_children():
		_mesh_nodes(c, here, out)
