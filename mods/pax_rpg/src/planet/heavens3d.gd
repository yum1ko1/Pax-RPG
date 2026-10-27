extends Node3D
## Око Раскола и луны Селунэ и Иру у глобуса — тем же расчётом, что небо локаций (sky_clock.gd): Око висит
## неподвижно между орбитами лун, луны ходят по кругам и проходят сквозь него. Узел — наш (ребёнок planet.gd, в мире
## глобуса), не ребёнок планеты игры: её детей обходят потоки игры. Каждый кадр planet.gd ставит его на место
## планеты (place): оси — как у планеты (радиус 1), но повёрнуты вокруг её оси так, что Хоэн там, где солнце игры
## (sun_dir её материала), — глобус и небо освещены одинаково.
##
## Око — квадрат в плоскости кольца с шейдером обода и вихрей маны (eye_ring.gdshader), тонкий тор поверх и осколки
## (MultiMesh, кружат и кувыркаются в шейдере eye_rocks.gdshader — без работы процессора). Луны — сферы с moon.gdshader
## (обращены к Юруме одной стороной), вокруг ореол (glow.gdshader).

const SkyClock := preload("res://mods/pax_rpg/src/sky_clock.gd")

const ROCKS := 700
const EXTENT := 2.2                # квадрат Ока — до 2.2 радиуса кольца (там гаснут вихри и ореол)
const HALO := {"selune": 5.0, "iru": 7.0}   # ширина ореола в радиусах луны
const TINT := {"selune": Color(0.25, 0.06, 0.06), "iru": Color(0.5, 0.24, 0.41)}

var _eye: Node3D
var _rock_mat: ShaderMaterial
var _moons: Dictionary = {}        # id → MeshInstance3D
var _moon_mats: Dictionary = {}    # id → ShaderMaterial
var _meshes: Array[GeometryInstance3D] = []


func setup(m: PaxMod) -> bool:
	name = "PaxRpgHeavens"
	var ring_sh: Shader = m.shader("shaders/eye_ring.gdshader")
	var rock_sh: Shader = m.shader("shaders/eye_rocks.gdshader")
	var moon_sh: Shader = m.shader("shaders/moon.gdshader")
	var glow_sh: Shader = m.shader("shaders/glow.gdshader")
	if ring_sh == null or rock_sh == null or moon_sh == null or glow_sh == null:
		m.log_error("Pax RPG: heavens shaders did not load")
		return false
	_build_eye(ring_sh, rock_sh)
	for id: String in SkyClock.MOONS:
		_build_moon(id, moon_sh, glow_sh)
	return true


## Слои отрисовки — как у планеты игры (её камера может видеть не все).
func set_layers(layers: int) -> void:
	for g: GeometryInstance3D in _meshes:
		g.layers = layers


## planet — где планета игры (радиус 1 в её осях), sun — направление на солнце в её осях, t — время мира в днях.
func place(planet: Transform3D, sun: Vector3, t: float) -> void:
	var flat := Vector3(sun.x, 0.0, sun.z)
	if flat.length_squared() < 1e-8:
		return
	flat = flat.normalized()
	var turn := Basis(Vector3.UP, atan2(-flat.z, flat.x))     # +X неба (Хоэн) → на солнце игры
	global_transform = planet * Transform3D(turn, Vector3.ZERO)
	var sun_h := turn.inverse() * sun.normalized()
	_rock_mat.set_shader_parameter("sun", _eye.basis.inverse() * sun_h)
	for id: String in _moons:
		var mi: MeshInstance3D = _moons[id]
		var p := SkyClock.moon_pos(id, t)
		var face := Basis(Vector3.UP, atan2(-p.z, p.x))            # одна сторона луны всегда к Юруме
		mi.transform = Transform3D(face, p)
		(_moon_mats[id] as ShaderMaterial).set_shader_parameter("sun", face.inverse() * sun_h)


# ---------- Око ----------

func _build_eye(ring_sh: Shader, rock_sh: Shader) -> void:
	_eye = Node3D.new()
	_eye.name = "Eye"
	var n := SkyClock.eye_normal()
	var a1 := n.cross(Vector3.UP).normalized()
	_eye.transform = Transform3D(Basis(a1, n.cross(a1), n), SkyClock.eye_center())   # z — ось кольца
	add_child(_eye)
	var r := SkyClock.EYE_R
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 2.0 * EXTENT * r
	var ring_mat := ShaderMaterial.new()
	ring_mat.shader = ring_sh
	ring_mat.set_shader_parameter("extent", EXTENT)
	_eye.add_child(_mesh(quad, ring_mat))
	var torus := TorusMesh.new()                           # обод — тонкий жгут света, видно и с ребра
	torus.inner_radius = r - 0.012
	torus.outer_radius = r + 0.012
	torus.rings = 256
	torus.ring_segments = 8
	var core := StandardMaterial3D.new()
	core.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core.albedo_color = Color(1.0, 0.96, 0.92)
	var ti := _mesh(torus, core)
	ti.rotation = Vector3(PI * 0.5, 0.0, 0.0)              # тор лежит в XZ — кладём в плоскость кольца
	_eye.add_child(ti)
	_rock_mat = ShaderMaterial.new()
	_rock_mat.shader = rock_sh
	_rock_mat.set_shader_parameter("ring_r", r)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = _ico()
	mm.instance_count = ROCKS
	var rng := RandomNumberGenerator.new()
	rng.seed = 4141
	for i: int in ROCKS:
		# радиус — гуще у обода; внутренние кружат быстрее; остальное (размер, качание, кувырок) — из seed в шейдере
		var g := (rng.randf() + rng.randf() + rng.randf() - 1.5) * 0.9
		var rr := maxf(0.2, 1.0 + g) * r
		var w := 0.28 / pow(rr / r, 1.5) * rng.randf_range(0.8, 1.2)
		mm.set_instance_transform(i, Transform3D.IDENTITY)
		mm.set_instance_custom_data(i, Color(rr, rng.randf() * TAU, w, rng.randf() * 100.0))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = _rock_mat
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mmi.custom_aabb = AABB(Vector3(-2.6, -2.6, -0.8) * r, Vector3(5.2, 5.2, 1.6) * r)   # экземпляры двигает шейдер
	_meshes.append(mmi)
	_eye.add_child(mmi)


## Осколок — икосаэдр с гранёными нормалями.
static func _ico() -> ArrayMesh:
	var t := (1.0 + sqrt(5.0)) * 0.5
	var v: Array[Vector3] = [Vector3(-1, t, 0), Vector3(1, t, 0), Vector3(-1, -t, 0), Vector3(1, -t, 0),
		Vector3(0, -1, t), Vector3(0, 1, t), Vector3(0, -1, -t), Vector3(0, 1, -t),
		Vector3(t, 0, -1), Vector3(t, 0, 1), Vector3(-t, 0, -1), Vector3(-t, 0, 1)]
	var f: Array[int] = [0, 11, 5, 0, 5, 1, 0, 1, 7, 0, 7, 10, 0, 10, 11, 1, 5, 9, 5, 11, 4, 11, 10, 2, 10, 7, 6, 7, 1, 8,
		3, 9, 4, 3, 4, 2, 3, 2, 6, 3, 6, 8, 3, 8, 9, 4, 9, 5, 2, 4, 11, 6, 2, 10, 8, 6, 7, 9, 8, 1]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i: int in range(0, f.size(), 3):
		var a := v[f[i]].normalized()
		var b := v[f[i + 1]].normalized()
		var c := v[f[i + 2]].normalized()
		st.set_normal((a + b + c).normalized())          # грань выпуклого тела — нормаль от центра
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
	return st.commit()


# ---------- луны ----------

func _build_moon(id: String, moon_sh: Shader, glow_sh: Shader) -> void:
	var size := float((SkyClock.MOONS[id] as Dictionary)["size"])
	var sphere := SphereMesh.new()
	sphere.radius = size
	sphere.height = size * 2.0
	sphere.radial_segments = 64
	sphere.rings = 32
	var mat := ShaderMaterial.new()
	mat.shader = moon_sh
	mat.set_shader_parameter("kind", 0.0 if id == "selune" else 1.0)
	var mi := _mesh(sphere, mat)
	mi.name = id.capitalize()
	add_child(mi)
	_moons[id] = mi
	_moon_mats[id] = mat
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * size * float(HALO[id])
	var gm := ShaderMaterial.new()
	gm.shader = glow_sh
	gm.set_shader_parameter("tint", TINT[id])
	mi.add_child(_mesh(quad, gm))


func _mesh(mesh: Mesh, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_meshes.append(mi)
	return mi
