extends RefCounted
## Мир за частоколом: степь холмами до горизонта (shaders/steppe.gdshader — текстура земли, волны ветра, тени облаков),
## горные хребты кольцом (ridged-шум, shaders/mountain.gdshader — скалы слоями, снег по высоте и уклону; дымка
## тумана делает их синими и далёкими), кочевые юрты на холмах. Без коллизий — герой за стену не выходит. Высоты — шум
## (FastNoiseLite), город — в плоской «чаше» (land: [центр X, центр Z, полуширина, полуглубина]).
const Assets := preload("res://mods/pax_rpg/src/location/assets.gd")

var mod: PaxMod
var root: Node3D
var _noise := FastNoiseLite.new()
var _flat := Rect2()


func build(m: PaxMod, parent: Node3D, area: Rect2) -> void:
	mod = m
	_flat = area
	root = Node3D.new()
	root.name = "Landscape"
	parent.add_child(root)
	_noise.seed = 1047
	_noise.frequency = 0.0065
	_noise.fractal_octaves = 4
	_terrain()
	_mountains()
	_camps()


## Высота степи: в городе — ниже земли города, за стеной поднимается холмами.
func height(x: float, z: float) -> float:
	var dx := maxf(0.0, absf(x - _flat.get_center().x) - _flat.size.x * 0.5)
	var dz := maxf(0.0, absf(z - _flat.get_center().y) - _flat.size.y * 0.5)
	var d := sqrt(dx * dx + dz * dz)
	var t := smoothstep(4.0, 90.0, d)
	var hills := (_noise.get_noise_2d(x, z) * 0.5 + 0.5) * 55.0 + _noise.get_noise_2d(x * 3.1, z * 3.1) * 5.0
	return lerpf(-0.4, hills + d * 0.02, t)


func _terrain() -> void:
	var size := 1400.0
	var n := 140
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var c := _flat.get_center()
	var grass := Color(0.52, 0.55, 0.3)
	var ochre := Color(0.78, 0.6, 0.4)
	var dry := Color(0.66, 0.56, 0.42)
	for j: int in n + 1:
		for i: int in n + 1:
			var x := c.x - size * 0.5 + size * i / n
			var z := c.y - size * 0.5 + size * j / n
			var h := height(x, z)
			var k := _noise.get_noise_2d(x * 2.0 + 300.0, z * 2.0) * 0.5 + 0.5
			var col := ochre.lerp(grass, smoothstep(0.35, 0.75, k)).lerp(dry, smoothstep(18.0, 34.0, h) * 0.6)
			st.set_color(col)
			st.set_uv(Vector2(x, z) / 8.0)
			st.add_vertex(Vector3(x, h, z))
	for j: int in n:
		for i: int in n:
			var a := j * (n + 1) + i
			st.add_index(a)
			st.add_index(a + 1)
			st.add_index(a + n + 1)
			st.add_index(a + 1)
			st.add_index(a + n + 2)
			st.add_index(a + n + 1)
	st.generate_normals()
	st.generate_tangents()                               # для карты нормалей земли
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var sh: Shader = mod.shader("shaders/steppe.gdshader")
	if sh != null:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("g_col", _tex("models/gharn/tex/ground.jpg", false))
		m.set_shader_parameter("g_nrm", _tex("models/gharn/tex/ground_n.jpg", true))
		mi.material_override = m
	else:
		var mat := StandardMaterial3D.new()
		mat.vertex_color_use_as_albedo = true
		mat.albedo_texture = _tex("models/gharn/tex/ground.jpg", false)
		mat.roughness = 0.95
		mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED        # даль — не в отражённый свет (SDFGI), дорого и не видно
	root.add_child(mi)


## Картинка мода с мипмапами (без них даль рябит).
func _tex(path: String, normal: bool) -> Texture2D:
	var tex := mod.texture(path)
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


## Горы: кольцо хребтов от MOUNT_R0 до MOUNT_R1 м вокруг города — сетка в полярных координатах, высота — ridged-шум
## (острые гребни, долины между ними). Ближние хребты ниже (~150 м, без снега), дальние до ~450 м, в снегу.
## Шум берётся в декартовых X/Z — шва на 360° нет.
const MOUNT_R0 := 545.0
const MOUNT_R1 := 1550.0


func _mountains() -> void:
	var ridge := FastNoiseLite.new()
	ridge.seed = 77
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	ridge.fractal_octaves = 6
	ridge.frequency = 0.0021
	var big := FastNoiseLite.new()                       # где хребты выше, где седловины
	big.seed = 78
	big.frequency = 0.0007
	var na := 720
	var nr := 84
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for j: int in nr + 1:
		var f := float(j) / nr
		var r := lerpf(MOUNT_R0, MOUNT_R1, pow(f, 1.25))      # ближе — гуще
		var amp := lerpf(110.0, 450.0, smoothstep(600.0, 1300.0, r)) * smoothstep(MOUNT_R0, 720.0, r)
		for i: int in na:
			var a := TAU * i / na
			var x := cos(a) * r
			var z := sin(a) * r
			var v := ridge.get_noise_2d(x, z) * 0.5 + 0.5
			var b := big.get_noise_2d(x, z) * 0.5 + 0.5
			var h := -18.0 + amp * pow(v, 1.6) * (0.55 + 0.75 * b)
			st.add_vertex(Vector3(x, h, z))
	for j: int in nr:
		for i: int in na:
			var i2 := (i + 1) % na
			var a0 := j * na + i
			var a1 := j * na + i2
			var b0 := (j + 1) * na + i
			var b1 := (j + 1) * na + i2
			for k: int in [a0, b0, a1, a1, b0, b1]:
				st.add_index(k)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.name = "Mountains"
	mi.mesh = st.commit()
	var sh: Shader = mod.shader("shaders/mountain.gdshader")
	if sh != null:
		var m := ShaderMaterial.new()
		m.shader = sh
		m.set_shader_parameter("detail_n", _tex("models/gharn/tex/ground_n.jpg", true))
		mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi)


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


func yurt_y(x: float, z: float) -> float:
	return minf(minf(height(x - 2.0, z), height(x + 2.0, z)), minf(height(x, z - 2.0), height(x, z + 2.0)))
