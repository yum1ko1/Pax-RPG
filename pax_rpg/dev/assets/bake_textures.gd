extends SceneTree
## Текстуры моделей мода → сжатые DDS (S3TC: BC1 без альфы, BC3 с альфой) с mip-уровнями, как в больших играх:
## в видеопамяти в 4–8 раз меньше несжатых. Для каждой модели <name>.glb — папка <name>.tex/ с t<N>.dds (полное)
## и t<N>_lo.dds (512 px — грузится сразу, полное подменяет вблизи: assets.gd). N — порядок текстуры при обходе
## сцены (MeshInstance3D по порядку, поверхности, слоты материала) — тот же обход делает игра.
## Запуск (редакторская сборка Godot — в игре сжатия нет):
##   godot --headless --path <любой проект> -s bake_textures.gd -- <папка исходных glb> <папка models мода> [bc5]
## bc5 — карты нормалей в BC5 (RGTC: два канала по 8 бит, без «кубиков» BC1; z восстанавливает шейдер).
## Исходники (с JPEG внутри) лежат в pax_rpg/dev/models_src/, в мод уходят glb без картинок (strip_glb.py).

const SLOTS := [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ORM,
	BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_EMISSION,
	BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]
const LO := 512


static func textures_of(scene: Node) -> Array:
	var out: Array = []
	for mi: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s: int in m.mesh.get_surface_count():
			var mat := m.get_surface_override_material(s)
			if mat == null:
				mat = m.mesh.surface_get_material(s)
			if not (mat is BaseMaterial3D):
				continue
			for slot: int in SLOTS:
				var t: Texture2D = (mat as BaseMaterial3D).get_texture(slot)
				if t != null and not out.has(t):
					out.append(t)
	return out


static func albedos_of(scene: Node) -> Array:
	var out: Array = []
	for mi: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s: int in m.mesh.get_surface_count():
			var mat := m.get_surface_override_material(s)
			if mat == null:
				mat = m.mesh.surface_get_material(s)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).albedo_texture != null:
				out.append((mat as BaseMaterial3D).albedo_texture)
	return out


static func normals_of(scene: Node) -> Array:
	var out: Array = []
	for mi: Node in scene.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		for s: int in m.mesh.get_surface_count():
			var mat := m.get_surface_override_material(s)
			if mat == null:
				mat = m.mesh.surface_get_material(s)
			if mat is BaseMaterial3D and (mat as BaseMaterial3D).normal_texture != null:
				out.append((mat as BaseMaterial3D).normal_texture)
	return out


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var src_dir := args[0]
	var dst_dir := args[1]
	var files: Array = []
	_walk(src_dir, "", files)
	# 4-й аргумент — файл со списком ближних моделей (по строке: путь без .glb, напр. gharn/khan_palace) — им 4K
	var near: Array = []
	if args.size() > 3 and FileAccess.file_exists(args[3]):
		for line: String in FileAccess.get_file_as_string(args[3]).split("\n"):
			if line.strip_edges() != "" and not line.begins_with("#"):
				near.append(line.strip_edges())
	for rel: String in files:
		var doc := GLTFDocument.new()
		var st := GLTFState.new()
		if doc.append_from_file(src_dir.path_join(rel), st) != OK:
			print("skip ", rel)
			continue
		var scene := doc.generate_scene(st)
		var texs := textures_of(scene)
		var normals := normals_of(scene) if args.size() > 2 and args[2] == "bc5" else []
		var albedos := albedos_of(scene)
		if texs.is_empty():
			scene.free()
			continue
		# полное разрешение: персонажи и детальные большие модели — 2048, большие простые — 1024, мелочь — 512
		var ext := _extent(scene)
		var skinned := not scene.find_children("*", "Skeleton3D", true, false).is_empty()
		var big := ext > 4.0 or skinned
		var hi_max := 2048 if skinned or (big and _tris(scene) >= 5000) else (1024 if big else 512)
		if near.has(rel.get_basename()):
			hi_max = 4096                          # ближние (исходный цвет 4K: главные постройки) — 4K
		var out_dir := dst_dir.path_join(rel.get_basename() + ".tex")
		DirAccess.make_dir_recursive_absolute(out_dir)
		var t0 := Time.get_ticks_msec()
		for n: int in texs.size():
			var img: Image = (texs[n] as Texture2D).get_image()
			if img == null or img.is_empty():
				continue
			if img.is_compressed():
				img.decompress()
			if img.has_mipmaps():
				img.clear_mipmaps()
			var alpha := img.detect_alpha() != Image.ALPHA_NONE
			img.convert(Image.FORMAT_RGBA8 if alpha else Image.FORMAT_RGB8)
			var nm := normals.has(texs[n])
			if nm:
				img.convert(Image.FORMAT_RGB8)
			# у ближних (4K) — 4K только цвет; нормали, шероховатость и металл — 2K: разницы не видно, памяти вдвое меньше
			_save(img, hi_max if albedos.has(texs[n]) else mini(hi_max, 2048), out_dir.path_join("t%d.dds" % n), nm)
			if big:
				_save(img, LO, out_dir.path_join("t%d_lo.dds" % n), nm)
		print("%s: %d текстур, %s, %d мс" % [rel, texs.size(), ("%d+512" % hi_max) if big else "512", Time.get_ticks_msec() - t0])
		scene.free()
	quit()


func _save(src: Image, max_px: int, path: String, normal := false) -> void:
	var img := src.duplicate() as Image
	var m := maxi(img.get_width(), img.get_height())
	if m > max_px:
		var k := float(max_px) / m
		img.resize(maxi(4, int(img.get_width() * k)), maxi(4, int(img.get_height() * k)), Image.INTERPOLATE_LANCZOS)
	img.generate_mipmaps()
	if normal:
		img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL)   # S3TC + normal → RGTC (BC5)
	else:
		img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_GENERIC)
	img.save_dds(path)


func _tris(n: Node) -> int:
	var t := 0
	for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
		var m := (mi as MeshInstance3D).mesh
		if m is ArrayMesh:
			for si: int in m.get_surface_count():
				t += (m as ArrayMesh).surface_get_array_index_len(si) / 3
	return t


func _extent(n: Node) -> float:
	var box := AABB()
	var first := true
	for mi: Node in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		var t := Transform3D.IDENTITY
		var p: Node = m
		while p != null and p != n:
			if p is Node3D:
				t = (p as Node3D).transform * t
			p = p.get_parent()
		var a := t * m.mesh.get_aabb()
		box = a if first else box.merge(a)
		first = false
	return box.get_longest_axis_size()


func _walk(root: String, rel: String, out: Array) -> void:
	var d := DirAccess.open(root.path_join(rel))
	if d == null:
		return
	for f: String in d.get_files():
		if f.get_extension() == "glb":
			out.append(rel.path_join(f) if rel != "" else f)
	for sub: String in d.get_directories():
		_walk(root, rel.path_join(sub) if rel != "" else sub, out)
