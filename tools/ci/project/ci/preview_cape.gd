extends SceneTree
## Кадры плаща героя (сзади, сбоку, спереди) на тестовой арене: --out=<папка> → cape_*.png.

var mod: Node
var out_dir := "/tmp"
var frame := 0
var loc: Node


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	root.size = Vector2i(1280, 960)
	mod = (load("res://mods/pax_rpg/main.gd") as GDScript).new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	mod.call("_mod_loaded")
	loc = mod.get("location")
	loc.call("build_test")
	process_frame.connect(_tick)


func _view(from: Vector3, to: Vector3) -> void:
	var cam: Camera3D = loc.get("_cam")
	var pl: Node3D = loc.get("_player")
	loc.set("_cine", [[pl.global_position.x + from.x, pl.global_position.y + from.y, pl.global_position.z + from.z],
		[pl.global_position.x + to.x, pl.global_position.y + to.y, pl.global_position.z + to.z]])


func _tick() -> void:
	frame += 1
	if frame == 60:
		var hh: Object = loc.get("_hero")
		print("DBG equip ", hh.call("equip", "cape_black"))
	if frame == 90:
		_view(Vector3(0, 0.9, 2.6), Vector3(0, 0.6, 0))      # сзади (герой смотрит на −Z)
	if frame == 99:
		var h: Object = loc.get("_hero")
		print("DBG hero=", h, " worn=", (h.get("_worn") as Dictionary).keys() if h else null, " items=", (h.get("_items") as Dictionary).keys() if h else null, " model=", h.get("model") if h else null)
	if frame == 100:
		_shot("cape_back")
	if frame == 101:
		_view(Vector3(2.4, 0.8, 0.3), Vector3(0, 0.6, 0))
	if frame == 110:
		_shot("cape_side")
	if frame == 111:
		_view(Vector3(0.4, 0.9, -2.2), Vector3(0, 0.7, 0))
	if frame == 120:
		_shot("cape_front")
	if frame == 125:
		var hm: Node3D = (loc.get("_hero") as Object).get("model")
		var bz := hm.global_transform.basis.z.normalized()
		var hp := hm.global_position
		var pl: Node3D = loc.get("_player")
		var o := hp - pl.global_position
		for k: int in 2:
			var d := bz * (1.6 if k == 0 else -1.6)
			loc.set("_cine", [[hp.x + d.x, hp.y + 1.5, hp.z + d.z], [hp.x, hp.y + 1.2, hp.z]])
			await process_frame
			await process_frame
			await process_frame
			_shot("cape_rear%d" % k)
	if frame == 121:
		_view(Vector3(0.9, 1.05, 1.0), Vector3(0, 0.75, 0))
	if frame == 130:
		_shot("cape_collar")
	if frame >= 140:
		quit(0)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
