extends SceneTree
## Кадры экрана загрузки и заставки города (для проверки глазами): --out=<папка> → loading_*.png, title_*.png.
## Запуск — как smoke (run_checks.sh копирует мод в проект), без игры: только 2D.

var mod: Node
var out_dir := "/tmp"
var frame := 0
var loading: Node
var title: Node
const SHOTS := {200: "loading_a", 262: "loading_b", 295: "loading_c", 315: "loading_d", 335: "loading_e", 355: "loading_f", 380: "loading_g", 420: "loading_h"}


func _initialize() -> void:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out_dir = a.trim_prefix("--out=")
	root.size = Vector2i(1920, 1080)
	mod = (load("res://mods/pax_rpg/main.gd") as GDScript).new()
	mod.set("id", "pax_rpg")
	root.add_child(mod)
	loading = (load("res://mods/pax_rpg/src/travel/loading.gd") as GDScript).new()
	loading.call("setup", mod)
	root.add_child(loading)
	var bg := ColorRect.new()                   # «игра» под экраном загрузки — видно, как он расползается
	bg.color = Color(0.2, 0.5, 0.3)
	bg.size = Vector2(1920, 1080)
	root.add_child(bg)
	root.move_child(bg, 0)
	loading.call("run", "Гхарн", "Степной ветер приносит запах кумыса и дыма — столица орды уже близко.", 4.0,
		func() -> void: pass, func() -> void: pass)
	process_frame.connect(_tick)


func _tick() -> void:
	frame += 1
	if SHOTS.has(frame):
		_shot(SHOTS[frame])
	if frame == 480:
		title = (load("res://mods/pax_rpg/src/location/city_title.gd") as GDScript).new()
		title.call("setup", mod, "Гхарн")
		var layer := CanvasLayer.new()
		root.add_child(layer)
		layer.add_child(title)
		title.call("play", 0.0)
	if frame == 492:
		_shot("title_a")
	if frame == 550:
		_shot("title_b")
	if frame == 840:
		_shot("title_c")
	if frame >= 880:
		quit(0)


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join(n + ".png"))
	print("shot ", n)
