extends SceneTree
var mod: Node
var out_dir := "/tmp"
var frame := 0
var loc: Node


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	root.size = Vector2i(1280, 720)
	mod = (load("res://mods/pax_rpg/main.gd") as GDScript).new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	mod.call("_mod_loaded")
	loc = mod.get("location")
	loc.call("build_test")
	process_frame.connect(_tick)


func _tick() -> void:
	frame += 1
	if frame == 30:
		_shot("help_closed")
	if frame == 32:
		(loc.get("_help") as Node).call("set_open", true)
	if frame == 40:
		_shot("help_open")
	if frame >= 45:
		quit(0)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
