extends SceneTree
## Рыцарь с мечом на ходу (новые клипы Mixamo): F — достать меч, W — вперёд, A — вбок, S — назад.

var mod: Node
var out_dir := "/tmp"
var frame := 0
var loc: Node
const STEPS := {30: ["F", true], 34: ["F", false], 90: ["W", true], 120: ["shot", "walk_armed"], 125: ["W", false],
	130: ["A", true], 160: ["shot", "strafe_l"], 165: ["A", false], 170: ["S", true], 200: ["shot", "back_armed"],
	205: ["S", false], 210: ["F", true], 214: ["F", false], 270: ["W", true], 300: ["shot", "walk"], 305: ["W", false]}


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
	loc.call("build_test")
	for g: Node in loc.get("_goblins"):
		g.process_mode = Node.PROCESS_MODE_DISABLED
		(g as Node3D).position += Vector3(30, 0, 30)
	process_frame.connect(_tick)


func _key(k: String, on: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = {"F": KEY_F, "W": KEY_W, "A": KEY_A, "S": KEY_S}[k]
	e.keycode = e.physical_keycode
	e.pressed = on
	Input.parse_input_event(e)


func _tick() -> void:
	frame += 1
	var pl: Node3D = loc.get("_player")
	if pl != null:
		loc.set("_cine", [[pl.global_position.x + 2.6, pl.global_position.y + 0.9, pl.global_position.z + 1.2],
			[pl.global_position.x, pl.global_position.y + 0.3, pl.global_position.z]])
	if STEPS.has(frame):
		var st: Array = STEPS[frame]
		if st[0] == "shot":
			_shot(st[1])
		else:
			_key(st[0], st[1])
	if frame >= 310:
		quit(0)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
