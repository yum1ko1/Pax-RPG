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
	if frame < 60:
		loc.set("_cine", [[16.0, 7.0, 50.0], [32.0, 1.0, 33.0]])
	else:
		loc.set("_cine", [[27.0, 2.2, 47.5], [32.0, 1.2, 33.0]])
	if frame == 50:
		_shot("yard_a")
	if frame == 75:
		_shot("yard_b")
	if frame >= 80:
		quit(0)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
