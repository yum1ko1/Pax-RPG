extends SceneTree
## Кадры нового инвентаря (для проверки глазами) без игры: --out=<папка> → inv_*.png. Курсор водится по слотам:
## подсказка вещи, закрепление, мини-подсказка стата, выбор вещи, приём, пассив, репутация, ранг.
## Запуск — как smoke (run_checks.sh копирует мод в проект): xvfb-run … -s res://ci/preview_inventory.gd -- --out=…

var mod: Node
var inv: Control
var out_dir := "/tmp"
var frame := 0
# кадр → [действие, аргумент]
const STEPS := {
	20: ["shot", "inv_a"],
	25: ["move", Vector2(1160, 280)],          # нагрудник (координаты макета 1536 × 1024)
	45: ["shot", "inv_b_tip"],
	130: ["shot", "inv_c_pinned"],
	135: ["move", "stat0"],
	150: ["shot", "inv_d_mini"],
	160: ["click", Vector2(1020, 450)],        # перчатки — выбор вещи
	180: ["shot", "inv_e_menu"],
	185: ["key_esc", null],
	190: ["move", Vector2(800, 30)],
	200: ["move", Vector2(488, 363)],          # приём основного оружия
	290: ["shot", "inv_f_skill"],
	300: ["move", Vector2(800, 30)],
	310: ["move", Vector2(605, 194)],          # пассив
	330: ["shot", "inv_g_passive"],
	340: ["move", Vector2(800, 30)],
	350: ["move", Vector2(830, 847)],          # репутация
	440: ["shot", "inv_h_rep"],
	450: ["move", Vector2(800, 30)],
	460: ["move", Vector2(652, 847)],          # ранг
	480: ["shot", "inv_i_rank"],
	490: ["move", Vector2(800, 30)],
	500: ["click", Vector2(413, 414)],         # смена оружия
	540: ["shot", "inv_j_swap"],
}


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	root.size = Vector2i(1920, 1080)
	mod = (load("res://mods/pax_rpg/main.gd") as GDScript).new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	inv = (load("res://mods/pax_rpg/src/location/inventory.gd") as GDScript).new()
	inv.call("setup", mod)
	root.add_child(inv)
	var st := {"level": 14, "gold": 1250, "main_stat": "agility", "stat_points": 2,
		"attributes": {"agility": 60, "intellect": 30, "charisma": 50, "strength": 30, "smithing": 30, "inlay": 40, "luck": 30}}
	inv.call("open", null, null, null, null, st)
	process_frame.connect(_tick)


func _to_screen(p: Vector2) -> Vector2:
	var fr: Control = inv.get("_frame")
	return fr.get_global_transform() * p


func _move(p: Vector2) -> void:
	var sp := _to_screen(p)
	root.warp_mouse(sp)
	var e := InputEventMouseMotion.new()
	e.position = sp
	e.global_position = sp
	Input.parse_input_event(e)


func _tick() -> void:
	frame += 1
	if not STEPS.has(frame):
		if frame > 560:
			quit(0)
		return
	var s: Array = STEPS[frame]
	match str(s[0]):
		"shot":
			_shot(str(s[1]))
		"move":
			if s[1] is String:                 # на первую строку стата закреплённой подсказки
				var tip: Control = inv.get("_tip")
				var lines: Array = tip.get("lines") if tip != null else []
				if not lines.is_empty():
					var r: Rect2 = lines[0]["rect"]
					_move(tip.position + (r.position + r.size * 0.5) * tip.scale.x)
			else:
				_move(s[1])
		"click":
			_move(s[1])
			var sp := _to_screen(s[1])
			for down: bool in [true, false]:
				var e := InputEventMouseButton.new()
				e.button_index = MOUSE_BUTTON_LEFT
				e.pressed = down
				e.position = sp
				e.global_position = sp
				Input.parse_input_event(e)
		"key_esc":
			inv.call("back")


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
