extends RefCounted
## Сборка города из планировки (config/<город>.json, генератор — pax_rpg/dev/gharn/gharn_layout.py):
## земля, модели (glb мода) и простые блоки (терраса, пандус, холм). Одинаковые модели ставятся пачкой —
## по MultiMeshInstance3D на каждую сетку модели (сотни бочек и тайлов дороги — пара вызовов отрисовки).
## Коллизия «c»: коробка по габаритам модели (здания, стены, юрты) — мелочь и деревья не мешают ходить.

const MATS := {"stone": Color(0.49, 0.48, 0.45), "stone_cut": Color(0.55, 0.53, 0.49), "stone_dark": Color(0.36, 0.35, 0.33),
	"earth": Color(0.6, 0.45, 0.28)}

var mod: PaxMod
var root: Node3D
var rects: Array = []          # [центр XZ, размер XZ, цвет] — для миникарты
var count := 0


func build(m: PaxMod, parent: Node, data: Dictionary) -> void:
	mod = m
	root = Node3D.new()
	root.name = "City"
	parent.add_child(root)
	var g: Array = data.get("ground", [190, 186, 0, 0])
	var gm: Dictionary = data.get("ground_mask", {})
	if gm.is_empty():
		_block(Vector3(float(g[0]), 1.0, float(g[1])), Vector3(float(g[2]), -0.5, float(g[3])), "earth", 0.0, 0.0, true)
	else:
		_ground(Vector2(float(g[0]), float(g[1])), Vector2(float(g[2]), float(g[3])), gm)
	var groups := {}
	for it: Variant in data.get("items", []):
		var d: Dictionary = it
		var p: Array = d.get("p", [0, 0, 0])
		var pos := Vector3(float(p[0]), float(p[1]), float(p[2]))
		if d.has("box"):
			var b: Array = d.box
			_block(Vector3(float(b[0]), float(b[1]), float(b[2])), pos, str(d.get("mat", "stone")), float(d.get("r", 0.0)),
				float(d.get("rx", 0.0)), bool(d.get("c", true)))
			continue
		var k := str(d.get("m", ""))
		if not groups.has(k):
			groups[k] = []
		var basis := Basis(Vector3.UP, deg_to_rad(float(d.get("r", 0.0)))).scaled(Vector3.ONE * float(d.get("s", 1.0)))
		(groups[k] as Array).append([Transform3D(basis, pos), bool(d.get("c", false)), d.get("col", [])])
	for k: String in groups:
		_place(k, groups[k])
		_lights(k, groups[k])
	_fix_textures()


## Земля: плоскость с шейдером (глина, кладка дорог и тропы по маске — shaders/ground.gdshader) и коробка-коллизия.
func _ground(size: Vector2, center: Vector2, gm: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = size
	pm.subdivide_width = 8
	pm.subdivide_depth = 8
	var sh: Shader = mod.shader("shaders/ground.gdshader")
	if sh != null:
		var m := ShaderMaterial.new()
		m.shader = sh
		const T := "models/gharn/tex/"
		for u: Array in [["g_col", "ground.jpg"], ["g_nrm", "ground_n.jpg"], ["g_rgh", "ground_r.jpg"],
				["c_col", "cobble.jpg"], ["c_nrm", "cobble_n.jpg"], ["c_rgh", "cobble_r.jpg"], ["c_hgt", "cobble_h.jpg"]]:
			m.set_shader_parameter(u[0], _tex(T + str(u[1]), str(u[0]).ends_with("nrm")))
		m.set_shader_parameter("mask", mod.texture(str(gm.get("tex", ""))))
		var r: Array = gm.get("rect", [0, 0, 1, 1])
		m.set_shader_parameter("mask_rect", Vector4(float(r[0]), float(r[1]), float(r[2]), float(r[3])))
		pm.material = m
	mi.mesh = pm
	mi.position = Vector3(center.x, 0.0, center.y)
	root.add_child(mi)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size.x, 1.0, size.y)
	cs.shape = bs
	body.add_child(cs)
	body.position = Vector3(center.x, -0.5, center.y)
	root.add_child(body)
	rects.append([center, size, Color(0.11, 0.16, 0.35)])


## Картинка мода с мипмапами (без них плитка вдали рябит при движении камеры).
func _tex(path: String, normal := false) -> Texture2D:
	var t := mod.texture(path)
	if t == null:
		return null
	var img := t.get_image()
	if img == null:
		return t
	if img.is_compressed():
		return t
	if not img.has_mipmaps():
		img.generate_mipmaps(normal)
	return ImageTexture.create_from_image(img)


## Текстуры моделей: glb игра грузит без импорта — у картинок нет мипмапов (рябь вдали, «шум» на камнях).
## Каждой — мипмапы и, если движок умеет на лету, сжатие в видеопамяти; картинки — параллельно на всех ядрах.
const TEX_SLOTS := [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS,
	BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_EMISSION, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]
var _mats: Array = []              # материалы моделей города (BaseMaterial3D), собирает _place
var _imgs: Array = []


func _fix_textures() -> void:
	var uses := {}                     # текстура → [[материал, слот], …]
	for mat: BaseMaterial3D in _mats:
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		for slot: int in TEX_SLOTS:
			var t := mat.get_texture(slot)
			if t == null:
				continue
			if not uses.has(t):
				uses[t] = []
			(uses[t] as Array).append([mat, slot])
	var keys: Array = uses.keys()
	_imgs.clear()
	for t: Texture2D in keys:
		var img := t.get_image()
		var normal := false
		for u: Array in uses[t]:
			normal = normal or int(u[1]) == BaseMaterial3D.TEXTURE_NORMAL
		_imgs.append([img, normal])
	var task := WorkerThreadPool.add_group_task(_prep_image, _imgs.size(), -1, true, "pax_rpg mipmaps")
	WorkerThreadPool.wait_for_group_task_completion(task)
	for i: int in keys.size():
		var img: Image = _imgs[i][0]
		if img == null or img.is_empty():
			continue
		var nt := ImageTexture.create_from_image(img)
		for u: Array in uses[keys[i]]:
			(u[0] as BaseMaterial3D).set_texture(int(u[1]), nt)
	_imgs.clear()
	_mats.clear()


func _prep_image(i: int) -> void:
	var img: Image = _imgs[i][0]
	if img == null or img.is_empty() or img.is_compressed():
		return
	if not img.has_mipmaps():
		img.generate_mipmaps(bool(_imgs[i][1]))
	img.compress(Image.COMPRESS_S3TC, Image.COMPRESS_SOURCE_NORMAL if bool(_imgs[i][1]) else Image.COMPRESS_SOURCE_GENERIC)


## Тёплый свет у фонарей (без теней — их десятки).
func _lights(path: String, list: Array) -> void:
	var off := Vector3.ZERO
	var col := Color(1.0, 0.62, 0.35)
	if path.ends_with("lantern_post.glb"):
		off = Vector3(0.82, 2.35, 0)
	elif path.ends_with("stone_lantern.glb"):
		off = Vector3(0, 1.35, 0)
	elif path.ends_with("mana_crystal.glb"):
		off = Vector3(0, 0.6, 0)
		col = Color(1.0, 0.4, 0.8)
	elif path.ends_with("cauldron.glb"):
		off = Vector3(0, 0.3, 0)
	else:
		return
	for e: Array in list:
		var t: Transform3D = e[0]
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = 1.6
		l.omni_range = 7.0
		l.position = t * off
		root.add_child(l)


## Модель: её сетки (со своими сдвигами внутри модели) → MultiMesh на все места; коллизии — коробки.
func _place(path: String, list: Array) -> void:
	var src := mod.model(path)
	if src == null:
		mod.log_warning("Pax RPG city: no model " + path)
		return
	var parts: Array = []
	var aabb := AABB()
	var first := true
	_collect(src, Transform3D.IDENTITY, parts)
	for pr: Array in parts:
		var a: AABB = (pr[1] as Transform3D) * (pr[0] as Mesh).get_aabb()
		aabb = a if first else aabb.merge(a)
		first = false
	for pr: Array in parts:
		var mesh: Mesh = pr[0]
		for si: int in mesh.get_surface_count():
			var sm := mesh.surface_get_material(si)
			if sm is BaseMaterial3D and not _mats.has(sm):
				_mats.append(sm)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pr[0]
		mm.instance_count = list.size()
		for i: int in list.size():
			mm.set_instance_transform(i, (list[i][0] as Transform3D) * (pr[1] as Transform3D))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		root.add_child(mi)
	for e: Array in list:
		count += 1
		var t: Transform3D = e[0]
		var cl: Array = e[2]
		if bool(e[1]) and not first and cl.size() > 0 and cl[0] is Array:
			_boxes(t, cl)                                 # несколько коробок (ворота: две башни, проход свободен)
			continue
		if bool(e[1]) and not first:
			var body := StaticBody3D.new()
			var sh := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			var col: Array = e[2]
			var sc := t.basis.get_scale().x
			if col.size() == 3:                          # своя коробка (ствол дерева): от земли вверх
				bs.size = Vector3(float(col[0]), float(col[1]), float(col[2])) * sc
				sh.position = Vector3(0, bs.size.y / 2, 0)
			else:
				bs.size = aabb.size * sc * 0.92
				sh.position = aabb.get_center() * sc
			sh.shape = bs
			body.add_child(sh)
			body.transform = Transform3D(t.basis.orthonormalized(), t.origin)
			root.add_child(body)
			var sz := Vector2(bs.size.x, bs.size.z)
			rects.append([Vector2(t.origin.x, t.origin.z), sz, Color(0.22, 0.27, 0.5)])
	src.free()


## Коробки коллизии [sx, sy, sz, ox, oy, oz] в осях модели (с её масштабом).
func _boxes(t: Transform3D, list: Array) -> void:
	var body := StaticBody3D.new()
	var sc := t.basis.get_scale().x
	for c: Variant in list:
		var b: Array = c
		var sh := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(float(b[0]), float(b[1]), float(b[2])) * sc
		sh.shape = bs
		sh.position = Vector3(float(b[3]), float(b[4]), float(b[5])) * sc
		body.add_child(sh)
		var g := t.origin + t.basis.orthonormalized() * sh.position
		rects.append([Vector2(g.x, g.z), Vector2(bs.size.x, bs.size.z), Color(0.22, 0.27, 0.5)])
	body.transform = Transform3D(t.basis.orthonormalized(), t.origin)
	root.add_child(body)


func _collect(n: Node, xf: Transform3D, out: Array) -> void:
	var here := xf
	if n is Node3D:
		here = xf * (n as Node3D).transform
	if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
		out.append([(n as MeshInstance3D).mesh, here])
	for c in n.get_children():
		_collect(c, here, out)


func _block(size: Vector3, pos: Vector3, mat: String, ry: float, rx: float, collide: bool) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(ry)) * Basis(Vector3.RIGHT, deg_to_rad(rx))
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var sm := StandardMaterial3D.new()
	sm.albedo_color = MATS.get(mat, MATS.stone)
	sm.roughness = 0.95
	if mat == "earth":
		sm.albedo_color = Color.WHITE
		sm.albedo_texture = mod.texture("models/gharn/tex/ground.jpg")
		sm.uv1_triplanar = true
		sm.uv1_world_triplanar = true
		sm.uv1_scale = Vector3.ONE * 0.25
	bm.material = sm
	mi.mesh = bm
	mi.transform = Transform3D(basis, pos)
	root.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var sh := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		sh.shape = bs
		body.add_child(sh)
		body.transform = Transform3D(basis, pos)
		root.add_child(body)
	if size.x < 150.0:
		rects.append([Vector2(pos.x, pos.z), Vector2(size.x, size.z), Color(0.2, 0.27, 0.55)])
	else:
		rects.append([Vector2(pos.x, pos.z), Vector2(size.x, size.z), Color(0.11, 0.16, 0.35)])
