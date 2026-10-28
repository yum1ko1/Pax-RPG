extends SceneTree
## Видео приёма «Иай: остановка времени» вне игры: тестовая арена мода с гоблинами, герой с мечом, V — приём.
## Каждый кадр — PNG в --out=<папка>; дальше tools/preview/iai_video.sh склеивает видео и звук (по строкам iai_sound).
##   xvfb-run godot --path tools/ci/project --rendering-driver opengl3 --fixed-fps 30 -s res://ci/preview_iai.gd -- --out=DIR

var frame := 0
var mod: Node
var out_dir := ""
var loc: Node
const START := 70
const LEN := 600


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	root.size = Vector2i(1280, 720)
	mod = (load("res://mods/pax_rpg/main.gd") as GDScript).new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	mod.call("_mod_loaded")
	var commands: Dictionary = root.get_node("Pax").get("commands")
	(commands["rpg_arena"] as Callable).call_deferred(PackedStringArray())
	process_frame.connect(_tick)


func _tick() -> void:
	frame += 1
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	loc = mod.get("location")
	if frame == 20:                                     # меч в руки
		_key(KEY_F, true)
	if frame == 24:
		_key(KEY_F, false)
	if frame == START:
		print("iai_start ", frame)
		_key(KEY_V, true)
	if frame == START + 2:
		_key(KEY_V, false)
	if frame == START + 4:
		var iai: Node = loc.get("_iai")
		var hero: Object = loc.get("_hero")
		print("iai_debug active=%s cd=%s action=%s floor=%s stagger=%s" % [iai.get("active") if iai else "null",
			loc.get("_iai_cd"), hero.get("action") if hero else "-", (loc.get("_player") as CharacterBody3D).is_on_floor(),
			loc.get("_stagger")])
	if frame >= START - 10 and frame < START + LEN and out_dir != "":
		var img := root.get_texture().get_image()
		img.save_jpg(out_dir.path_join("f_%04d.jpg" % (frame - START + 10)), 0.9)
	if frame >= START + LEN:
		print("preview: done")
		quit()


func _key(k: int, down: bool) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = k
	e.keycode = k
	e.pressed = down
	Input.parse_input_event(e)
