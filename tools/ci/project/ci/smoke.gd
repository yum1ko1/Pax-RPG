extends SceneTree
## Дымовой прогон: мод загружается как в игре (main.gd → _mod_loaded), пункт меню «Тест: арена» открывает арену
## с настоящими моделями, бот 9 секунд жмёт клавиши — ходьба, меч, комбо, захват, блок, уворот, эликсир.
## Ошибки выполнения Godot печатает как «SCRIPT ERROR» — run_checks.sh их ловит. С экраном (xvfb) — скриншот
## arena.png в папку из аргумента --out=<папка> (после «--»).

const SCRIPT := [
	[20, "key", KEY_W, true], [110, "key", KEY_W, false],
	[120, "key", KEY_F, true], [124, "key", KEY_F, false],
	[200, "lmb"], [216, "lmb"], [232, "lmb"],
	[330, "key", KEY_Q, true], [334, "key", KEY_Q, false],
	[360, "rmb", true], [400, "rmb", false],
	[420, "key", KEY_ALT, true], [424, "key", KEY_ALT, false],
	[470, "key", KEY_R, true], [474, "key", KEY_R, false],
	[480, "key", KEY_A, true], [520, "key", KEY_A, false],
	[530, "lmb"], [546, "lmb"],
]
const END := 600

var frame := 0
var mod: Node
var out_dir := ""


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	root.size = Vector2i(1920, 1080)
	var main_script := load("res://mods/pax_rpg/main.gd") as GDScript
	if main_script == null:
		print("smoke: FAIL main.gd не загрузился")
		quit(1)
		return
	mod = main_script.new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	mod.call("_mod_loaded")
	var pax := root.get_node_or_null("Pax")
	var items: Dictionary = pax.get("menu_items") if pax != null else {}
	if not items.has("pax_rpg_test"):
		print("smoke: FAIL нет пункта меню pax_rpg_test")
		quit(1)
		return
	(items["pax_rpg_test"] as Callable).call()
	process_frame.connect(_tick)


func _tick() -> void:
	frame += 1
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	for step: Array in SCRIPT:
		if int(step[0]) == frame:
			_do(step)
	if frame == 60:
		var loc: Node = mod.get("location")
		if loc == null or not bool(loc.get("active")):
			print("smoke: FAIL арена не открылась")
			quit(1)
			return
	if frame == END:
		var loc: Node = mod.get("location")
		print("smoke: hp=%s kills=%s flask=%s lock=%s" % [loc.get("_hp"), loc.get("_kills"), loc.get("_flask"),
			loc.get("_lock")])
		if out_dir != "" and DisplayServer.get_name() != "headless":
			var img := root.get_texture().get_image()
			if img != null:
				img.save_png(out_dir.path_join("arena.png"))
				print("smoke: скриншот ", out_dir.path_join("arena.png"))
		print("smoke: ok")
		quit(0)


func _do(step: Array) -> void:
	match str(step[1]):
		"key":
			var k := InputEventKey.new()
			k.keycode = int(step[2])
			k.physical_keycode = int(step[2])
			k.pressed = bool(step[3])
			Input.parse_input_event(k)
		"lmb", "rmb":
			var m := InputEventMouseButton.new()
			m.button_index = MOUSE_BUTTON_LEFT if str(step[1]) == "lmb" else MOUSE_BUTTON_RIGHT
			m.pressed = true if str(step[1]) == "lmb" else bool(step[2])
			Input.parse_input_event(m)
			if str(step[1]) == "lmb":
				var up := m.duplicate() as InputEventMouseButton
				up.pressed = false
				Input.parse_input_event(up)
