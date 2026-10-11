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
		var basis := Basis(Vector3.UP, deg_to_rad(float(d.get("r", 0.0)))) * Basis.from_scale(Vector3.ONE * float(d.get("s", 1.0)))
		if d.has("sv"):                                   # своя форма (стекло окна — по размеру окна)
			var sv: Array = d.sv
			basis = basis * Basis.from_scale(Vector3(float(sv[0]), float(sv[1]), float(sv[2])))
		(groups[k] as Array).append([Transform3D(basis, pos), bool(d.get("c", false)), d.get("col", [])])
	for k: String in groups:
		if k.ends_with("banner_clan.glb"):
			_flags(groups[k])                              # знамя Гхарна — своё полотнище на ветру
			continue
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
## Каждой — мипмапы, по одной (вместе все картинки не помещаются в память). Сжатия на лету в игре нет —
## размер картинок задан заранее по габариту модели (pax_rpg/dev/gharn/tex_budget.py).
const TEX_SLOTS := [BaseMaterial3D.TEXTURE_ALBEDO, BaseMaterial3D.TEXTURE_NORMAL, BaseMaterial3D.TEXTURE_ROUGHNESS,
	BaseMaterial3D.TEXTURE_METALLIC, BaseMaterial3D.TEXTURE_EMISSION, BaseMaterial3D.TEXTURE_AMBIENT_OCCLUSION]
var _mats: Array = []              # материалы моделей города (BaseMaterial3D), собирает _place


func _fix_textures() -> void:
	var done := {}                     # исходная текстура → с мипмапами
	for mat: BaseMaterial3D in _mats:
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		for slot: int in TEX_SLOTS:
			var t := mat.get_texture(slot)
			if t == null:
				continue
			if not done.has(t):
				var img := t.get_image()
				if img == null or img.is_empty() or img.is_compressed() or img.has_mipmaps():
					done[t] = t
				else:
					img.generate_mipmaps(slot == BaseMaterial3D.TEXTURE_NORMAL)
					done[t] = ImageTexture.create_from_image(img)
			mat.set_texture(slot, done[t])
	_mats.clear()


## Знамёна Гхарна: древко с перекладиной и полотнище (textures/gharn_flag.png — герб: огненный зверь),
## полотнище колышется (shaders/flag.gdshader). Каждое — свой узел: фаза ветра от места, флаги не машут в такт.
func _flags(list: Array) -> void:
	var tex := _tex("textures/gharn_flag.png")
	var sh: Shader = mod.shader("shaders/flag.gdshader")
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.16, 0.1, 0.08)
	wood.roughness = 0.8
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.8, 0.6, 0.25)
	gold.metallic = 1.0
	gold.roughness = 0.35
	var pole := CylinderMesh.new()
	pole.top_radius = 0.05
	pole.bottom_radius = 0.07
	pole.height = 5.4
	pole.material = wood
	var bar := BoxMesh.new()
	bar.size = Vector3(1.45, 0.08, 0.08)
	bar.material = wood
	var tip := SphereMesh.new()
	tip.radius = 0.09
	tip.height = 0.18
	tip.material = gold
	var cloth := QuadMesh.new()
	cloth.size = Vector2(1.25, 2.0)
	cloth.subdivide_width = 6
	cloth.subdivide_depth = 14
	var mat: Material = null
	if sh != null:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("tex", tex)
		mat = m
	for e: Array in list:
		var t: Transform3D = e[0]
		var n := Node3D.new()
		n.transform = t
		root.add_child(n)
		for part: Array in [[pole, Vector3(0, 2.7, 0)], [bar, Vector3(0, 5.05, 0)], [tip, Vector3(0, 5.45, 0)],
				[tip, Vector3(0.74, 5.05, 0)], [tip, Vector3(-0.74, 5.05, 0)]]:
			var mi := MeshInstance3D.new()
			mi.mesh = part[0]
			mi.position = part[1]
			n.add_child(mi)
		var c := MeshInstance3D.new()
		c.mesh = cloth
		c.material_override = mat
		c.position = Vector3(0, 5.0 - 1.0, 0.07)
		n.add_child(c)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(0.25, 5.4, 0.25)
		cs.shape = bs
		cs.position = Vector3(0, 2.7, 0)
		body.add_child(cs)
		n.add_child(body)
		count += 1


## Стекло окон: тёмное, почти зеркальное (небо, солнце и фонари в нём — через отражения окружения и SSR),
## изнутри — слабый тёплый свет очага.
func _glass(m: BaseMaterial3D) -> void:
	m.albedo_color = Color(0.1, 0.13, 0.18)
	m.metallic = 0.9
	m.metallic_specular = 0.9
	m.roughness = 0.05
	m.emission_enabled = true
	m.emission = Color(1.0, 0.62, 0.3)
	m.emission_energy_multiplier = 0.35
	m.cull_mode = BaseMaterial3D.CULL_DISABLED


## Тёплый свет у фонарей (без теней — их десятки).
func _lights(path: String, list: Array) -> void:
	var off := Vector3.ZERO
	var col := Color(1.0, 0.62, 0.35)
	if path.ends_with("lantern_post.glb"):
		off = Vector3(0.82, 2.35, 0)
	elif path.ends_with("firepit.glb"):
		off = Vector3(0, 0.6, 0)
		col = Color(1.0, 0.5, 0.2)
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
			if sm is BaseMaterial3D and sm.resource_name.begins_with("glass"):
				_glass(sm)
			elif sm is BaseMaterial3D and not _mats.has(sm):
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
