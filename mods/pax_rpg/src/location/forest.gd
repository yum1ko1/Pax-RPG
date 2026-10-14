extends RefCounted
## Генератор леса для мини-заданий (quest.gd): по зерну — каждый раз другой лес. Планировка того же вида, что у города
## (config/<id>.json → city.gd строит её так же), плюс «terrain» — рельеф: холмы и лощины из шума, к краям сходит на нет
## (дальше — степь и горы landscape.gd), у входа, у выхода и у находки — ровные поляны. Деревья кучками, кусты, брёвна,
## камни и пучки травы стоят на земле (height). Земля — сетка с высотами и коллизия HeightMapShape3D (make_ground).
## Ничего не сохраняется: лес живёт, пока герой в нём; нужен снова — тот же seed даёт тот же лес.

const SIZE := 150.0                  # м, сторона квадрата леса
const STEP := 1.5                    # м, шаг сетки земли
const AMP := 7.0                     # м, перепад высот


static func noise(seed_v: int) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = seed_v
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = 0.018
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 4
	return n


## Высота земли в точке (x, z): шум, сходящий к краю, и ровные поляны flats [[x, z, r], …] на высоте 0.
static func height(n: FastNoiseLite, x: float, z: float, t: Dictionary) -> float:
	var h := n.get_noise_2d(x, z) * float(t.get("amp", AMP)) + 1.5
	var half := float(t.get("size", SIZE)) * 0.5
	var r := maxf(absf(x), absf(z)) / half
	h *= 1.0 - smoothstep(0.75, 1.0, r)
	for f: Variant in t.get("flats", []):
		var a: Array = f
		var d := Vector2(x - float(a[0]), z - float(a[1])).length()
		h = lerpf(0.0, h, smoothstep(float(a[2]), float(a[2]) * 2.2, d))
	return h


## Планировка леса (как config/gharn.json): старт, выход, находка, гоблины у неё, деревья, кусты, брёвна, камни, трава.
static func generate(seed_v: int, quest: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var half := SIZE * 0.5
	var start := Vector2(rng.randf_range(-20.0, 20.0), half - 22.0)
	var exit := start + Vector2(0.0, 7.0)
	var ang := rng.randf_range(-0.9, 0.9)
	var item := start + Vector2(sin(ang), -cos(ang)) * rng.randf_range(55.0, 80.0)
	var t := {"seed": seed_v, "size": SIZE, "amp": AMP, "flats": [[start.x, start.y, 8.0], [exit.x, exit.y, 5.0],
		[item.x, item.y, 6.0]]}
	var n := noise(seed_v)
	var items: Array = []
	var clear: Array = [[start, 9.0], [exit, 6.0], [item, 5.0]]
	var free := func(p: Vector2, r: float) -> bool:
		for c: Array in clear:
			if p.distance_to(c[0]) < float(c[1]) + r:
				return false
		return true
	# деревья — рощами: центры рощ, вокруг — стволы
	for g: int in 22:
		var gc := Vector2(rng.randf_range(-half + 8.0, half - 8.0), rng.randf_range(-half + 8.0, half - 8.0))
		for k: int in rng.randi_range(3, 8):
			var p := gc + Vector2(rng.randf_range(-9.0, 9.0), rng.randf_range(-9.0, 9.0))
			if absf(p.x) > half - 4.0 or absf(p.y) > half - 4.0 or not free.call(p, 2.0):
				continue
			var s := rng.randf_range(1.4, 2.4)
			items.append({"m": "models/gharn/flame_tree.glb", "p": [p.x, height(n, p.x, p.y, t) - 0.15, p.y],
				"r": rng.randf_range(0.0, 360.0), "s": s, "c": true, "col": [0.5 * s, 3.0, 0.5 * s]})
	var scatter := [["models/gharn/props/bush_dry.glb", 90, 0.8, 1.5, false], ["models/gharn/props/rock_small.glb", 45, 0.8, 2.6, true],
		["models/gharn/props/wood_pile.glb", 14, 0.9, 1.4, true], ["models/gharn/props/grass_tuft.glb", 260, 0.8, 1.6, false]]
	for sc: Array in scatter:
		for k: int in int(sc[1]):
			var p := Vector2(rng.randf_range(-half + 4.0, half - 4.0), rng.randf_range(-half + 4.0, half - 4.0))
			if not free.call(p, 1.0):
				continue
			var e := {"m": str(sc[0]), "p": [p.x, height(n, p.x, p.y, t) - 0.05, p.y], "r": rng.randf_range(0.0, 360.0),
				"s": rng.randf_range(float(sc[2]), float(sc[3]))}
			if bool(sc[4]):
				e["c"] = true
			items.append(e)
	return {
		"forest": true, "terrain": t, "landscape": true, "ground": [SIZE, SIZE, 0.0, 0.0],
		"start": [start.x, 1.4, start.y], "exit": [exit.x, exit.y], "exit_radius": 3.5, "goblins": 0,
		"quest_item": [item.x, item.y], "quest_goblins": int(quest.get("goblins", 2)), "items": items, "npcs": 0,
		"paths": [], "arena": [],
	}


## Земля леса: сетка с высотами (цвет — трава на ровном, земля на склонах) и коллизия HeightMapShape3D.
static func make_ground(mod: PaxMod, parent: Node3D, t: Dictionary) -> void:
	var n := noise(int(t.get("seed", 0)))
	var size := float(t.get("size", SIZE))
	var cells := int(size / STEP)
	var w := cells + 1
	var hs := PackedFloat32Array()
	hs.resize(w * w)
	for j: int in w:
		for i: int in w:
			hs[j * w + i] = height(n, -size * 0.5 + i * STEP, -size * 0.5 + j * STEP, t)
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var cols := PackedColorArray()
	var uvs := PackedVector2Array()
	verts.resize(w * w)
	norms.resize(w * w)
	cols.resize(w * w)
	uvs.resize(w * w)
	for j: int in w:
		for i: int in w:
			var k := j * w + i
			var x := -size * 0.5 + i * STEP
			var z := -size * 0.5 + j * STEP
			verts[k] = Vector3(x, hs[k], z)
			var hl := hs[j * w + maxi(i - 1, 0)]
			var hr := hs[j * w + mini(i + 1, w - 1)]
			var hd := hs[maxi(j - 1, 0) * w + i]
			var hu := hs[mini(j + 1, w - 1) * w + i]
			var nr := Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized()
			norms[k] = nr
			var slope := 1.0 - nr.y
			cols[k] = Color(0.62, 0.66, 0.42).lerp(Color(0.55, 0.45, 0.35), clampf(slope * 6.0, 0.0, 1.0))
			uvs[k] = Vector2(x, z) * 0.25
	var idx := PackedInt32Array()
	for j: int in cells:
		for i: int in cells:
			var a := j * w + i
			idx.append_array([a, a + 1, a + w, a + 1, a + w + 1, a + w])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = norms
	arr[Mesh.ARRAY_COLOR] = cols
	arr[Mesh.ARRAY_TEX_UV] = uvs
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	var tex := mod.texture("models/gharn/tex/ground.jpg")
	if tex != null:
		mat.albedo_texture = tex
	var nt := mod.texture("models/gharn/tex/ground_n.jpg")
	if nt != null:
		mat.normal_enabled = true
		mat.normal_texture = nt
	mesh.surface_set_material(0, mat)
	var mi := MeshInstance3D.new()
	mi.name = "ForestGround"
	mi.mesh = mesh
	parent.add_child(mi)
	var body := StaticBody3D.new()                        # коллизия — та же сетка высот
	var shape := CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = w
	hm.map_depth = w
	hm.map_data = hs
	shape.shape = hm
	shape.scale = Vector3(STEP, 1.0, STEP)
	body.add_child(shape)
	parent.add_child(body)
