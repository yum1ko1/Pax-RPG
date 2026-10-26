extends SceneTree
## Удар копьём Тянь Лун (Attack1) с новыми эффектами (hit_vfx.gd): гоблин прямо перед героем, камера сбоку-сзади,
## кадры вокруг мига укола — hit_NN.png в --out=<папка>.

var mod: Node
var out_dir := "/tmp"
var frame := 0
var loc: Node
var game_cam := false                # --cam=game — камера игрока (за спиной), иначе сбоку
var press := 170                    # первый клик (кадр 90) — достать копьё, второй — укол


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		if a == "--cam=game":
			game_cam = true
	root.size = Vector2i(1280, 720)
	seed(7)                                  # гоблин блокирует по randf — с этим зерном укол попадает
	mod = (load("res://mods/pax_rpg/main.gd") as GDScript).new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	mod.call("_mod_loaded")
	mod.call("set_setting", "character", "tian_long")
	loc = mod.get("location")
	loc.call("build_test")
	process_frame.connect(_tick)


func _tick() -> void:
	frame += 1
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	var gobs: Array = loc.get("_goblins")
	var pl: Node3D = loc.get("_player")
	if frame == 30 and gobs.size() > 0:
		var g: Node3D = gobs[0]
		g.set_physics_process(false)
		var body: Node3D = loc.get("_body_mesh")
		var fwd := -body.global_transform.basis.z
		fwd.y = 0.0
		g.global_position = pl.global_position + fwd.normalized() * 2.2
		for i: int in range(1, gobs.size()):
			(gobs[i] as Node3D).global_position += Vector3(0.0, -50.0, 0.0)
		loc.call("_set_lock", g)
	if frame == 60 and gobs.size() > 0 and not game_cam:
		var body: Node3D = loc.get("_body_mesh")
		var fwd := -body.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var side := fwd.cross(Vector3.UP)
		var c := pl.global_position + fwd * 0.3 + side * 4.6 + Vector3(0.0, 1.5, 0.0)
		var at := pl.global_position + fwd * 1.2 + Vector3(0.0, 1.0, 0.0)
		loc.set("_cine", [[c.x, c.y, c.z], [at.x, at.y, at.z]])
	if frame == press or frame == 90:
		var m := InputEventMouseButton.new()
		m.button_index = MOUSE_BUTTON_LEFT
		m.pressed = true
		Input.parse_input_event(m)
		var up := m.duplicate() as InputEventMouseButton
		up.pressed = false
		Input.parse_input_event(up)
	var hero: Object = loc.get("_hero")
	if frame >= press and frame <= press + 60 and frame % 4 == 0 and hero != null:
		print("f ", frame, " action=", hero.get("action"), " pl=", pl.global_position, " gob=", (gobs[0] as Node3D).global_position)
	var hf: Object = loc.get("_hitfx")
	if hf != null and frame % 2 == 0:
		for e: Dictionary in hf.get("_live"):
			print("  fx ", frame, " ", e.kind, " t=", snappedf(float(e.t), 0.01), " at=", (e.n as Node3D).global_position)
	if frame >= press + 20 and frame <= press + 62 and (frame - press) % 2 == 0:
		_shot("hit_%02d" % (frame - press))
	if frame >= press + 70:
		quit(0)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
