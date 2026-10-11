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


const SH := {30: [13.0, 0], 45: [13.0, 1], 60: [17.6, 2], 75: [14.0, 3], 90: [22.0, 4], 105: [22.0, 5]}


func _tick() -> void:
	frame += 1
	var cams := [[[-3.0, 2.4, 44.0], [-8.0, 1.6, 47.0]], [[26.0, 5.0, 9.0], [34.0, 2.6, 0.0]],
		[[-28.0, 14.0, 70.0], [-55.0, 2.0, 50.0]], [[0.0, 9.0, 78.0], [0.0, 14.0, 320.0]],
		[[0.0, 2.2, 66.0], [0.0, 3.0, 20.0]], [[60.0, 10.0, -2.0], [54.0, 5.0, -22.0]]]
	for f: int in SH:
		if frame >= f - 10 and frame <= f:
			loc.call("set_hour", float(SH[f][0]))
			loc.set("_cine", cams[int(SH[f][1])])
		if frame == f:
			_shot("dn_%d" % f)
	if frame >= 110:
		quit(0)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
