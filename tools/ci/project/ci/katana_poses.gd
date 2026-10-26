extends SceneTree
## Подбор позы катаны прокрутки: кадры её SubViewport (roll.gd) в разных поворотах → --out=<папка>/pose_*.png.

var roll: Control
var out_dir := "/tmp"
var poses: Array = []
var i := -1
var wait := 0


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	var mod: Node = (load("res://mods/pax_rpg/main.gd") as GDScript).new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	var loot: Control = (load("res://mods/pax_rpg/src/location/loot/loot.gd") as GDScript).new()
	loot.call("setup", mod)
	root.add_child(loot)
	roll = (loot.get("_rolls") as Array)[0]
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(ProjectSettings.globalize_path("res://mods/pax_rpg/models/weapons/katana.glb"), st) == OK:
		var kat := doc.generate_scene(st) as Node3D
		roll.call("set_katana", kat)
	var d := deg_to_rad(1.0)
	# [имя, yaw, pitch, roll вокруг клинка]
	for p: Array in [["A", 0, -25, -90], ["B", 20, -25, -90], ["C", 35, -35, -90], ["D", -35, -35, -90], ["E", 0, -25, 90],
			["F", 0, -65, 0], ["G", 35, -15, -90], ["H", 60, -20, -90]]:
		poses.append([p[0], Basis(Vector3.UP, float(p[1]) * d) * Basis(Vector3.RIGHT, float(p[2]) * d) * Basis(Vector3.BACK, float(p[3]) * d)])
	(roll.get("_vp") as SubViewport).render_target_update_mode = SubViewport.UPDATE_ALWAYS
	process_frame.connect(_tick)


func _tick() -> void:
	wait -= 1
	if wait > 0:
		return
	if i >= 0:
		await RenderingServer.frame_post_draw
		(roll.get("_vp") as SubViewport).get_texture().get_image().save_png(out_dir.path_join("pose_%s.png" % poses[i][0]))
	i += 1
	if i >= poses.size():
		quit(0)
		return
	var k: Node3D = roll.get("_kat")
	k.position = Vector3.ZERO
	k.basis = poses[i][1]
	wait = 3
