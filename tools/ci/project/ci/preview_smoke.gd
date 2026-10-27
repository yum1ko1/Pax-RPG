extends SceneTree
## Дым из трубы (vfx.gd → smoke, клубы из симуляции со светом с 6 сторон) и жаровня рядом: --hour=<час>,
## --old — прежний дым (флипбук) для сравнения. Кадры fire_NN.png в --out=<папка>.
var mod: Node
var out_dir := "/tmp"
var hour := 13.0
var old := false
var flip := -1.0
var frame := 0
var loc: Node
var cam := Vector3.ZERO
var look := Vector3.ZERO
var vfx: Object


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		if a.begins_with("--hour="):
			hour = float(a.trim_prefix("--hour="))
		if a == "--flip":
			flip = 1.0
		if a == "--old":
			old = true
	root.size = Vector2i(1280, 720)
	seed(5)
	mod = (load("res://mods/pax_rpg/main.gd") as GDScript).new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	mod.call("_mod_loaded")
	loc = mod.get("location")
	loc.call("build_test")
	process_frame.connect(_tick)


func _box(view: Node, size: Vector3, at: Vector3, col: Color) -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = 0.9
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = m
	mi.mesh = bm
	mi.position = at
	view.add_child(mi)


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
		var base := pl.global_position + fwd * 9.0 - side * 7.0 + Vector3(0, -0.95, 0)
		var view: Node = loc.get("_view")
		if vfx == null:
			vfx = (load("res://mods/pax_rpg/src/location/vfx.gd") as GDScript).new(mod)
		if old:
			vfx.set("_mats", {"sim_smoke": vfx.call("_flip_mat", "textures/vfx/smoke_8x8.png", false, 1.0)})
		_box(view, Vector3(3.0, 4.0, 3.0), base + Vector3(0, 2.0, 0), Color(0.35, 0.3, 0.27))      # дом
		_box(view, Vector3(0.6, 1.6, 0.6), base + Vector3(0.8, 4.8, 0.4), Color(0.3, 0.26, 0.24))  # труба
		vfx.call("smoke", view, base + Vector3(0.8, 5.7, 0.4), 0.9 * 1.4, Color(0.3, 0.28, 0.3, 0.42), 13)
		_box(view, Vector3(0.7, 0.9, 0.7), base + Vector3(-2.6, 0.45, -1.0), Color(0.2, 0.19, 0.18))
		var l: OmniLight3D = vfx.call("fire", view, base + Vector3(-2.6, 0.99, -1.0), 0.75, true, true)
		l.light_energy = 2.6
		cam = base + (fwd * 9.0 - side * 1.5) * flip + Vector3(0, 2.6, 0)
		look = base + Vector3(0, 4.2, 0)
	if frame >= 30:
		loc.call("set_hour", hour)
		loc.set("_cine", [[cam.x, cam.y, cam.z], [look.x, look.y, look.z]])
	if frame >= 330 and frame < 420 and frame % 2 == 0:
		_shot("fire_%02d" % ((frame - 330) / 2))
	if frame >= 422:
		quit(0)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
