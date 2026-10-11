extends SceneTree
## Захват цели (голова смотрит на гоблина), гибель гоблина (тело лежит, мана летит в шкалу опыта).

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
	var gobs: Array = loc.get("_goblins")
	var pl: Node3D = loc.get("_player")
	if frame == 20 and gobs.size() > 0:
		var g: Node3D = gobs[0]
		g.set_physics_process(false)
		g.global_position = pl.global_position + Vector3(3.0, 0.0, -2.0)    # справа-спереди, под углом ~55°
		loc.call("_set_lock", g)
	if frame == 70:
		var g: Node3D = gobs[0]
		loc.set("_cine", [[pl.global_position.x - 0.2, pl.global_position.y + 1.2, pl.global_position.z - 2.4],
			[pl.global_position.x, pl.global_position.y + 0.7, pl.global_position.z]])
	if frame == 80:
		_shot("look_front")
	if frame == 85:
		loc.set("_cine", [])
		var g: Node = gobs[0]
		g.call("deathblow")
	if frame == 92:
		_shot("death_a")
	if frame == 115:
		_shot("death_b")
	if frame == 160:
		_shot("death_c")
	if frame >= 170:
		quit(0)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
