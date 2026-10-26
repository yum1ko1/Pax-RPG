extends SceneTree
## Огонь жаровни: слева — прежний (шум на плоскости + флипбук), справа — из симуляции газа (vfx.gd → sim_flame).
## --hour=<час> (21 — ночь), --mode=pair|new (new — один новый огонь крупно). Кадры fire_NN.png в --out=<папка>.
var mod: Node
var out_dir := "/tmp"
var hour := 21.0
var mode := "pair"
var frame := 0
var loc: Node
var cam := Vector3.ZERO
var look := Vector3.ZERO


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		if a.begins_with("--hour="):
			hour = float(a.trim_prefix("--hour="))
		if a.begins_with("--mode="):
			mode = a.trim_prefix("--mode=")
	root.size = Vector2i(1280, 720)
	seed(5)
	mod = (load("res://mods/pax_rpg/main.gd") as GDScript).new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	mod.call("_mod_loaded")
	loc = mod.get("location")
	loc.call("build_test")
	process_frame.connect(_tick)


func _brazier(at: Vector3, sim: bool) -> void:
	var view: Node3D = loc.get("_view")
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.2, 0.19, 0.18)
	stone.roughness = 0.9
	for b: Array in [[Vector3(0.7, 0.9, 0.7), 0.45], [Vector3(0.95, 0.18, 0.95), 0.99]]:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b[0]
		bm.material = stone
		mi.mesh = bm
		mi.position = at + Vector3(0, float(b[1]), 0)
		view.add_child(mi)
	var vfx: Object = loc.get("_vfx")
	var l: OmniLight3D = vfx.call("fire", view, at + Vector3(0, 1.08, 0), 0.75, true, sim)
	l.light_energy = 2.6


func _tick() -> void:
	frame += 1
	var pl: Node3D = loc.get("_player")
	if frame == 30:
		for g: Variant in loc.get("_goblins"):
			(g as Node3D).global_position += Vector3(0.0, -50.0, 0.0)
			(g as Node3D).set_physics_process(false)
		var body: Node3D = loc.get("_body_mesh")
		var fwd := -body.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var side := fwd.cross(Vector3.UP)
		var base := pl.global_position + fwd * 4.0 + Vector3(0, -0.95, 0)
		if mode == "pair":
			_brazier(base - side * 1.3, false)
			_brazier(base + side * 1.3, true)
			cam = base - fwd * 3.6 + Vector3(0, 1.6, 0)
			look = base + Vector3(0, 1.4, 0)
		else:
			_brazier(base, true)
			cam = base - fwd * 2.4 + Vector3(0, 1.4, 0)
			look = base + Vector3(0, 1.5, 0)
	if frame >= 30:
		loc.call("set_hour", hour)
		loc.set("_cine", [[cam.x, cam.y, cam.z], [look.x, look.y, look.z]])
	if frame >= 120 and frame < 210 and frame % 2 == 0:
		_shot("fire_%02d" % ((frame - 120) / 2))
	if frame >= 212:
		quit(0)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
