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
	_block(Vector3(float(g[0]), 1.0, float(g[1])), Vector3(float(g[2]), -0.5, float(g[3])), "earth", 0.0, 0.0, true)
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
		(groups[k] as Array).append([Transform3D(basis, pos), bool(d.get("c", false))])
	for k: String in groups:
		_place(k, groups[k])


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
		if bool(e[1]) and not first:
			var body := StaticBody3D.new()
			var sh := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = aabb.size * t.basis.get_scale().x * 0.92
			sh.shape = bs
			sh.position = aabb.get_center() * t.basis.get_scale().x
			body.add_child(sh)
			body.transform = Transform3D(t.basis.orthonormalized(), t.origin)
			root.add_child(body)
			var sz := Vector2(bs.size.x, bs.size.z)
			rects.append([Vector2(t.origin.x, t.origin.z), sz, Color(0.22, 0.27, 0.5)])
	src.free()


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
