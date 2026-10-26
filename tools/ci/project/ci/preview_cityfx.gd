extends SceneTree
## Огни и дым города (vfx.gd) крупно: --what=fire — ближайший к центру живой огонь (жаровня, кузня), ночью и днём;
## --what=smoke — дым из трубы кузни. Кадры fx_<what>_NN.png в --out=<папка>.
var mod: Node
var out_dir := "/tmp"
var what := "fire"
var hour := 21.0
var frame := 0
var loc: Node
var target := Vector3.ZERO
var cam := Vector3.ZERO


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		if a.begins_with("--what="):
			what = a.trim_prefix("--what=")
		if a.begins_with("--hour="):
			hour = float(a.trim_prefix("--hour="))
	root.size = Vector2i(1280, 720)
	seed(3)
	mod = (load("res://mods/pax_rpg/main.gd") as GDScript).new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	mod.call("_mod_loaded")
	loc = mod.get("location")
	loc.call("build", {"id": "gharn"})
	process_frame.connect(_tick)


func _pick() -> void:
	var city: Object = loc.get("_city")
	if what == "smoke":
		var best: Node3D = null
		for p: Variant in city.get("smoke"):
			var n := p as Node3D
			if n != null and is_instance_valid(n) and (best == null or n.global_position.y > best.global_position.y):
				best = n
		target = best.global_position + Vector3(0, 2.5, 0)
		cam = target + Vector3(9.0, 1.0, 12.0)
		return
	var best_l: Node3D = null
	for e: Variant in city.get("lights"):
		var l := (e as Array)[0] as Node3D
		if l == null or not is_instance_valid(l) or not l.get_script():
			continue
		if float((e as Array)[1]) < 2.5:
			continue
		if best_l == null or l.global_position.length() < best_l.global_position.length():
			best_l = l
	target = best_l.global_position
	var d := Vector3(target.x, 0, target.z).normalized()
	if d.length() < 0.1:
		d = Vector3(0, 0, 1)
	cam = target + d * 3.2 + Vector3(0, 0.6, 0)
	print("fire at ", target)


func _tick() -> void:
	frame += 1
	if frame == 20:
		_pick()
	if frame >= 20:
		loc.call("set_hour", hour)
		loc.set("_cine", [[cam.x, cam.y, cam.z], [target.x, target.y, target.z]])
	if frame >= 60 and frame <= 90 and frame % 6 == 0:
		_shot("fx_%s_%02d" % [what, frame - 60])
	if frame > 92:
		quit(0)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
