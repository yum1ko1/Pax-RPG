extends RefCounted
## Модели мода, как в больших играх:
##  • кэш — glb разбирается один раз, копии делят сетки, материалы и текстуры (раньше 32 жителя = 32 комплекта 4K);
##  • сжатые текстуры — DDS (BC1/BC3, с mip-уровнями) из <name>.tex/ вместо картинок glb: в видеопамяти в 4–8 раз
##    меньше (готовит pax_rpg/dev/assets/bake_textures.gd, картинки из glb убирает strip_glb.py);
##  • LOD — у неподвижных моделей движок строит упрощённые сетки и вдали рисует их (ImporterMesh.generate_lods);
##  • стриминг — у больших моделей сначала лёгкие 512 px (t<N>_lo.dds), полные 2048 подгружаются, когда модель
##    ближе NEAR м к камере, и выгружаются дальше FAR (stream_tick — раз в полсекунды, не больше SWAPS за раз).

const SLOTS := [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ORM,
	BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_EMISSION,
	BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]
const LOD_MIN_TRIS := 3000           # сетки проще — без LOD
const NEAR := 70.0                   # дальше — реже переключение лёгких/полных текстур на глазах (видеопамяти хватает)
const FAR := 95.0
const SWAPS := 2

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
		_textures(mod, path, m)
		var t2 := Time.get_ticks_msec()
		_lods(m)
		var t3 := Time.get_ticks_msec()
		if t3 - t0 > 150:                               # журнал загрузки: что из моделей долгое
			print("[pax_rpg] load: model %s — glb %d, textures %d, lod %d ms" % [path.get_file(), t1 - t0, t2 - t1, t3 - t2])
		_cache[path] = m
	return (_cache[path] as Node3D).duplicate() as Node3D


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
	var swaps := 0
	for s: Dictionary in _streams:
		var d := INF
		for p: Vector3 in s.pts:
			d = minf(d, p.distance_to(cam))
		var alive: Array = []
		for n: Variant in s.nodes:
			if is_instance_valid(n):
				alive.append(n)
				d = minf(d, (n as Node3D).global_position.distance_to(cam))
		s.nodes = alive
		var want := d < NEAR if not bool(s.hi_on) else d < FAR
		if want != bool(s.hi_on):
			_swap(mod, s, want)
			swaps += 1
			if swaps >= SWAPS:
				return


static func _swap(mod: PaxMod, s: Dictionary, hi: bool) -> void:
	var img := _dds(mod, str(s.hi if hi else s.lo))
	if img == null:
		return
	(s.tex as ImageTexture).set_image(img)
	s.hi_on = hi


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
			for slot: int in SLOTS:
				var t: Texture2D = (mat as BaseMaterial3D).get_texture(slot)
				if t == null or seen.has(t):
					continue
				seen.append(t)
				var n := seen.size() - 1
				var hi := dir + "t%d.dds" % n
				var lo := dir + "t%d_lo.dds" % n
				var has_lo := not mod.read_bytes(lo).is_empty()
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


## PBR моделей Meshy: рассеяние Burley (мягче Lambert на камне, ткани, коже), отражения GGX, нормальная доля зеркальности
## у неметаллов, анизотропная фильтрация. Металличность — из текстуры модели; без текстуры у неметалла — 0.
static func _pbr(m: BaseMaterial3D) -> void:
	m.diffuse_mode = BaseMaterial3D.DIFFUSE_BURLEY
	m.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	m.metallic_specular = 0.5
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if m.metallic_texture == null and m.metallic > 0.0 and not m.resource_name.to_lower().contains("metal"):
		m.metallic = 0.0                                   # Meshy ставит металличность 1 и без карты — всё «пластиковое»
	m.roughness = clampf(m.roughness, 0.25, 1.0)


## LOD для неподвижных сеток (у скинованных — нет: их меньше и они близко).
static func _lods(m: Node3D) -> void:
	if _lod_ok < 0:
		return
	for mi: Node in m.find_children("*", "MeshInstance3D", true, false):
		var inst := mi as MeshInstance3D
		if inst.mesh == null or not (inst.mesh is ArrayMesh) or inst.skin != null:
			continue
		var am := inst.mesh as ArrayMesh
		var tris := 0
		for si: int in am.get_surface_count():
			tris += am.surface_get_array_index_len(si) / 3
		if tris < LOD_MIN_TRIS or am.get_blend_shape_count() > 0:
			continue
		var im := ImporterMesh.new()
		for si: int in am.get_surface_count():
			im.add_surface(am.surface_get_primitive_type(si), am.surface_get_arrays(si), [], {},
				am.surface_get_material(si), am.surface_get_name(si))
		im.generate_lods(25.0, 60.0, [])
		if im.get_surface_count() == 0 or im.get_surface_lod_count(0) == 0:
			_lod_ok = -1                                     # упрощения сеток в этой сборке нет — не пробовать
			return
		_lod_ok = 1
		inst.mesh = im.get_mesh()
