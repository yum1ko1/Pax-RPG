extends SceneTree
## Приземления спецприёмов (hit_vfx.gd → landing): --who=orc — прыжок орка-чемпиона (JumpAttack) перед героем,
## --who=knight — удар «Сокрушения» рыцаря о землю (_ult_wave 1 и 2). Кадры land_NN.png в --out=<папка>.

var mod: Node
var out_dir := "/tmp"
var who := "orc"
var frame := 0
var loc: Node
var orc: Node3D
var t0 := -1


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		if a.begins_with("--who="):
			who = a.trim_prefix("--who=")
	root.size = Vector2i(1280, 720)
	seed(7)
	mod = (load("res://mods/pax_rpg/main.gd") as GDScript).new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	mod.call("_mod_loaded")
	loc = mod.get("location")
	loc.call("build_test")
	process_frame.connect(_tick)


func _tick() -> void:
	frame += 1
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var pl: Node3D = loc.get("_player")
	var body: Node3D = loc.get("_body_mesh")
	var fwd := -body.global_transform.basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var side := fwd.cross(Vector3.UP)
	if frame == 30:
		for g: Variant in loc.get("_goblins"):
			(g as Node3D).global_position += Vector3(0.0, -50.0, 0.0)   # гоблины не мешают кадру
			(g as Node3D).set_physics_process(false)
		if who == "orc":
			loc.call("spawn_orc")
			var gs: Array = loc.get("_goblins")
			orc = gs[gs.size() - 1]
			orc.global_position = pl.global_position + fwd * 7.0 + Vector3(0.0, -0.9, 0.0)
	if frame == 60:
		var at := pl.global_position + fwd * (4.0 if who == "orc" else 2.4)
		var c := pl.global_position - fwd * 2.5 + side * 6.5 + Vector3(0.0, 2.6, 0.0)
		loc.set("_cine", [[c.x, c.y, c.z], [at.x, at.y - 0.4, at.z]])
	if frame == 110:
		if who == "orc" and is_instance_valid(orc):
			orc.call("_start_attack", "JumpAttack")
		else:
			loc.call("_ult_wave", 1)
			t0 = frame
	if who == "orc" and t0 < 0 and frame > 110 and is_instance_valid(orc) and bool(orc.get("_slam_done")):
		t0 = frame
	if who == "knight" and t0 > 0 and frame == t0 + 11:
		loc.call("_ult_wave", 2)
	if t0 > 0 and frame >= t0 - 4 and frame <= t0 + 44 and (frame - t0) % 2 == 0:
		_shot("land_%02d" % (frame - t0 + 4))
	if (t0 > 0 and frame > t0 + 50) or frame > 400:
		quit(0)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
