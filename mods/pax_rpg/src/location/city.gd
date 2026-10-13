extends RefCounted
const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")
const Landscape := preload("res://mods/pax_rpg/src/location/landscape.gd")
const Vfx := preload("res://mods/pax_rpg/src/location/vfx.gd")
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
var vfx: Vfx
var leaves: Array = []
var lights: Array = []         # [OmniLight3D, энергия ночью] — ими управляет daynight.gd
var glass: Array = []
var paper_mats: Array = []     # бумажные фонари рынка — своё, мягкое свечение          # материалы окон (ночью светятся)         # CPUParticles3D листьев — ими управляет ветер (wind.gd)


func build(m: PaxMod, parent: Node, data: Dictionary) -> void:
	mod = m
	vfx = Vfx.new(m)
	root = Node3D.new()
	root.name = "City"
	parent.add_child(root)
	var g: Array = data.get("ground", [190, 186, 0, 0])
	var gm: Dictionary = data.get("ground_mask", {})
	if gm.is_empty():
		_block(Vector3(float(g[0]), 1.0, float(g[1])), Vector3(float(g[2]), -0.5, float(g[3])), "earth", 0.0, 0.0, true)
	else:
		_ground(Vector2(float(g[0]), float(g[1])), Vector2(float(g[2]), float(g[3])), gm)
	if bool(data.get("landscape", true)):              # степь, горы и кочевья за стеной
		var land := Landscape.new()
		var gw := Vector2(float(g[0]), float(g[1]))
		land.build(mod, root, Rect2(Vector2(float(g[2]), float(g[3])) - gw * 0.5, gw))
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
		if d.has("sign"):
			_sign(d.sign, pos, float(d.get("r", 0.0)))
			continue
		if d.has("lanterns"):
			_lantern_line(d.lanterns, int(d.get("seed", 0)))
			continue
		if d.has("merchant"):
			_merchant(pos, float(d.get("r", 0.0)), int(d.get("seed", 0)))
			continue
		if d.has("brazier"):                              # жаровня: каменная тумба, чаша, огонь
			_block(Vector3(0.7, 0.9, 0.7), pos + Vector3(0, 0.45, 0), "stone_dark", 0.0, 0.0, true)
			_block(Vector3(0.95, 0.18, 0.95), pos + Vector3(0, 0.99, 0), "stone_cut", 45.0, 0.0, false)
			lights.append([vfx.fire(root, pos + Vector3(0, 1.08, 0), 0.75), 2.6])
			continue
		if d.has("laundry"):
			_laundry(d.laundry, int(d.get("seed", 0)))
			continue
		var k := str(d.get("m", ""))
		if d.has("anim"):                                 # живое существо: своя модель с анимациями
			_animal(k, pos, float(d.get("r", 0.0)), float(d.get("s", 1.0)), d.get("anim", []), d.get("col", []))
			continue
		if not groups.has(k):
			groups[k] = []
		var basis := Basis(Vector3.UP, deg_to_rad(float(d.get("r", 0.0)))) * Basis.from_scale(Vector3.ONE * float(d.get("s", 1.0)))
		if d.has("sv"):                                   # своя форма (стекло окна — по размеру окна)
			var sv: Array = d.sv
			basis = basis * Basis.from_scale(Vector3(float(sv[0]), float(sv[1]), float(sv[2])))
		(groups[k] as Array).append([Transform3D(basis, pos), bool(d.get("c", false)), d.get("col", [])])
	for k: String in groups:
		_smoke_for(k, groups[k])
		if k.ends_with("fountain_dragon.glb"):
			for e: Array in groups[k]:
				_fountain_water(e[0])
		if k.ends_with("flame_tree.glb"):
			_leaves(groups[k])
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


const TEX_MAX := 2048


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
				if img == null or img.is_empty() or img.is_compressed():
					done[t] = t
				else:
					# несжатая 4K с мипмапами — 85 МБ видеопамяти; город из десятков таких съедал 8 ГБ и
					# кадр упирался в память. Дальше TEX_MAX пикселей на глаз не видно с высоты камеры.
					if maxi(img.get_width(), img.get_height()) > TEX_MAX:
						if img.has_mipmaps():
							img.clear_mipmaps()
						var k := float(TEX_MAX) / maxi(img.get_width(), img.get_height())
						img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
					elif img.has_mipmaps():
						done[t] = t
						mat.set_texture(slot, t)
						continue
					img.generate_mipmaps(slot == BaseMaterial3D.TEXTURE_NORMAL)
					if t is ImageTexture:                      # на месте: исходник из кэша моделей не висит в памяти вторым
						(t as ImageTexture).set_image(img)
						done[t] = t
					else:
						done[t] = ImageTexture.create_from_image(img)
			mat.set_texture(slot, done[t])
	_mats.clear()


## Дым и пар: из дымоходов юрт (не всех), над кострами — гуще, над котлами — белый пар. Мягкие круглые клубы
## (флипбук с объёмом — vfx.gd) растут, светлеют и тают, их сносит вдоль ветра. Через smoke_drift их подталкивает ветер (wind.gd).
var smoke: Array = []


func _smoke_for(path: String, list: Array) -> void:
	var spec := {}
	if path.ends_with("yurt_small.glb"):
		spec = {"y": 3.0, "col": Color(0.5, 0.48, 0.5, 0.32), "amount": 16, "size": 0.55, "share": 0.65}
	elif path.ends_with("yurt_large.glb"):
		spec = {"y": 4.25, "col": Color(0.5, 0.48, 0.5, 0.32), "amount": 18, "size": 0.65, "share": 0.7}
	elif path.ends_with("firepit.glb"):
		spec = {"y": 0.7, "col": Color(0.38, 0.36, 0.38, 0.38), "amount": 20, "size": 0.5, "share": 1.0}
	elif path.ends_with("cauldron.glb"):
		spec = {"y": 1.3, "col": Color(0.95, 0.95, 1.0, 0.25), "amount": 14, "size": 0.35, "share": 1.0}
	else:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = path.hash()
	var col: Color = spec.col
	for e: Array in list:
		if rng.randf() > float(spec.share):
			continue
		var t: Transform3D = e[0]
		var sc := t.basis.get_scale().x
		var p := vfx.smoke(root, t.origin + Vector3(0, float(spec.y) * sc, 0), float(spec.size) * 1.4, col,
			maxi(6, int(spec.amount) / 2))
		smoke.append(p)


## Живая вода фонтана: рябь в чаше (shaders/water.gdshader), струя из пасти дракона веером вниз, брызги и
## пар над водой. Размеры — по модели (чаша r ≈ 2.15, вода на 1.45, верх дракона 4.0 — в единицах модели).
func _fountain_water(t: Transform3D) -> void:
	var sc := t.basis.get_scale().x
	var wsh: Shader = mod.shader("shaders/water.gdshader")
	var disc := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4.3, 4.3) * sc
	disc.mesh = pm
	if wsh != null:
		var wm := ShaderMaterial.new()
		wm.shader = wsh
		disc.material_override = wm
	disc.position = t.origin + Vector3(0, 1.45 * sc, 0)
	root.add_child(disc)
	# капли — вытянутые по скорости штрихи (как струя на свету), а не шарики; блеск — HDR, ловит bloom
	var dm := StandardMaterial3D.new()
	dm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dm.albedo_texture = mod.texture("textures/vfx/glow.png")
	dm.albedo_color = Color(1.3, 1.6, 1.9, 0.55)
	dm.vertex_color_use_as_albedo = true
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dm.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	dm.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	dm.billboard_keep_scale = true
	var drop := QuadMesh.new()
	drop.size = Vector2(0.05, 0.32)
	drop.material = dm
	var jet := CPUParticles3D.new()                       # струи веером из пасти вниз в чашу
	jet.mesh = drop
	jet.particle_flag_align_y = true                      # штрих — вдоль полёта
	jet.amount = 320
	jet.lifetime = 1.3
	jet.local_coords = false
	jet.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	jet.emission_sphere_radius = 0.12 * sc
	jet.direction = Vector3.UP
	jet.spread = 70.0
	jet.initial_velocity_min = 1.6 * sc
	jet.initial_velocity_max = 2.4 * sc
	jet.gravity = Vector3(0, -9.8, 0)
	jet.scale_amount_min = 0.7
	jet.scale_amount_max = 1.4
	var jr := Gradient.new()
	jr.set_color(0, Color(1, 1, 1, 0.9))
	jr.set_color(1, Color(1, 1, 1, 0.4))
	jet.color_ramp = jr
	jet.position = t.origin + Vector3(0, 4.0 * sc, 0)
	root.add_child(jet)
	var splash := CPUParticles3D.new()                    # брызги, отскочившие от воды — короткие штрихи
	splash.mesh = drop
	splash.particle_flag_align_y = true
	splash.amount = 110
	splash.lifetime = 0.45
	splash.local_coords = false
	splash.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING
	splash.emission_ring_axis = Vector3.UP
	splash.emission_ring_radius = 1.5 * sc
	splash.emission_ring_inner_radius = 0.6 * sc
	splash.emission_ring_height = 0.05
	splash.direction = Vector3.UP
	splash.spread = 40.0
	splash.initial_velocity_min = 0.8
	splash.initial_velocity_max = 1.8
	splash.gravity = Vector3(0, -9.8, 0)
	splash.scale_amount_min = 0.25
	splash.scale_amount_max = 0.55
	splash.position = t.origin + Vector3(0, 1.48 * sc, 0)
	root.add_child(splash)
	var mist := vfx.smoke(root, t.origin + Vector3(0, 1.7 * sc, 0), 1.1 * sc, Color(0.85, 0.93, 1.0, 0.16), 10, 0.25)
	mist.emission_shape = CPUParticles3D.EMISSION_SHAPE_RING     # водяная пыль над чашей
	mist.emission_ring_axis = Vector3.UP
	mist.emission_ring_radius = 1.4 * sc
	mist.emission_ring_inner_radius = 0.5 * sc
	mist.emission_ring_height = 0.1
	smoke.append(mist)


## Вывеска лавки: доска тёмного лака в золотой рамке на двух стойках, крупный иероглиф и подпись — с обеих
## сторон. sign: [иероглиф, подпись].
var _sign_font: SystemFont


func _sign(sg: Array, pos: Vector3, ry: float) -> void:
	if _sign_font == null:
		_sign_font = SystemFont.new()
		_sign_font.font_names = PackedStringArray(["Yu Mincho", "MS Mincho", "Noto Serif CJK JP", "Noto Serif JP",
			"SimSun", "Georgia"])
		_sign_font.font_weight = 700
	var n := Node3D.new()
	n.position = pos
	n.rotation.y = deg_to_rad(ry)
	root.add_child(n)
	var lac := StandardMaterial3D.new()
	lac.albedo_color = Color(0.12, 0.05, 0.06)
	lac.roughness = 0.35
	var gold := StandardMaterial3D.new()
	gold.albedo_color = Color(0.82, 0.62, 0.28)
	gold.metallic = 1.0
	gold.roughness = 0.35
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.2, 0.13, 0.09)
	for part: Array in [[Vector3(0.08, 2.6, 0.08), Vector3(-0.42, 1.3, 0), wood], [Vector3(0.08, 2.6, 0.08), Vector3(0.42, 1.3, 0), wood],
			[Vector3(0.78, 1.62, 0.05), Vector3(0, 1.62, 0), gold], [Vector3(0.7, 1.54, 0.08), Vector3(0, 1.62, 0), lac],
			[Vector3(1.0, 0.07, 0.1), Vector3(0, 2.55, 0), wood]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = part[0]
		bm.material = part[2]
		mi.mesh = bm
		mi.position = part[1]
		n.add_child(mi)
	for side: float in [1.0, -1.0]:
		var k := Label3D.new()
		k.text = str(sg[0])
		k.font = _sign_font
		k.font_size = 220
		k.pixel_size = 0.0028
		k.modulate = Color(1.0, 0.82, 0.45)
		k.outline_size = 0
		k.position = Vector3(0, 1.85, 0.045 * side)
		k.rotation.y = 0.0 if side > 0 else PI
		n.add_child(k)
		var t := Label3D.new()
		t.text = str(sg[1])
		t.font_size = 40
		t.pixel_size = 0.0025
		t.modulate = Color(1.0, 0.9, 0.85)
		t.outline_size = 0
		t.position = Vector3(0, 1.08, 0.045 * side)
		t.rotation.y = 0.0 if side > 0 else PI
		n.add_child(t)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.0, 2.6, 0.2)
	cs.shape = bs
	cs.position = Vector3(0, 1.3, 0)
	body.add_child(cs)
	n.add_child(body)
	count += 1


## Бельё и шкуры между столбами у юрт: верёвка, полотнища колышутся (shaders/flag.gdshader, сплошной цвет).
## laundry: [x1, z1, x2, z2].
func _laundry(l: Array, seed_v: int) -> void:
	var a := Vector3(float(l[0]), 0, float(l[1]))
	var b := Vector3(float(l[2]), 0, float(l[3]))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.25, 0.17, 0.11)
	var top := 2.3
	for p: Vector3 in [a, b]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.04
		cm.bottom_radius = 0.055
		cm.height = top + 0.15
		cm.material = wood
		mi.mesh = cm
		mi.position = p + Vector3(0, (top + 0.15) * 0.5, 0)
		root.add_child(mi)
	var dir := (b - a)
	var length := dir.length()
	var rope := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.012
	rm.bottom_radius = 0.012
	rm.height = length
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.55, 0.45, 0.32)
	rm.material = rmat
	rope.mesh = rm
	var basis := Basis.looking_at(dir.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5)
	rope.transform = Transform3D(basis, a.lerp(b, 0.5) + Vector3(0, top, 0))
	root.add_child(rope)
	var colors := [Color(0.72, 0.12, 0.14), Color(0.92, 0.86, 0.72), Color(0.18, 0.22, 0.45), Color(0.82, 0.6, 0.25),
		Color(0.45, 0.3, 0.2), Color(0.55, 0.38, 0.26)]
	var sh: Shader = mod.shader("shaders/flag.gdshader")
	var x := 0.35
	var yaw := atan2(dir.x, dir.z) - PI * 0.5
	while x < length - 0.4:
		var w := rng.randf_range(0.45, 0.9)
		var hide := rng.randf() < 0.3
		var h := rng.randf_range(0.9, 1.3) if hide else rng.randf_range(0.55, 1.0)
		var c: Color = colors[4 + rng.randi() % 2] if hide else colors[rng.randi() % 4]
		var q := QuadMesh.new()
		q.size = Vector2(w, h)
		q.subdivide_width = 3
		q.subdivide_depth = 5
		var mi := MeshInstance3D.new()
		mi.mesh = q
		if sh != null:
			var g := Gradient.new()
			g.set_color(0, c)
			g.set_color(1, c.darkened(0.15))
			var gt := GradientTexture2D.new()
			gt.gradient = g
			gt.width = 8
			gt.height = 8
			var m := ShaderMaterial.new()
			m.shader = sh
			m.set_shader_parameter("tex", gt)
			m.set_shader_parameter("amp", 0.05)
			mi.material_override = m
		mi.transform = Transform3D(Basis(Vector3.UP, yaw), a + dir.normalized() * (x + w * 0.5) + Vector3(0, top - h * 0.5 - 0.02, 0))
		root.add_child(mi)
		x += w + rng.randf_range(0.08, 0.3)


## Гирлянда больших бумажных фонарей (как на концепте рынка): верёвка между столбами, оранжевые шары с тёмными
## ободами качаются; посередине — тёплый свет (ночью ярче, daynight.gd). lanterns: [x1, z1, x2, z2, высота].
var _lantern_mesh: SphereMesh
var _rim_mesh: CylinderMesh


## Текстура бумажного фонаря-тётин: оранжевая бумага с волокнами, бамбуковые рёбра поперёк, тёмные
## полосы у горловин, с двух сторон — чёрный герб (круг с тремя каплями-томоэ).
func _lantern_tex() -> ImageTexture:
	var w := 256
	var h := 128
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var n := FastNoiseLite.new()
	n.frequency = 0.08
	for y: int in h:
		var v := float(y) / h
		var rib := pow(absf(sin(v * PI * 11.0)), 18.0)
		var band := 1.0 - smoothstep(0.06, 0.12, v) * smoothstep(0.94, 0.88, v)
		for x: int in w:
			var f := n.get_noise_2d(x * 3.0, y * 0.6) * 0.06
			var c := Color(0.97 + f, 0.5 + f, 0.16 + f * 0.5)
			c = c.lerp(Color(0.55, 0.16, 0.05), rib * 0.6)
			c = c.lerp(Color(0.1, 0.05, 0.04), band)
			for cx: float in [0.25, 0.75]:              # герб с двух сторон
				var d := Vector2((float(x) / w - cx) * 2.0, v - 0.5)
				var r := d.length()
				var ring := smoothstep(0.012, 0.0, absf(r - 0.17))
				var ang := atan2(d.y, d.x)
				var tomoe := smoothstep(0.02, 0.0, absf(r - 0.085 - 0.04 * sin(ang * 3.0))) * float(r < 0.15)
				c = c.lerp(Color(0.08, 0.03, 0.02), maxf(ring, tomoe) * 0.9)
			img.set_pixel(x, y, c)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _lantern_line(l: Array, seed_v: int) -> void:
	var a := Vector3(float(l[0]), 0, float(l[1]))
	var b := Vector3(float(l[2]), 0, float(l[3]))
	var hgt := float(l[4]) if l.size() > 4 else 4.2
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	if _lantern_mesh == null:
		var paper := StandardMaterial3D.new()
		var ptex := _lantern_tex()
		paper.albedo_texture = ptex
		paper.emission_enabled = true
		paper.emission = Color(1.0, 0.42, 0.12)
		paper.emission_texture = ptex
		paper.emission_energy_multiplier = 0.4
		paper_mats.append(paper)                          # мягко разгорается к ночи (daynight.gd)
		paper.roughness = 0.8
		_lantern_mesh = SphereMesh.new()
		_lantern_mesh.radius = 0.38
		_lantern_mesh.height = 0.86
		_lantern_mesh.material = paper
		var dark := StandardMaterial3D.new()
		dark.albedo_color = Color(0.12, 0.06, 0.04)
		_rim_mesh = CylinderMesh.new()
		_rim_mesh.top_radius = 0.2
		_rim_mesh.bottom_radius = 0.2
		_rim_mesh.height = 0.08
		_rim_mesh.material = dark
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color(0.24, 0.16, 0.1)
	for p: Vector3 in [a, b]:
		var mi := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.07
		cm.bottom_radius = 0.09
		cm.height = hgt + 0.3
		cm.material = wood
		mi.mesh = cm
		mi.position = p + Vector3(0, (hgt + 0.3) * 0.5, 0)
		root.add_child(mi)
	var dir := b - a
	var rope := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.015
	rm.bottom_radius = 0.015
	rm.height = dir.length()
	rm.material = wood
	rope.mesh = rm
	rope.transform = Transform3D(Basis.looking_at(dir.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, PI * 0.5),
		a.lerp(b, 0.5) + Vector3(0, hgt, 0))
	root.add_child(rope)
	var n := maxi(2, int(dir.length() / 2.6))
	for i: int in n:
		var f := (i + 0.5) / n
		var sag := sin(f * PI) * 0.35
		var holder := Node3D.new()
		holder.position = a.lerp(b, f) + Vector3(0, hgt - sag, 0)
		root.add_child(holder)
		var lan := MeshInstance3D.new()
		lan.mesh = _lantern_mesh
		var sc := rng.randf_range(0.75, 1.25)
		lan.scale = Vector3.ONE * sc
		lan.position = Vector3(0, -0.55 * sc, 0)
		holder.add_child(lan)
		for y: float in [-0.12, -0.98]:
			var rim := MeshInstance3D.new()
			rim.mesh = _rim_mesh
			rim.position = Vector3(0, y * sc, 0)
			holder.add_child(rim)
		var tw := holder.create_tween()                   # лёгкое покачивание
		if tw != null:
			tw.set_loops()
			var amp := rng.randf_range(0.05, 0.12)
			var dur := rng.randf_range(1.4, 2.2)
			tw.tween_property(holder, "rotation:z", amp, dur).set_trans(Tween.TRANS_SINE)
			tw.tween_property(holder, "rotation:z", -amp, dur).set_trans(Tween.TRANS_SINE)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.55, 0.25)
	light.light_energy = 0.8
	light.omni_range = 7.0
	light.distance_fade_enabled = true
	light.distance_fade_begin = 45.0
	light.distance_fade_length = 10.0
	light.position = a.lerp(b, 0.5) + Vector3(0, hgt - 0.8, 0)
	root.add_child(light)
	lights.append([light, 2.2])
	count += 1


## Торговец за прилавком: гоблин с анимацией покоя (модель и клип — как у мирных жителей), смотрит на покупателей.
func _merchant(pos: Vector3, ry: float, seed_v: int) -> void:
	var m := Assets.model(mod, "models/goblin/goblin_rigged.glb")
	if m == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	m.position = pos
	m.rotation.y = deg_to_rad(ry)
	m.scale = Vector3.ONE * rng.randf_range(0.9, 1.1)
	root.add_child(m)
	Assets.track("models/goblin/goblin_rigged.glb", m)
	var ap := _find_player(m)
	var src := Assets.model(mod, "models/goblin/idle.glb")
	if ap != null and src != null:
		var sa := _find_player(src)
		if sa != null and sa.get_animation_list().size() > 0:
			var an: Animation = sa.get_animation(sa.get_animation_list()[0]).duplicate()
			an.loop_mode = Animation.LOOP_LINEAR
			var lib := AnimationLibrary.new()
			lib.add_animation("idle", an)
			if not ap.has_animation_library("m"):
				ap.add_animation_library("m", lib)
			ap.play("m/idle")
			ap.seek(rng.randf() * 2.0, true)
			ap.speed_scale = rng.randf_range(0.85, 1.15)
	if src != null:
		src.free()
	count += 1


## Листопад: с кроны каждого дерева медленно падают алые листья, кружатся, ветер сносит их (wind.gd: гуще в порыв).
func _leaves(list: Array) -> void:
	var leaf := QuadMesh.new()
	leaf.size = Vector2(0.11, 0.07)
	var m := StandardMaterial3D.new()                 # освещённые — ночью и в тени темнеют вместе с городом
	m.roughness = 1.0
	m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	leaf.material = m
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.55, 0.22, 0.2))         # приглушённые: пыльно-красный, ржавый, бурый
	ramp.set_color(1, Color(0.6, 0.42, 0.28))
	ramp.add_point(0.5, Color(0.48, 0.18, 0.16))
	for e: Array in list:
		var t: Transform3D = e[0]
		var sc := t.basis.get_scale().x
		var p := CPUParticles3D.new()
		p.mesh = leaf
		p.amount = 7
		p.lifetime = 7.0
		p.visibility_range_end = 45.0
		p.preprocess = 7.0
		p.local_coords = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(3.2, 0.8, 3.2) * sc
		p.direction = Vector3(0, -1, 0)
		p.spread = 30.0
		p.initial_velocity_min = 0.1
		p.initial_velocity_max = 0.4
		p.gravity = Vector3(0.3, -0.55, 0.1)
		p.damping_min = 0.2
		p.damping_max = 0.6
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.angular_velocity_min = -220.0
		p.angular_velocity_max = 220.0
		p.scale_amount_min = 0.8
		p.scale_amount_max = 1.5
		p.color_initial_ramp = ramp
		p.position = t.origin + Vector3(0, 5.6 * sc, 0)
		root.add_child(p)
		leaves.append(p)


## Животное (буйвол): своя копия модели, клипы anim по очереди со случайной паузой — пасётся, оглядывается.
func _animal(path: String, pos: Vector3, ry: float, sc: float, clips: Array, col: Array) -> void:
	var m := Assets.model(mod, path)
	if m == null:
		return
	m.position = pos
	m.rotation.y = deg_to_rad(ry)
	m.scale = Vector3.ONE * sc
	root.add_child(m)
	Assets.track(path, m)
	count += 1
	var ap := _find_player(m)
	if ap != null and not clips.is_empty():
		for c: Variant in clips:
			if ap.has_animation(str(c)):
				ap.get_animation(str(c)).loop_mode = Animation.LOOP_LINEAR
		ap.play(str(clips[0]))
		ap.seek(randf() * 3.0, true)
		ap.speed_scale = randf_range(0.85, 1.1)
		var t := Timer.new()
		t.wait_time = randf_range(6.0, 12.0)
		t.autostart = true
		t.timeout.connect(func() -> void:
			ap.play(str(clips[randi() % clips.size()]), 0.6)
			t.wait_time = randf_range(6.0, 14.0))
		m.add_child(t)
	if col.size() == 3:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(float(col[0]), float(col[1]), float(col[2])) * sc
		cs.shape = bs
		cs.position = Vector3(0, bs.size.y * 0.5, 0)
		body.add_child(cs)
		m.add_child(body)
		rects.append([Vector2(pos.x, pos.z), Vector2(bs.size.x, bs.size.z), Color(0.5, 0.2, 0.25)])


static func _find_player(n: Node) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_player(c)
		if f != null:
			return f
	return null


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
	glass.append(m)
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
		if path.ends_with("firepit.glb") or path.ends_with("cauldron.glb"):     # живой огонь из слоёв
			var fs := 0.55 if path.ends_with("firepit.glb") else 0.32
			var fo := Vector3(0, 0.25, 0) if path.ends_with("firepit.glb") else Vector3(0, 0.05, 0)
			lights.append([vfx.fire(root, t * fo, fs, false), 2.6])
			continue
		vfx.halo(root, t * off, col, 0.9 if path.ends_with("mana_crystal.glb") else 1.1, 0.9)
		var l := OmniLight3D.new()
		l.light_color = col
		l.light_energy = 1.6
		l.omni_range = 9.0
		l.distance_fade_enabled = true                    # дальние огни не считаем
		l.distance_fade_begin = 45.0
		l.distance_fade_length = 10.0
		l.position = t * off
		root.add_child(l)
		lights.append([l, 2.8])


const CELL := 24.0
const FAR_DRAW := 220.0


## Мелкий пропс → дальность, дальше которой не рисуется (0 — обычная модель, с тенью и всегда).
func _small_prop(path: String) -> float:
	for k: Array in [["grass_tuft", 40.0], ["rock_small", 60.0], ["bush_dry", 70.0], ["fence_wood", 80.0],
			["barrel", 60.0], ["crate", 60.0], ["sack", 50.0], ["pot", 45.0], ["bucket", 45.0], ["wall_rubble", 70.0]]:
		if path.get_file().begins_with(str(k[0])):
			return float(k[1])
	return 0.0


## Модель: её сетки (со своими сдвигами внутри модели) → MultiMesh на все места; коллизии — коробки.
func _place(path: String, list: Array) -> void:
	var src := Assets.model(mod, path)
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
		# по ячейкам CELL м: у MultiMesh на весь город рамка на весь город — камера не отсекает ничего,
		# и каждый каскад тени рисует всё заново. Ячейками — рисуется только то, что в кадре.
		var cells := {}
		for i: int in list.size():
			var o: Vector3 = (list[i][0] as Transform3D).origin
			var key := Vector2i(floori(o.x / CELL), floori(o.z / CELL))
			if not cells.has(key):
				cells[key] = []
			(cells[key] as Array).append(i)
		var small := _small_prop(path)
		for key: Vector2i in cells:
			var ids: Array = cells[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = pr[0]
			mm.instance_count = ids.size()
			for j: int in ids.size():
				mm.set_instance_transform(j, (list[ids[j]][0] as Transform3D) * (pr[1] as Transform3D))
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			if small > 0.0:                               # мелочь: без тени и не рисуется вдали
				mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
				mi.visibility_range_end = small
				mi.visibility_range_end_margin = 6.0
				mi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
			else:                                         # дальше FAR_DRAW м всё равно в дымке — не рисуем
				mi.visibility_range_end = FAR_DRAW
				mi.visibility_range_end_margin = 20.0
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
	var pts: Array = []
	for e: Array in list:
		pts.append((e[0] as Transform3D).origin)
	Assets.track(path, null, pts)                        # стриминг текстур: где стоят копии
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


## Материалы блоков — общие на все блоки (раньше свой на каждый). Арена — CC0 текстуры 4K (Poly Haven, DDS:
## pax_rpg/dev/assets/tex_dds.gd): цвет 4K, нормали 2K; развёртка трипланарная по миру — без растяжений на кольцах.
const TEX_MATS := {"arena_wall": ["japanese_stone_wall", 0.33], "arena_seat": ["large_sandstone_blocks", 0.4],
	"arena_sand": ["dense_sand", 0.22]}
var _mat_cache := {}


func _block_mat(mat: String) -> StandardMaterial3D:
	if _mat_cache.has(mat):
		return _mat_cache[mat]
	var sm := StandardMaterial3D.new()
	sm.albedo_color = MATS.get(mat, MATS.stone)
	sm.roughness = 0.95
	if mat == "earth":
		sm.albedo_color = Color.WHITE
		sm.albedo_texture = mod.texture("models/gharn/tex/ground.jpg")
		sm.uv1_triplanar = true
		sm.uv1_world_triplanar = true
		sm.uv1_scale = Vector3.ONE * 0.25
	elif TEX_MATS.has(mat):
		var tm: Array = TEX_MATS[mat]
		var d := Assets._dds(mod, "textures/arena/%s_diff.dds" % tm[0])
		var n := Assets._dds(mod, "textures/arena/%s_nor.dds" % tm[0])
		sm.albedo_color = Color.WHITE
		if d != null:
			sm.albedo_texture = ImageTexture.create_from_image(d)
		if n != null:
			sm.normal_enabled = true
			sm.normal_texture = ImageTexture.create_from_image(n)
			sm.normal_scale = 1.2
		sm.uv1_triplanar = true
		sm.uv1_world_triplanar = true
		sm.uv1_scale = Vector3.ONE * float(tm[1])
		sm.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	_mat_cache[mat] = sm
	return sm


func _block(size: Vector3, pos: Vector3, mat: String, ry: float, rx: float, collide: bool) -> void:
	var basis := Basis(Vector3.UP, deg_to_rad(ry)) * Basis(Vector3.RIGHT, deg_to_rad(rx))
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _block_mat(mat)
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
