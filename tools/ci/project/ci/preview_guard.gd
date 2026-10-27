extends SceneTree
## Защита в бою (hit_vfx.gd): --fx=parry|block|trail — эффект перед героем Тянь Лун, камера сбоку-сзади;
## --col=red|pink — энергия копья или меча, --hour=<час>. Кадры fx_NN.png в --out=<папка>.

var mod: Node
var out_dir := "/tmp"
var fx := "parry"
var col := Color(1.0, 0.08, 0.16)
var frame := 0
var hour := -1.0
var loc: Node
var at := Vector3.ZERO
var fwd := Vector3.FORWARD
const GO := 120


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		if a.begins_with("--fx="):
			fx = a.trim_prefix("--fx=")
		if a.begins_with("--hour="):
			hour = float(a.trim_prefix("--hour="))
		if a == "--col=pink":
			col = Color(1.0, 0.35, 0.75)
	root.size = Vector2i(1280, 720)
	seed(3)
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
	var pl: Node3D = loc.get("_player")
	if frame == 30:
		for g: Variant in loc.get("_goblins"):
			(g as Node3D).global_position += Vector3(0.0, -50.0, 0.0)
			(g as Node3D).set_physics_process(false)
	if frame == 60:
		var body: Node3D = loc.get("_body_mesh")
		fwd = -body.global_transform.basis.z
		fwd.y = 0.0
		fwd = fwd.normalized()
		var side := fwd.cross(Vector3.UP)
		at = pl.global_position + fwd * 0.9 + Vector3(0.0, 1.25, 0.0)
		var c := pl.global_position - fwd * 0.6 + side * 2.8 + Vector3(0.0, 1.6, 0.0)
		var look := pl.global_position + fwd * 0.8 + Vector3(0.0, 1.2, 0.0)
		loc.set("_cine", [[c.x, c.y, c.z], [look.x, look.y, look.z]])
	if frame >= 30 and hour >= 0.0:
		loc.call("set_hour", hour)
	if frame == GO:
		var hf: Object = loc.call("_landing_fx")
		match fx:
			"parry":
				hf.call("parry", at, -fwd, col)
			"block":
				hf.call("block", at, -fwd, col)
			"trail":
				hf.call("trail", pl.global_position + Vector3(0.0, 1.2, 0.0), fwd, col, 1.0)
	if frame >= GO - 2 and frame < GO + 26:
		_shot("fx_%02d" % (frame - GO + 2))
	if frame >= GO + 30:
		quit(0)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
