extends SceneTree
## Дымовой прогон поручения (вручную, не в CI): мод грузится как в smoke.gd, берётся поручение аргумента
## --contract=<id> (по умолчанию shepherd), строится его логово (forest.gd), бот ждёт стройки, ставит героя у лагеря,
## гоблинов лагеря убивает напрямую, проверяет «дело сделано», сдаёт поручение (награда, окно приёма, приём), затем
## гибель героя (кошель). Скриншоты lair_*.png — в --out=<папка>. Итог — «smoke: ok» или «smoke: FAIL …».
##   godot --path tools/ci/project -s res://ci/smoke_lair.gd -- --out=<папка> [--contract=beast]

const Quest := preload("res://mods/pax_rpg/src/location/quest.gd")

var frame := 0
var mod: Node
var loc: Node
var out_dir := ""
var cid := "shepherd"
var _built_at := -1


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
		elif a.begins_with("--contract="):
			cid = a.trim_prefix("--contract=")
	root.size = Vector2i(1920, 1080)
	mod = (load("res://mods/pax_rpg/main.gd") as GDScript).new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	mod.call("_mod_loaded")
	process_frame.connect(_tick)


func _fail(t: String) -> void:
	print("smoke: FAIL ", t)
	quit(1)


func _tick() -> void:
	frame += 1
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if frame == 2:
		loc = mod.get("location")
		var q := Quest.take(mod, {"id": "gharn", "lat": 0.0, "lon": 0.0}, cid, 5, "Тестовый житель")
		print("smoke: взято поручение ", q)
		if Quest.marker(mod, "gharn", 5) != "wait":
			_fail("marker после взятия: " + Quest.marker(mod, "gharn", 5))
			return
		loc.call("build", {"id": "forest", "seed": int(q.seed), "lat": 0.0, "lon": 0.0})
	if frame > 2 and _built_at < 0 and loc != null and bool(loc.call("is_ready")) and loc.get("_player") != null:
		_built_at = frame
		print("smoke: логово построено на кадре ", frame, " — ", loc.get("_city_name"))
	if _built_at < 0:
		if frame > 60000:
			_fail("логово не построилось")
		return
	var f := frame - _built_at
	if f == 30:
		var goblins: Array = loc.get("_goblins")
		var guards: Array = loc.get("_camp_guards")
		print("smoke: врагов %d, стража лагеря %d, вожак %s, пленник %s" % [goblins.size(), guards.size(),
			loc.get("_leader"), loc.get("_captive")])
		if guards.is_empty():
			_fail("нет стражи лагеря")
			return
		var cam: Node3D = loc.get("_cam")
		var p: Node3D = loc.get("_player")
		var guard0: Node3D = guards[0]
		p.global_position = guard0.global_position + Vector3(0.0, 0.5, 6.0)
		loc.set("_yaw", 0.0)
	if f == 90:
		_shot("lair_camp.png")
		for g: Variant in loc.get("_camp_guards"):
			if is_instance_valid(g):
				g.set("hp", 0.0)
				g.call("_die")
	if f == 150:
		var captive: Node3D = loc.get("_captive")
		if is_instance_valid(captive):
			(loc.get("_player") as Node3D).global_position = captive.global_position + Vector3(0.0, 0.5, 1.2)
	if f == 220:
		var q := Quest.get_q(mod)
		print("smoke: состояние поручения ", q.get("state", ""))
		if str(q.get("state", "")) != "found":
			_fail("дело не засчитано")
			return
		var gold0 := int((loc.get("_prog") as Object).get("gold"))
		var done := Quest.complete(mod)
		loc.call("_contract_reward", done)
		loc.call("_perk_try")
		var pp: Control = loc.get("_perk_pick")
		print("smoke: золото %d → %d, приёмы на выбор %s" % [gold0, int((loc.get("_prog") as Object).get("gold")), pp.get("choices")])
		if not pp.visible or (pp.get("choices") as Array).size() != 2:
			_fail("окно приёма не открылось")
			return
	if f == 240:
		_shot("lair_perk.png")
		loc.get("_perk_pick").call("key", KEY_1)
		var perks: Array = (loc.get("_prog") as Object).get("perks")
		print("smoke: приёмы героя ", perks, ", сдано ", Quest.done_list(mod), ", спасённые ", Quest.rescued(mod, "gharn"))
		if perks.is_empty():
			_fail("приём не взят")
			return
	if f == 260:
		(loc.get("_prog") as Object).call("add_gold", 100)
		loc.set("_hp", 0.0)
		loc.call("_hero_down_check", null)
		var pr := Quest.purse(mod)
		print("smoke: гибель — кошель ", pr)
		if pr.is_empty() or not is_instance_valid(loc.get("_purse")):
			_fail("кошель не оставлен")
			return
	if f == 300:
		var purse: Node3D = loc.get("_purse")
		(loc.get("_player") as Node3D).global_position = purse.global_position + Vector3(0.0, 0.9, 0.0)
	if f == 340:
		if not Quest.purse(mod).is_empty():
			_fail("кошель не подобран")
			return
		print("smoke: кошель подобран, золото ", (loc.get("_prog") as Object).get("gold"))
		print("smoke: ok")
		quit(0)


func _shot(name: String) -> void:
	if out_dir != "" and DisplayServer.get_name() != "headless":
		var img := root.get_texture().get_image()
		if img != null:
			img.save_png(out_dir.path_join(name))
			print("smoke: скриншот ", name)
