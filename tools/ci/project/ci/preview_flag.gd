extends SceneTree
## Знамя Гхарна крупно (Аллея).
var mod: Node
var out_dir := "/tmp"
var frame := 0
var loc: Node


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	root.size = Vector2i(960, 720)
	mod = (load("res://mods/pax_rpg/main.gd") as GDScript).new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	mod.call("_mod_loaded")
	loc = mod.get("location")
	loc.call("build", {"id": "gharn"})
	process_frame.connect(_tick)


func _tick() -> void:
	frame += 1
	if frame < 55:
		loc.set("_cine", [[-62.0, 3.6, -1.5], [-65.5, 3.6, -7.5]])
	if frame == 40:
		_shot("flag_a")
	if frame == 55:
		loc.set("_cine", [[-55.0, 2.0, 3.0], [-67.0, 3.5, -7.0]])
	if frame == 70:
		_shot("flag_b")
	if frame >= 75:
		quit(0)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
