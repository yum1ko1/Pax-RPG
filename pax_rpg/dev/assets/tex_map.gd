extends SceneTree
## Номер t<N>.dds каждой картинки glb (тот же обход, что в bake_textures.gd: MeshInstance3D по порядку, поверхности,
## слоты) → JSON {путь от models: [N для картинки 0, 1, … или -1]}. По нему mark_glb.py пишет номер в саму заглушку
## картинки, и игра (assets.gd → _textures) берёт DDS по номеру из пикселя, а не по своему обходу: загрузчик игры
## раскладывал картинки иначе (у героя с 10 картинками номера съезжали — в цвет и металл шли чужие карты).
##   godot --headless --path <любой проект> -s tex_map.gd -- <папка models мода> <выход.json>
## Берёт все модели, у которых есть папка <name>.tex.

const SLOTS := [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ORM,
	BaseMaterial3D.TEXTURE_ROUGHNESS, BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_EMISSION,
	BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]


func _init() -> void:
	var a := OS.get_cmdline_user_args()
	var root: String = a[0]
	var out := {}
	for rel: String in _glbs(root, ""):
		if not DirAccess.dir_exists_absolute(root.path_join(rel.get_basename() + ".tex")):
			continue
		var d := GLTFDocument.new()
		var st := GLTFState.new()
		if d.append_from_file(root.path_join(rel), st) != OK:
			continue
		var sc := d.generate_scene(st)
		var imgs := st.get_images()
		var seen: Array = []
		for mi: Node in sc.find_children("*", "MeshInstance3D", true, false):
			var m := (mi as MeshInstance3D).mesh
			if m == null:
				continue
			for s: int in m.get_surface_count():
				var mat := m.surface_get_material(s) as BaseMaterial3D
				if mat == null:
					continue
				for slot: int in SLOTS:
					var t := mat.get_texture(slot)
					if t != null and not seen.has(t):
						seen.append(t)
		var map: Array = []
		for i: int in imgs.size():
			map.append(seen.find(imgs[i]))
		out[rel] = map
		sc.free()
	var f := FileAccess.open(a[1], FileAccess.WRITE)
	f.store_string(JSON.stringify(out, " ", true))
	f.close()
	print("tex_map: %d моделей" % out.size())
	quit()


func _glbs(root: String, sub: String) -> Array:
	var res: Array = []
	var dir := DirAccess.open(root.path_join(sub))
	for f: String in dir.get_files():
		if f.ends_with(".glb"):
			res.append(sub.path_join(f) if sub != "" else f)
	for dd: String in dir.get_directories():
		if not dd.ends_with(".tex"):
			res.append_array(_glbs(root, sub.path_join(dd) if sub != "" else dd))
	return res
