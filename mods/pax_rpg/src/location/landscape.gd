extends RefCounted
## Мир за частоколом: степь холмами до горизонта, три гряды гор со снежными шапками (дымка тумана делает их
## синими и далёкими), кочевые юрты на холмах. Без коллизий — герой за стену не выходит. Высоты — шум
## (FastNoiseLite), город — в плоской «чаше» (land: [центр X, центр Z, полуширина, полуглубина]).

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
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	var tex := mod.texture("models/gharn/tex/ground.jpg")
	if tex != null:
		var img := tex.get_image()
		if img != null and not img.is_compressed() and not img.has_mipmaps():
			img.generate_mipmaps()
			tex = ImageTexture.create_from_image(img)
	mat.albedo_texture = tex
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.roughness = 0.95
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(mi)


## Горы: три кольца пиков (ближние ниже и теплее, дальние выше, голубее — дымка), снег на вершинах.
func _mountains() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 1.0
	for ring: Array in [[620.0, 16, 90.0, 170.0], [880.0, 22, 160.0, 290.0], [1180.0, 26, 240.0, 420.0]]:
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for p: int in int(ring[1]):
			var ang := TAU * (p + rng.randf_range(-0.3, 0.3)) / float(ring[1])
			var r := float(ring[0]) * rng.randf_range(0.92, 1.08)
			var h := rng.randf_range(float(ring[2]), float(ring[3]))
			var w := h * rng.randf_range(1.6, 2.4)
			_peak(st, Vector3(cos(ang) * r, -10.0, sin(ang) * r), w, h, rng)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)


func _peak(st: SurfaceTool, base: Vector3, w: float, h: float, rng: RandomNumberGenerator) -> void:
	var seg := 10
	var rings := 6
	var rock := Color(0.42, 0.38, 0.42)
	var snow := Color(0.95, 0.95, 1.0)
	var start := []
	var top := base + Vector3(rng.randf_range(-0.15, 0.15) * w, h, rng.randf_range(-0.15, 0.15) * w)
	var verts: Array = []
	for k: int in rings + 1:
		var f := float(k) / rings
		var row: Array = []
		for i: int in seg:
			var a := TAU * i / seg
			var rr := w * 0.5 * (1.0 - f) * (0.75 + 0.5 * rng.randf())
			var p := base.lerp(top, f) + Vector3(cos(a) * rr, rng.randf_range(-0.04, 0.04) * h, sin(a) * rr)
			row.append(p)
		verts.append(row)
	start = verts
	for k: int in rings:
		for i: int in seg:
			var j := (i + 1) % seg
			var q := [start[k][i], start[k + 1][i], start[k + 1][j], start[k][j]]
			for v: Vector3 in [q[0], q[1], q[2], q[0], q[2], q[3]]:
				var hf := (v.y - base.y) / h
				st.set_color(rock.lerp(snow, smoothstep(0.62, 0.72, hf + rng.randf_range(-0.03, 0.03))))
				st.add_vertex(v)


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
			var m := mod.model("models/gharn/props/" + ("yurt_large.glb" if rng.randf() < 0.3 else "yurt_small.glb"))
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
